package com.monga.app.chat

import com.monga.app.data.ChatStore
import com.monga.app.data.local.Message
import com.monga.app.data.local.MessageRole
import com.monga.app.inference.InferenceEngine
import com.monga.app.inference.InferenceEvent
import com.monga.app.inference.InferenceState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatCoordinatorTest {

    @Test
    fun completedGenerationSavesUserAndAssistantMessages() = runBlocking {
        val store = FakeChatStore()
        val engine = StubInferenceEngine(
            InferenceEvent.Token("안녕"),
            InferenceEvent.Token(" 몽아야"),
            InferenceEvent.Completed,
        )
        val coordinator = ChatCoordinator(store, engine)

        val result = coordinator.send(
            conversationId = 1L,
            content = "테스트",
        )

        assertEquals(ChatResult.Completed, result)
        assertEquals(2, store.savedMessages.size)

        assertEquals(MessageRole.USER, store.savedMessages[0].role)
        assertEquals("테스트", store.savedMessages[0].content)

        assertEquals(MessageRole.ASSISTANT, store.savedMessages[1].role)
        assertEquals("안녕 몽아야", store.savedMessages[1].content)
    }

    @Test
    fun cancelledGenerationDoesNotSavePartialAssistantMessage() = runBlocking {
        val store = FakeChatStore()
        val engine = StubInferenceEngine(
            InferenceEvent.Token("완성되지 않은"),
            InferenceEvent.Cancelled,
        )
        val coordinator = ChatCoordinator(store, engine)

        val result = coordinator.send(
            conversationId = 1L,
            content = "테스트",
        )

        assertEquals(ChatResult.Cancelled, result)
        assertEquals(1, store.savedMessages.size)
        assertEquals(MessageRole.USER, store.savedMessages.single().role)
    }

    @Test
    fun failedGenerationDoesNotSaveAssistantMessage() = runBlocking {
        val store = FakeChatStore()
        val failure = IllegalStateException("test failure")
        val engine = StubInferenceEngine(
            InferenceEvent.Failed(failure),
        )
        val coordinator = ChatCoordinator(store, engine)

        val result = coordinator.send(
            conversationId = 1L,
            content = "테스트",
        )

        assertTrue(result is ChatResult.Failed)
        assertEquals(failure, (result as ChatResult.Failed).cause)

        assertEquals(1, store.savedMessages.size)
        assertEquals(MessageRole.USER, store.savedMessages.single().role)
    }

    private class FakeChatStore : ChatStore {
        val savedMessages = mutableListOf<Message>()

        override suspend fun saveMessage(
            conversationId: Long,
            role: MessageRole,
            content: String,
        ) {
            savedMessages += Message(
                id = savedMessages.size.toLong() + 1,
                conversationId = conversationId,
                role = role,
                content = content,
                createdAt = savedMessages.size.toLong(),
            )
        }

        override suspend fun recentMessages(
            conversationId: Long,
        ): List<Message> = emptyList()
    }

    private class StubInferenceEngine(
        vararg events: InferenceEvent,
    ) : InferenceEngine {
        private val generatedEvents = events.toList()

        private val _state = MutableStateFlow<InferenceState>(
            InferenceState.Ready
        )

        override val state: StateFlow<InferenceState> = _state

        override suspend fun loadModel(path: String) {
            _state.value = InferenceState.Ready
        }

        override fun generate(prompt: String): Flow<InferenceEvent> =
            flowOf(*generatedEvents.toTypedArray())

        override fun cancel() = Unit

        override suspend fun unload() {
            _state.value = InferenceState.NoModel
        }
    }
}