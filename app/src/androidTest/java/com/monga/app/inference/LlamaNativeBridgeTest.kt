package com.monga.app.inference

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import androidx.test.platform.app.InstrumentationRegistry
import com.monga.app.chat.DefaultCoreMemoryProvider
import com.monga.app.chat.DefaultSystemPromptProvider
import com.monga.app.chat.PersonaProvider
import com.monga.app.data.local.CoreMemory
import java.io.File
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking

@RunWith(AndroidJUnit4::class)
class LlamaNativeBridgeTest {

    @Test
    fun nativePing_returnsExpectedMessage() {
        assertEquals(
            "monga-native-ok",
            LlamaNativeBridge.nativePing(),
        )
    }

    @Test
    fun nativeLlamaTimeUs_returnsPositiveValue() {
        assertTrue(
            LlamaNativeBridge.nativeLlamaTimeUs() > 0L,
        )
    }

    @Test
    fun lfm2_5_1_2b_coreMemoryCompatibility() = runBlocking {
        verifyCoreMemoryCompatibility(
            "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
        )
    }

    @Test
    fun qwen3_1_7b_coreMemoryCompatibility() = runBlocking {
        verifyCoreMemoryCompatibility(
            "Qwen3-1.7B-Q4_K_M.gguf",
        )
    }

    @Test
    fun qwen3_0_6b_coreMemoryCompatibility() = runBlocking {
        verifyCoreMemoryCompatibility(
            "Qwen_Qwen3-0.6B-Q4_K_M.gguf",
        )
    }

    @Test
    fun gemma3_1b_coreMemoryCompatibility() = runBlocking {
        verifyCoreMemoryCompatibility(
            "gemma-3-1b-it-Q4_K_M.gguf",
        )
    }

    @Test
    fun qwen2_5_0_5b_coreMemoryCompatibility() = runBlocking {
        verifyCoreMemoryCompatibility(
            "qwen2.5-0.5b-instruct-q4_k_m.gguf",
        )
    }

    private suspend fun verifyCoreMemoryCompatibility(
        modelFileName: String,
    ) {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$modelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine(maxTokens = 16)

        try {
            engine.loadModel(modelFile.absolutePath)
            assertEquals(InferenceState.Ready, engine.state.value)

            val countMemoryTokens: (String) -> Int = { text ->
                LlamaNativeBridge.nativeCountChatTokens(
                    roles = arrayOf(InferenceRole.SYSTEM.wireValue),
                    contents = arrayOf(text),
                )
            }

            val coreMemoryProvider = DefaultCoreMemoryProvider(
                coreMemories = flowOf(
                    listOf(
                        CoreMemory(
                            id = 1L,
                            content = "사용자가 좋아하는 음료는 녹차다.",
                            createdAt = 100L,
                            updatedAt = 100L,
                        ),
                        CoreMemory(
                            id = 2L,
                            content = "사용자는 조용한 환경에서 공부하는 것을 선호한다.",
                            createdAt = 200L,
                            updatedAt = 200L,
                        ),
                    )
                ),
                tokenCounter = countMemoryTokens,
            )

            val memory = coreMemoryProvider.buildMemory()
            val memoryTokens = countMemoryTokens(memory)

            assertTrue("Core Memory must not be empty.", memory.isNotBlank())
            assertTrue("Invalid memory token count.", memoryTokens > 0)
            assertTrue(
                "Core Memory exceeded its token budget: $memoryTokens",
                memoryTokens <= 1024,
            )

            val systemPrompt = DefaultSystemPromptProvider(
                personaProvider = PersonaProvider {
                    "- 친근하고 간결하게 대화한다."
                },
                coreMemoryProvider = coreMemoryProvider,
            ).buildPrompt()

            assertTrue(systemPrompt.contains("[사용자 기억]"))
            assertTrue(systemPrompt.contains(memory))

            val messages = listOf(
                InferenceMessage(InferenceRole.SYSTEM, systemPrompt),
                InferenceMessage(
                    InferenceRole.USER,
                    "내가 좋아하는 음료는 뭐야?",
                ),
            )

            val promptTokens = LlamaNativeBridge.nativeCountChatTokens(
                roles = messages.map { it.role.wireValue }.toTypedArray(),
                contents = messages.map { it.content }.toTypedArray(),
            )

            val effectiveBudget = minOf(
                LlamaNativeBridge.nativeModelContextSize(),
                4096,
            )

            assertTrue("Invalid prompt token count.", promptTokens > 0)
            assertTrue("Invalid model context size.", effectiveBudget > 0)
            assertTrue(
                "Final prompt exceeds the context budget.",
                promptTokens.toLong() + 16L <= effectiveBudget.toLong(),
            )

            var completed = false

            engine.generate(messages).collect { event ->
                when (event) {
                    is InferenceEvent.Token -> Unit
                    InferenceEvent.Completed -> completed = true
                    InferenceEvent.Cancelled ->
                        error("Generation was cancelled.")
                    is InferenceEvent.Failed -> throw event.cause
                }
            }

            assertTrue("Generation did not complete.", completed)
        } finally {
            engine.unload()
        }
    }

}
