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
class ModelMemoryGeneralizationDiagnosticTest {

    private val benchmarkModelFileName =
        "LFM2.5-1.2B-Instruct-Q4_K_M.gguf"

    private val benchmarkDisableThinking = false

    private val importantPrefix = "중요 정보: "

    private val preferenceMemory =
        "사용자가 가장 좋아하는 음료는 말차라떼다."

    private val scheduleMemory =
        "사용자는 다음 주 수요일 오후 3시에 치과 예약이 있다."

    private val projectMemory =
        "사용자가 만든 가상 프로젝트의 이름은 푸른정원이다."

    private val numberMemory =
        "사용자가 정한 가상의 보관함 번호는 4721이다."

    private fun benchmarkPrompt(text: String): String =
        if (benchmarkDisableThinking) {
            "$text /no_think"
        } else {
            text
        }

    private data class DiagnosticResult(
        val response: String,
        val endReason: GenerationEndReason,
    )

    private suspend fun buildBenchmarkSystemPrompt(coreMemory: String): String =
        DefaultSystemPromptProvider(
            personaProvider = DefaultPersonaProvider(),
            coreMemoryProvider = CoreMemoryProvider { coreMemory },
        ).buildPrompt()

    private suspend fun generate(
        engine: LlamaInferenceEngine,
        messages: List<InferenceMessage>,
    ): DiagnosticResult {
        val response = StringBuilder()

        engine.generate(messages).collect { event ->
            when (event) {
                is InferenceEvent.Token -> response.append(event.text)
                InferenceEvent.Completed -> Unit
                InferenceEvent.Cancelled ->
                    error("Memory generalization diagnostic generation was cancelled.")
                is InferenceEvent.Failed -> throw event.cause
            }
        }

        val text = response.toString().trim()

        assertTrue(
            "Model returned an empty response.",
            text.isNotBlank(),
        )

        return DiagnosticResult(
            response = text,
            endReason = engine.lastGenerationEndReason(),
        )
    }

    private suspend fun runCase(
        engine: LlamaInferenceEngine,
        id: String,
        coreMemory: String,
        prompt: String,
    ) {
        val systemPrompt = buildBenchmarkSystemPrompt(coreMemory)
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

        Log.i("MongaMemoryGeneralization", "$id memory: $coreMemory")
        Log.i("MongaMemoryGeneralization", "$id end reason: ${result.endReason}")
        Log.i("MongaMemoryGeneralization", "$id response: ${result.response}")
    }

    @Test
    fun importantPrefix_generalizationDiagnostic() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val modelFile = File(context.filesDir, "models/$benchmarkModelFileName")

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

            // P1/P2 — Preference: plain versus important prefix.
            runCase(
                engine = engine,
                id = "P1",
                coreMemory = preferenceMemory,
                prompt = "내가 가장 좋아하는 음료가 뭐였지?",
            )
            runCase(
                engine = engine,
                id = "P2",
                coreMemory = importantPrefix + preferenceMemory,
                prompt = "내가 가장 좋아하는 음료가 뭐였지?",
            )

            // S1/S2 — Schedule: plain versus important prefix.
            runCase(
                engine = engine,
                id = "S1",
                coreMemory = scheduleMemory,
                prompt = "내 치과 예약이 언제였지?",
            )
            runCase(
                engine = engine,
                id = "S2",
                coreMemory = importantPrefix + scheduleMemory,
                prompt = "내 치과 예약이 언제였지?",
            )

            // J1/J2 — Project fact: plain versus important prefix.
            runCase(
                engine = engine,
                id = "J1",
                coreMemory = projectMemory,
                prompt = "내가 만든 가상 프로젝트 이름이 뭐였지?",
            )
            runCase(
                engine = engine,
                id = "J2",
                coreMemory = importantPrefix + projectMemory,
                prompt = "내가 만든 가상 프로젝트 이름이 뭐였지?",
            )

            // N1/N2 — Arbitrary factual association: plain versus important prefix.
            runCase(
                engine = engine,
                id = "N1",
                coreMemory = numberMemory,
                prompt = "내가 정한 가상의 보관함 번호가 뭐였지?",
            )
            runCase(
                engine = engine,
                id = "N2",
                coreMemory = importantPrefix + numberMemory,
                prompt = "내가 정한 가상의 보관함 번호가 뭐였지?",
            )
        } finally {
            engine.unload()
        }
    }
}
