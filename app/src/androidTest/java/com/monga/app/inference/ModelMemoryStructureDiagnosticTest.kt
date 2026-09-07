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
class ModelMemoryStructureDiagnosticTest {

    private val benchmarkModelFileName =
        "LFM2.5-1.2B-Instruct-Q4_K_M.gguf"

    private val benchmarkDisableThinking = false

    private data class MemoryPair(
        val natural: String,
        val structured: String,
        val prompt: String,
    )

    private val codenameMemory =
        MemoryPair(
            natural = "사용자가 정한 가상의 암호명은 청록등대다.",
            structured = "주체: 사용자\n항목: 가상 암호명\n값: 청록등대",
            prompt = "내가 정한 가상의 암호명이 뭐였지?",
        )

    private val preferenceMemory =
        MemoryPair(
            natural = "사용자가 가장 좋아하는 음료는 말차라떼다.",
            structured = "주체: 사용자\n항목: 가장 좋아하는 음료\n값: 말차라떼",
            prompt = "내가 가장 좋아하는 음료가 뭐였지?",
        )

    private val scheduleMemory =
        MemoryPair(
            natural = "사용자는 다음 주 수요일 오후 3시에 치과 예약이 있다.",
            structured = "주체: 사용자\n항목: 치과 예약\n값: 다음 주 수요일 오후 3시",
            prompt = "내 치과 예약이 언제였지?",
        )

    private val projectMemory =
        MemoryPair(
            natural = "사용자가 만든 가상 프로젝트의 이름은 푸른정원이다.",
            structured = "주체: 사용자\n항목: 가상 프로젝트 이름\n값: 푸른정원",
            prompt = "내가 만든 가상 프로젝트 이름이 뭐였지?",
        )

    private val numberMemory =
        MemoryPair(
            natural = "사용자가 정한 가상의 보관함 번호는 4721이다.",
            structured = "주체: 사용자\n항목: 가상 보관함 번호\n값: 4721",
            prompt = "내가 정한 가상의 보관함 번호가 뭐였지?",
        )

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
                    error("Memory structure diagnostic generation was cancelled.")
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
        format: String,
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

        Log.i("MongaMemoryStructure", "$id format: $format")
        Log.i("MongaMemoryStructure", "$id memory: $coreMemory")
        Log.i("MongaMemoryStructure", "$id end reason: ${result.endReason}")
        Log.i("MongaMemoryStructure", "$id response: ${result.response}")
    }

    private suspend fun runPair(
        engine: LlamaInferenceEngine,
        idPrefix: String,
        memory: MemoryPair,
    ) {
        runCase(
            engine = engine,
            id = "$idPrefix-N",
            format = "Natural",
            coreMemory = memory.natural,
            prompt = memory.prompt,
        )
        runCase(
            engine = engine,
            id = "$idPrefix-K",
            format = "Structured",
            coreMemory = memory.structured,
            prompt = memory.prompt,
        )
    }

    @Test
    fun naturalVsStructuredMemory_diagnostic() = runBlocking {
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

            runPair(engine, "C", codenameMemory)
            runPair(engine, "P", preferenceMemory)
            runPair(engine, "S", scheduleMemory)
            runPair(engine, "J", projectMemory)
            runPair(engine, "N", numberMemory)
        } finally {
            engine.unload()
        }
    }
}
