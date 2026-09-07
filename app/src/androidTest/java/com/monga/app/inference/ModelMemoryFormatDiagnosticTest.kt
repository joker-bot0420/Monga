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
class ModelMemoryFormatDiagnosticTest {

    private val benchmarkModelFileName =
        "LFM2.5-1.2B-Instruct-Q4_K_M.gguf"

    private val benchmarkDisableThinking = false

    private val plainMemory =
        "사용자가 정한 가상의 암호명은 청록등대다."

    private val prefixedMemory =
        "벤치마크 전용 기억: 사용자가 정한 가상의 암호명은 청록등대다."

    private val memoryCueMemory =
        "기억: 사용자가 정한 가상의 암호명은 청록등대다."

    private val benchmarkOnlyMemory =
        "벤치마크 전용: 사용자가 정한 가상의 암호명은 청록등대다."

    private val importantInformationMemory =
        "중요 정보: 사용자가 정한 가상의 암호명은 청록등대다."

    private val userInformationMemory =
        "사용자 정보: 사용자가 정한 가상의 암호명은 청록등대다."

    private val relevantRecallPrompt =
        "내가 정한 가상의 암호명이 뭐였지?"

    private val irrelevantPrompt =
        "오늘 회사에서 일이 많아서 좀 지쳤어. 이제 쉬려고."

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
                    error("Memory format diagnostic generation was cancelled.")
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

        Log.i("MongaMemoryFormat", "$id end reason: ${result.endReason}")
        Log.i("MongaMemoryFormat", "$id response: ${result.response}")
    }

    @Test
    fun plainVsPrefixedMemory_abDiagnostic() = runBlocking {
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

            // A1 — Plain memory / relevant recall
            // Manual observation: whether `청록등대` is recalled directly.
            runCase(
                engine = engine,
                id = "A1",
                coreMemory = plainMemory,
                prompt = relevantRecallPrompt,
            )

            // A2 — Plain memory / irrelevant contamination control
            // Manual observation: natural fatigue/rest response without mentioning
            // `청록등대` or repeating the memory sentence.
            runCase(
                engine = engine,
                id = "A2",
                coreMemory = plainMemory,
                prompt = irrelevantPrompt,
            )

            // B1 — Prefixed memory / relevant recall
            // Manual observation: whether `청록등대` is recalled directly.
            runCase(
                engine = engine,
                id = "B1",
                coreMemory = prefixedMemory,
                prompt = relevantRecallPrompt,
            )

            // B2 — Prefixed memory / irrelevant contamination control
            // Manual observation: natural fatigue/rest response without mentioning
            // `청록등대`, `벤치마크 전용 기억`, or repeating the memory sentence.
            runCase(
                engine = engine,
                id = "B2",
                coreMemory = prefixedMemory,
                prompt = irrelevantPrompt,
            )

            // C1 — Memory cue / relevant recall
            // Manual observation: whether `청록등대` is recalled directly.
            runCase(
                engine = engine,
                id = "C1",
                coreMemory = memoryCueMemory,
                prompt = relevantRecallPrompt,
            )

            // C2 — Memory cue / irrelevant contamination control
            // Manual observation: fatigue/rest response without mentioning
            // `청록등대` or repeating the memory sentence.
            runCase(
                engine = engine,
                id = "C2",
                coreMemory = memoryCueMemory,
                prompt = irrelevantPrompt,
            )

            // D1 — Benchmark-only prefix / relevant recall
            // Manual observation: whether `청록등대` is recalled directly.
            runCase(
                engine = engine,
                id = "D1",
                coreMemory = benchmarkOnlyMemory,
                prompt = relevantRecallPrompt,
            )

            // D2 — Benchmark-only prefix / irrelevant contamination control
            // Manual observation: fatigue/rest response without mentioning
            // `청록등대` or repeating the memory sentence.
            runCase(
                engine = engine,
                id = "D2",
                coreMemory = benchmarkOnlyMemory,
                prompt = irrelevantPrompt,
            )

            // E1 — Important-information prefix / relevant recall
            // Manual observation: whether `청록등대` is recalled directly and
            // whether `중요 정보` is exposed unnecessarily in the response.
            runCase(
                engine = engine,
                id = "E1",
                coreMemory = importantInformationMemory,
                prompt = relevantRecallPrompt,
            )

            // E2 — Important-information prefix / irrelevant contamination control
            // Manual observation: fatigue/rest response without mentioning
            // `청록등대` or repeating the memory/prefix sentence.
            runCase(
                engine = engine,
                id = "E2",
                coreMemory = importantInformationMemory,
                prompt = irrelevantPrompt,
            )

            // F1 — User-information prefix / relevant recall
            // Manual observation: whether `청록등대` is recalled directly and
            // whether `사용자 정보` is exposed unnecessarily in the response.
            runCase(
                engine = engine,
                id = "F1",
                coreMemory = userInformationMemory,
                prompt = relevantRecallPrompt,
            )

            // F2 — User-information prefix / irrelevant contamination control
            // Manual observation: fatigue/rest response without mentioning
            // `청록등대` or repeating the memory/prefix sentence.
            runCase(
                engine = engine,
                id = "F2",
                coreMemory = userInformationMemory,
                prompt = irrelevantPrompt,
            )
        } finally {
            engine.unload()
        }
    }
}
