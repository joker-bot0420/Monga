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
import com.monga.app.inference.InferenceMessage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withTimeout

class ChatCoordinatorTest {

    private val systemPromptProvider = SystemPromptProvider { "" }

    @Test
    fun completedGenerationSavesUserAndAssistantMessages() = runBlocking {
        val store = FakeChatStore()
        val engine = StubInferenceEngine(
            InferenceEvent.Token("안녕"),
            InferenceEvent.Token(" 몽아야"),
            InferenceEvent.Completed,
        )
        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = systemPromptProvider,
        )

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
        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = systemPromptProvider,
        )

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
        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = systemPromptProvider,
        )

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

    @Test
    fun nonReadyEngineSkipsSystemPromptBuild() = runBlocking {
        val store = FakeChatStore()
        val engine = StubInferenceEngine()
        engine.setState(InferenceState.Loading)

        var promptBuildCount = 0

        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = SystemPromptProvider {
                promptBuildCount += 1
                ""
            },
        )

        val result = coordinator.send(
            conversationId = 1L,
            content = "테스트",
        )

        assertTrue(result is ChatResult.Failed)
        assertEquals(0, promptBuildCount)

        // 모델이 준비되지 않으면 사용자 메시지를 저장하지 않는다.
        assertEquals(0, store.savedMessages.size)
    }

    @Test
    fun concurrentSendIsIgnoredAndNextSendWorksAfterCompletion() = runBlocking {
        val store = FakeChatStore()
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var generationCount = 0

        val engine = object : InferenceEngine {
            private val _state = MutableStateFlow<InferenceState>(
                InferenceState.Ready
            )
            override val state: StateFlow<InferenceState> = _state

            override suspend fun loadModel(path: String) = Unit

            override fun generate(
                messages: List<InferenceMessage>,
            ): Flow<InferenceEvent> = flow {
                generationCount++
                started.complete(Unit)
                release.await()
                emit(InferenceEvent.Token("reply"))
                emit(InferenceEvent.Completed)
            }

            override fun cancel() = Unit
            override suspend fun unload() = Unit
        }

        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = systemPromptProvider,
        )

        withTimeout(5_000) {
            val first = async {
                coordinator.send(1L, "first")
            }

            // 첫 번째 생성이 실제로 시작할 때까지 기다린다.
            started.await()

            // 첫 번째 생성이 멈춰 있는 동안 두 번째 요청을 보낸다.
            val second = coordinator.send(1L, "second")

            assertEquals(ChatResult.Ignored, second)
            assertEquals(1, generationCount)
            assertEquals(1, store.savedMessages.size)

            // 첫 번째 생성을 완료시킨다.
            release.complete(Unit)
            assertEquals(ChatResult.Completed, first.await())

            // 잠금이 해제됐으므로 다음 요청은 정상 실행된다.
            val third = coordinator.send(1L, "third")

            assertEquals(ChatResult.Completed, third)
            assertEquals(2, generationCount)
        }
    }

    private class StubInferenceEngine(
        vararg events: InferenceEvent,
    ) : InferenceEngine {
        private val generatedEvents = events.toList()

        private val _state = MutableStateFlow<InferenceState>(
            InferenceState.Ready
        )

        override val state: StateFlow<InferenceState> = _state

        fun setState(state: InferenceState) {
            _state.value = state
        }

        override suspend fun loadModel(path: String) {
            _state.value = InferenceState.Ready
        }

        override fun generate(
            messages: List<InferenceMessage>,
        ): Flow<InferenceEvent> =
            flowOf(*generatedEvents.toTypedArray())

        override fun cancel() = Unit

        override suspend fun unload() {
            _state.value = InferenceState.NoModel
        }
    }
}