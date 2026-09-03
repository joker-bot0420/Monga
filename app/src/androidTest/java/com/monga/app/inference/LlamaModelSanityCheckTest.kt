package com.monga.app.inference

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import android.os.SystemClock
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import android.os.PowerManager

@RunWith(AndroidJUnit4::class)
class LlamaModelSanityCheckTest {

    private val benchmarkModelFileName =
        "Qwen3-1.7B-Q4_K_M.gguf"

    private val benchmarkDisableThinking = true

    private fun benchmarkPrompt(text: String): String =
        if (benchmarkDisableThinking) {
            "$text /no_think"
        } else {
            text
        }

    @Test
    fun userOnly_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine()

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            val response = StringBuilder()

            engine.generate(
                benchmarkPrompt("1+1은?")
            ).collect { event ->
                when (event) {
                    is InferenceEvent.Token ->
                        response.append(event.text)

                    InferenceEvent.Completed -> Unit

                    InferenceEvent.Cancelled ->
                        error("Generation was cancelled.")

                    is InferenceEvent.Failed ->
                        throw event.cause
                }
            }

            Log.i(
                "MongaSanity",
                "USER-only response: $response",
            )

            assertTrue(
                "Model returned an empty response.",
                response.isNotBlank(),
            )
        } finally {
            engine.unload()
        }
    }

    @Test
    fun systemAndUser_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine()

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            val response = StringBuilder()

            engine.generate(
                listOf(
                    InferenceMessage(
                        role = InferenceRole.SYSTEM,
                        content =
                            "모든 답변의 맨 앞에 [SYSTEM_OK]라고 적어라.",
                    ),
                    InferenceMessage(
                        role = InferenceRole.USER,
                        content = benchmarkPrompt("1+1은?"),
                    ),
                )
            ).collect { event ->
                when (event) {
                    is InferenceEvent.Token ->
                        response.append(event.text)

                    InferenceEvent.Completed -> Unit

                    InferenceEvent.Cancelled ->
                        error("Generation was cancelled.")

                    is InferenceEvent.Failed ->
                        throw event.cause
                }
            }

            Log.i(
                "MongaSanity",
                "SYSTEM+USER response: $response",
            )

            assertTrue(
                "Model returned an empty response.",
                response.isNotBlank(),
            )
        } finally {
            engine.unload()
        }
    }

    @Test
    fun multiTurn_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine()

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            val response = StringBuilder()

            engine.generate(
                listOf(
                    InferenceMessage(
                        role = InferenceRole.USER,
                        content = "내가 좋아하는 과일은 사과야.",
                    ),
                    InferenceMessage(
                        role = InferenceRole.ASSISTANT,
                        content = "알겠어. 네가 좋아하는 과일은 사과구나.",
                    ),
                    InferenceMessage(
                        role = InferenceRole.USER,
                        content = benchmarkPrompt(
                            "내가 좋아하는 과일이 뭐라고 했지?"
                        ),
                    ),
                )
            ).collect { event ->
                when (event) {
                    is InferenceEvent.Token ->
                        response.append(event.text)

                    InferenceEvent.Completed -> Unit

                    InferenceEvent.Cancelled ->
                        error("Generation was cancelled.")

                    is InferenceEvent.Failed ->
                        throw event.cause
                }
            }

            Log.i(
                "MongaSanity",
                "MULTI-TURN end reason: ${engine.lastGenerationEndReason()}",
            )

            Log.i(
                "MongaSanity",
                "MULTI-TURN response: $response",
            )

            assertTrue(
                "Model returned an empty response.",
                response.isNotBlank(),
            )
        } finally {
            engine.unload()
        }
    }
    @Test
    fun maxTokensEndReason_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine(maxTokens = 1)

        try {
            engine.loadModel(modelFile.absolutePath)

            engine.generate("1+1은 무엇이고, 그 이유도 설명해줘.").collect { event ->
                when (event) {
                    is InferenceEvent.Token -> Unit
                    InferenceEvent.Completed -> Unit
                    InferenceEvent.Cancelled ->
                        error("Generation was cancelled.")

                    is InferenceEvent.Failed ->
                        throw event.cause
                }
            }

            Log.i(
                "MongaSanity",
                "MAX-TOKENS end reason: ${engine.lastGenerationEndReason()}",
            )

            assertEquals(
                GenerationEndReason.MAX_TOKENS,
                engine.lastGenerationEndReason(),
            )
        } finally {
            engine.unload()
        }
    }

    @Test
    fun performanceTiming_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine(maxTokens = 192)

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            var firstTokenAtNs: Long? = null
            val startedAtNs = SystemClock.elapsedRealtimeNanos()

            engine.generate(
                benchmarkPrompt(
                    "오늘 하루 종일 정신없이 바빴어. 이제야 좀 쉬네."
                )
            ).collect { event ->
                when (event) {
                    is InferenceEvent.Token -> {
                        if (firstTokenAtNs == null) {
                            firstTokenAtNs =
                                SystemClock.elapsedRealtimeNanos()
                        }
                    }

                    InferenceEvent.Completed -> Unit

                    InferenceEvent.Cancelled ->
                        error("Generation was cancelled.")

                    is InferenceEvent.Failed ->
                        throw event.cause
                }
            }

            val finishedAtNs = SystemClock.elapsedRealtimeNanos()

            val firstTokenNs =
                firstTokenAtNs
                    ?: error("No visible token was emitted.")

            val ttftMs =
                (firstTokenNs - startedAtNs) / 1_000_000.0

            val totalMs =
                (finishedAtNs - startedAtNs) / 1_000_000.0

            val promptPrefillUs =
                engine.lastPromptPrefillUs()

            val nativeDecodeUs =
                engine.lastDecodeUs()

            val decodedTokenCount =
                engine.lastDecodedTokenCount()

            val promptPrefillMs =
                promptPrefillUs / 1_000.0

            val nativeDecodeTokensPerSecond =
                if (decodedTokenCount > 0 && nativeDecodeUs > 0L) {
                    decodedTokenCount * 1_000_000.0 / nativeDecodeUs
                } else {
                    0.0
                }

            val generatedTokenCount =
                engine.lastGeneratedTokenCount()

            val decodeTokenCount =
                (generatedTokenCount - 1).coerceAtLeast(0)

            val decodeWindowSeconds =
                (finishedAtNs - firstTokenNs) / 1_000_000_000.0

            val decodeTokensPerSecond =
                if (decodeTokenCount > 0 && decodeWindowSeconds > 0.0) {
                    decodeTokenCount / decodeWindowSeconds
                } else {
                    0.0
                }

            Log.i(
                "MongaSanity",
                "PERF TTFT ms: $ttftMs",
            )

            Log.i(
                "MongaSanity",
                "PERF prompt prefill ms: $promptPrefillMs",
            )

            Log.i(
                "MongaSanity",
                "PERF native decoded tokens: $decodedTokenCount",
            )

            Log.i(
                "MongaSanity",
                "PERF native decode us: $nativeDecodeUs",
            )

            Log.i(
                "MongaSanity",
                "PERF native decode tokens/sec: $nativeDecodeTokensPerSecond",
            )

            Log.i(
                "MongaSanity",
                "PERF total generation ms: $totalMs",
            )

            Log.i(
                "MongaSanity",
                "PERF end reason: ${engine.lastGenerationEndReason()}",
            )

            Log.i(
                "MongaSanity",
                "PERF generated tokens: $generatedTokenCount",
            )

            Log.i(
                "MongaSanity",
                "PERF decode tokens/sec: $decodeTokensPerSecond",
            )

            assertTrue(
                "TTFT must be positive.",
                ttftMs > 0.0,
            )
        } finally {
            engine.unload()
        }
    }

    @Test
    fun memoryRss_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine(maxTokens = 192)

        val rssBeforeLoadKb =
            engine.currentRssKb()

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            val rssAfterLoadKb =
                engine.currentRssKb()

            var peakRssKb = rssAfterLoadKb

            val samplingJob = launch {
                while (true) {
                    val currentRssKb =
                        engine.currentRssKb()

                    if (currentRssKb > peakRssKb) {
                        peakRssKb = currentRssKb
                    }

                    delay(10)
                }
            }

            try {
                engine.generate(
                    benchmarkPrompt(
                        "오늘 하루 종일 정신없이 바빴어. 이제야 좀 쉬네."
                    )
                ).collect { event ->
                    when (event) {
                        is InferenceEvent.Token -> Unit

                        InferenceEvent.Completed -> Unit

                        InferenceEvent.Cancelled ->
                            error("Generation was cancelled.")

                        is InferenceEvent.Failed ->
                            throw event.cause
                    }
                }
            } finally {
                samplingJob.cancel()
                samplingJob.join()
            }

            val rssAfterGenerationKb =
                engine.currentRssKb()

            Log.i(
                "MongaSanity",
                "MEM RSS before load KB: $rssBeforeLoadKb",
            )

            Log.i(
                "MongaSanity",
                "MEM RSS after load KB: $rssAfterLoadKb",
            )

            Log.i(
                "MongaSanity",
                "MEM RSS peak KB: $peakRssKb",
            )

            Log.i(
                "MongaSanity",
                "MEM RSS after generation KB: $rssAfterGenerationKb",
            )

            assertTrue(
                "RSS before model load must be positive.",
                rssBeforeLoadKb > 0,
            )

            assertTrue(
                "Peak RSS must be positive.",
                peakRssKb > 0,
            )
        } finally {
            engine.unload()
        }
    }

    @Test
    fun repeatedPerformance_sanityCheck() = runBlocking {
        val context =
            InstrumentationRegistry.getInstrumentation().targetContext

        val powerManager =
            context.getSystemService(PowerManager::class.java)

        val modelFile = File(
            context.filesDir,
            "models/$benchmarkModelFileName",
        )

        assertTrue(
            "Model file not found: ${modelFile.absolutePath}",
            modelFile.isFile,
        )

        val engine = LlamaInferenceEngine(maxTokens = 192)

        val prompt =
            benchmarkPrompt(
                "오늘 하루 종일 정신없이 바빴어. 이제야 좀 쉬네."
            )

        try {
            engine.loadModel(modelFile.absolutePath)

            assertEquals(
                InferenceState.Ready,
                engine.state.value,
            )

            // Warm-up: 결과는 평균에 포함하지 않는다.
            engine.generate(prompt).collect { event ->
                when (event) {
                    is InferenceEvent.Token -> Unit
                    InferenceEvent.Completed -> Unit

                    InferenceEvent.Cancelled ->
                        error("Warm-up generation was cancelled.")

                    is InferenceEvent.Failed ->
                        throw event.cause
                }
            }

            Log.i(
                "MongaSanity",
                "REPEAT warm-up completed",
            )

            val ttftResults = mutableListOf<Double>()
            val prefillResults = mutableListOf<Double>()
            val decodeResults = mutableListOf<Double>()
            val totalResults = mutableListOf<Double>()

            repeat(3) { index ->
                val runNumber = index + 1

                val thermalBefore =
                    powerManager.currentThermalStatus

                val startedAtNs =
                    SystemClock.elapsedRealtimeNanos()

                var firstTokenAtNs: Long? = null

                engine.generate(prompt).collect { event ->
                    when (event) {
                        is InferenceEvent.Token -> {
                            if (firstTokenAtNs == null) {
                                firstTokenAtNs =
                                    SystemClock.elapsedRealtimeNanos()
                            }
                        }

                        InferenceEvent.Completed -> Unit

                        InferenceEvent.Cancelled ->
                            error("Run $runNumber was cancelled.")

                        is InferenceEvent.Failed ->
                            throw event.cause
                    }
                }

                val finishedAtNs =
                    SystemClock.elapsedRealtimeNanos()

                val firstTokenNs =
                    checkNotNull(firstTokenAtNs) {
                        "Run $runNumber produced no visible token."
                    }

                val ttftMs =
                    (firstTokenNs - startedAtNs) / 1_000_000.0

                val totalMs =
                    (finishedAtNs - startedAtNs) / 1_000_000.0

                val prefillMs =
                    engine.lastPromptPrefillUs() / 1_000.0

                val decodeUs =
                    engine.lastDecodeUs()

                val decodedTokens =
                    engine.lastDecodedTokenCount()

                val decodeTokensPerSecond =
                    if (decodedTokens > 0 && decodeUs > 0L) {
                        decodedTokens * 1_000_000.0 / decodeUs
                    } else {
                        0.0
                    }

                ttftResults += ttftMs
                prefillResults += prefillMs
                decodeResults += decodeTokensPerSecond
                totalResults += totalMs

                val thermalAfter =
                    powerManager.currentThermalStatus

                Log.i(
                    "MongaSanity",
                    "REPEAT run $runNumber TTFT ms: $ttftMs",
                )

                Log.i(
                    "MongaSanity",
                    "REPEAT run $runNumber prefill ms: $prefillMs",
                )

                Log.i(
                    "MongaSanity",
                    "REPEAT run $runNumber decode tok/s: $decodeTokensPerSecond",
                )

                Log.i(
                    "MongaSanity",
                    "REPEAT run $runNumber total ms: $totalMs",
                )

                Log.i(
                    "MongaSanity",
                    "REPEAT run $runNumber thermal: " +
                            "${thermalStatusName(thermalBefore)} -> " +
                            thermalStatusName(thermalAfter),
                )

                Log.i(
                    "MongaSanity",
                    "REPEAT run $runNumber end reason: " +
                            engine.lastGenerationEndReason(),
                )

            }

            Log.i(
                "MongaSanity",
                "REPEAT average TTFT ms: ${ttftResults.average()}",
            )

            Log.i(
                "MongaSanity",
                "REPEAT average prefill ms: ${prefillResults.average()}",
            )

            Log.i(
                "MongaSanity",
                "REPEAT average decode tok/s: ${decodeResults.average()}",
            )

            Log.i(
                "MongaSanity",
                "REPEAT average total ms: ${totalResults.average()}",
            )

            Unit
        } finally {
            engine.unload()
        }
    }

    private fun thermalStatusName(status: Int): String =
        when (status) {
            PowerManager.THERMAL_STATUS_NONE -> "NONE"
            PowerManager.THERMAL_STATUS_LIGHT -> "LIGHT"
            PowerManager.THERMAL_STATUS_MODERATE -> "MODERATE"
            PowerManager.THERMAL_STATUS_SEVERE -> "SEVERE"
            PowerManager.THERMAL_STATUS_CRITICAL -> "CRITICAL"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "EMERGENCY"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "SHUTDOWN"
            else -> "UNKNOWN($status)"
        }

}

