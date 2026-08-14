package com.monga.app.inference

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.Assert.assertTrue

class FakeInferenceEngineTest {
    @Test
    fun generateStreamsTokensAndCompletes() = runBlocking {
        val engine = FakeInferenceEngine()

        assertEquals(InferenceState.NoModel, engine.state.value)

        engine.loadModel("fake.gguf")
        assertEquals(InferenceState.Ready, engine.state.value)

        val events = engine.generate("안녕").toList()

        val text = events
            .filterIsInstance<InferenceEvent.Token>()
            .joinToString("") { it.text }

        assertEquals(
            "안녕! 지금은 테스트 엔진으로 대화하고 있어.",
            text,
        )
        assertEquals(InferenceEvent.Completed, events.last())
        assertEquals(InferenceState.Ready, engine.state.value)
    }

    @Test
    fun cancelEmitsCancelledAndReturnsToReady() = runBlocking {
        val engine = FakeInferenceEngine()
        engine.loadModel("fake.gguf")

        val events = mutableListOf<InferenceEvent>()

        engine.generate("안녕").collect { event ->
            events += event

            if (event is InferenceEvent.Token) {
                engine.cancel()
            }
        }

        assertEquals(InferenceEvent.Cancelled, events.last())
        assertEquals(InferenceState.Ready, engine.state.value)
    }

    @Test
    fun generateWithoutModelFails() = runBlocking {
        val engine = FakeInferenceEngine()

        val events = engine.generate("안녕").toList()

        assertEquals(1, events.size)
        assertTrue(events.single() is InferenceEvent.Failed)
        assertEquals(InferenceState.NoModel, engine.state.value)
    }

    @Test
    fun unloadDuringGenerationKeepsNoModelState() = runBlocking {
        val engine = FakeInferenceEngine()
        engine.loadModel("fake.gguf")

        val events = mutableListOf<InferenceEvent>()

        engine.generate("안녕").collect { event ->
            events += event

            if (event is InferenceEvent.Token) {
                engine.unload()
            }
        }

        assertEquals(InferenceEvent.Cancelled, events.last())
        assertEquals(InferenceState.NoModel, engine.state.value)
    }

    @Test
    fun cancelAfterLastTokenEmitsCancelled() = runBlocking {
        val engine = FakeInferenceEngine()
        engine.loadModel("fake.gguf")

        val response = "안녕! 지금은 테스트 엔진으로 대화하고 있어."
        val expectedChunkCount = response.chunked(3).size

        val events = mutableListOf<InferenceEvent>()
        var tokenCount = 0

        engine.generate("안녕").collect { event ->
            events += event

            if (event is InferenceEvent.Token) {
                tokenCount++

                if (tokenCount == expectedChunkCount) {
                    engine.cancel()
                }
            }
        }

        assertEquals(InferenceEvent.Cancelled, events.last())
        assertEquals(InferenceState.Ready, engine.state.value)
    }
}
