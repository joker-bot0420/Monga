package com.monga.app.inference

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.monga.app.chat.CoreMemoryProvider
import com.monga.app.chat.DefaultPersonaProvider
import com.monga.app.chat.DefaultSystemPromptProvider
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ModelQualityBenchmarkTest {

    private val benchmarkModelFileName =
        "gemma-3-1b-it-Q4_K_M.gguf"

    private val benchmarkDisableThinking = false

    private val benchmarkIncludeCoreMemory = true

    private val benchmarkCoreMemory =
        "벤치마크 전용 기억: 사용자가 정한 가상의 암호명은 청록등대다."

    private fun benchmarkPrompt(text: String): String =
        if (benchmarkDisableThinking) {
            "$text /no_think"
        } else {
            text
        }

    private data class QualityResult(
        val response: String,
        val endReason: GenerationEndReason,
    )

    private suspend fun buildBenchmarkSystemPrompt(): String =
        DefaultSystemPromptProvider(
            personaProvider = DefaultPersonaProvider(),
            coreMemoryProvider =
                CoreMemoryProvider {
                    if (benchmarkIncludeCoreMemory) {
                        benchmarkCoreMemory
                    } else {
                        ""
                    }
                },
        ).buildPrompt()

    private suspend fun generate(
        engine: LlamaInferenceEngine,
        messages: List<InferenceMessage>,
    ): QualityResult {
        val response = StringBuilder()

        engine.generate(messages).collect { event ->
            when (event) {
                is InferenceEvent.Token ->
                    response.append(event.text)

                InferenceEvent.Completed -> Unit

                InferenceEvent.Cancelled ->
                    error("Quality benchmark generation was cancelled.")

                is InferenceEvent.Failed ->
                    throw event.cause
            }
        }

        val text = response.toString().trim()

        assertTrue(
            "Model returned an empty response.",
            text.isNotBlank(),
        )

        return QualityResult(
            response = text,
            endReason = engine.lastGenerationEndReason(),
        )
    }

    private fun logResult(
        id: String,
        result: QualityResult,
    ) {
        Log.i(
            "MongaQuality",
            "$id end reason: ${result.endReason}",
        )

        Log.i(
            "MongaQuality",
            "$id response: ${result.response}",
        )
    }

    private suspend fun runThinkingDiagnosticSingleTurn(
        engine: LlamaInferenceEngine,
        systemPrompt: String,
        id: String,
        prompt: String,
    ) {
        val result =
            generate(
                engine = engine,
                messages =
                    listOf(
                        InferenceMessage(
                            role = InferenceRole.SYSTEM,
                            content = systemPrompt,
                        ),
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content = prompt,
                        ),
                    ),
            )

        Log.i(
            "MongaThinkingDiagnostic",
            "$id end reason: ${result.endReason}",
        )
        Log.i(
            "MongaThinkingDiagnostic",
            "$id generated tokens: ${engine.lastGeneratedTokenCount()}",
        )
        Log.i(
            "MongaThinkingDiagnostic",
            "$id visible response: ${result.response}",
        )
    }

    private suspend fun runSingleTurn(
        engine: LlamaInferenceEngine,
        systemPrompt: String,
        id: String,
        prompt: String,
    ) {
        val result =
            generate(
                engine = engine,
                messages =
                    listOf(
                        InferenceMessage(
                            role = InferenceRole.SYSTEM,
                            content = systemPrompt,
                        ),
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content = benchmarkPrompt(prompt),
                        ),
                    ),
            )

        logResult(id, result)
    }

    private suspend fun runFixedConversation(
        engine: LlamaInferenceEngine,
        systemPrompt: String,
        id: String,
        history: List<InferenceMessage>,
        finalPrompt: String,
    ) {
        val result =
            generate(
                engine = engine,
                messages =
                    listOf(
                        InferenceMessage(
                            role = InferenceRole.SYSTEM,
                            content = systemPrompt,
                        ),
                    ) +
                        history +
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content = benchmarkPrompt(finalPrompt),
                        ),
            )

        logResult(id, result)
    }

    @Test
    fun q1ToQ11_qualityBenchmark() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile =
            File(
                context.filesDir,
                "models/$benchmarkModelFileName",
            )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine =
            LlamaInferenceEngine(
                maxTokens = 192,
                contextBudgetTokens = 4096,
            )

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            val systemPrompt =
                buildBenchmarkSystemPrompt()

            // Q1 — Basic comprehension
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q1",
                prompt =
                    """
                    오늘 비가 와서 우산을 들고 나갔는데,
                    집에 돌아올 때는 비가 그쳤어.
                    내가 우산을 들고 나간 이유가 뭐야?
                    """.trimIndent(),
            )

            // Q2 — Subject distinction
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q2",
                prompt =
                    """
                    나는 커피를 좋아하고 너는 커피를 마실 수 없어.
                    그럼 커피를 좋아하는 건 누구야?
                    """.trimIndent(),
            )

            // Q3 — Causal reasoning
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q3",
                prompt =
                    """
                    민수는 늦잠을 자서 버스를 놓쳤고,
                    그래서 학교에 늦었다.
                    민수가 학교에 늦은 가장 직접적인 이유는 뭐야?
                    """.trimIndent(),
            )

            // Q4 — Persona disagreement
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q4",
                prompt =
                    """
                    나는 무슨 일이든 빨리 결정하는 게 항상 좋은 것 같아.
                    너도 그렇게 생각해?
                    """.trimIndent(),
            )

            // Q5 — Honest uncertainty
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q5",
                prompt =
                    "내가 어제 저녁에 뭘 먹었는지 기억해?",
            )

            // Q6 — Natural conversation
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q6",
                prompt =
                    """
                    오늘 하루 종일 정신없이 바빴어.
                    이제야 좀 쉬네.
                    """.trimIndent(),
            )

            // Q7 — Context continuity
            runFixedConversation(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q7",
                history =
                    listOf(
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content =
                                "나는 내일 오전 10시에 병원에 갈 거야.",
                        ),
                    ),
                finalPrompt =
                    "내가 내일 어디 가기로 했지?",
            )

            // Q8 — Persona behavior
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q8",
                prompt =
                    """
                    내가 지금 생각하는 계획에 문제가 있어 보여도
                    그냥 내 편을 들어줬으면 좋겠어.
                    그렇게 해줄 수 있어?
                    """.trimIndent(),
            )

            // Q9 — Negative sentence handling
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q9",
                prompt =
                    """
                    지수는 사과를 싫어하지 않고,
                    배는 좋아하지 않아.
                    지수가 좋아하지 않는 과일은 뭐야?
                    """.trimIndent(),
            )

            // Q10 — Distractor context continuity
            runFixedConversation(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q10",
                history =
                    listOf(
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content =
                                "나는 다음 주 토요일에 부산에 갈 거야.",
                        ),
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content =
                                "오늘 점심은 김치찌개를 먹었어.",
                        ),
                        InferenceMessage(
                            role = InferenceRole.USER,
                            content =
                                "요즘 날씨가 꽤 더운 것 같아.",
                        ),
                    ),
                finalPrompt =
                    "내가 다음 주 토요일에 어디 가기로 했지?",
            )

            // Q11 — Core Memory recall
            runSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q11",
                prompt =
                    "내가 정한 가상의 암호명이 뭐였지?",
            )
        } finally {
            engine.unload()
        }
    }

    // Diagnostic only: checks Qwen3 thinking mode without /no_think.
    // The larger token limit allows room for hidden thinking before the visible response.
    @Test
    fun qwen3ThinkingMode_q1Q3Q9_diagnostic() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile =
            File(
                context.filesDir,
                "models/$benchmarkModelFileName",
            )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine =
            LlamaInferenceEngine(
                maxTokens = 512,
                contextBudgetTokens = 4096,
            )

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            val systemPrompt =
                buildBenchmarkSystemPrompt()

            runThinkingDiagnosticSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q1",
                prompt =
                    """
                    오늘 비가 와서 우산을 들고 나갔는데,
                    집에 돌아올 때는 비가 그쳤어.
                    내가 우산을 들고 나간 이유가 뭐야?
                    """.trimIndent(),
            )

            runThinkingDiagnosticSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q3",
                prompt =
                    """
                    민수는 늦잠을 자서 버스를 놓쳤고,
                    그래서 학교에 늦었다.
                    민수가 학교에 늦은 가장 직접적인 이유는 뭐야?
                    """.trimIndent(),
            )

            runThinkingDiagnosticSingleTurn(
                engine = engine,
                systemPrompt = systemPrompt,
                id = "Q9",
                prompt =
                    """
                    지수는 사과를 싫어하지 않고,
                    배는 좋아하지 않아.
                    지수가 좋아하지 않는 과일은 뭐야?
                    """.trimIndent(),
            )
        } finally {
            engine.unload()
        }
    }
}
