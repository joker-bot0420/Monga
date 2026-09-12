package com.monga.app.chat

import com.monga.app.data.ChatStore
import com.monga.app.data.local.Message
import com.monga.app.data.local.MessageRole
import com.monga.app.inference.InferenceEngine
import com.monga.app.inference.InferenceEvent
import com.monga.app.inference.InferenceMessage
import com.monga.app.inference.InferenceRole
import com.monga.app.inference.InferenceState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreMemoryUserContextTest {

    @Test
    fun injectsCoreMemoryOnlyIntoLatestUserInferenceCopy() = runBlocking {
        val store = RecordingChatStore().apply {
            seed(
                role = MessageRole.USER,
                content = "예전 질문",
            )
            seed(
                role = MessageRole.ASSISTANT,
                content = "예전 답변",
            )
        }
        val engine = CapturingInferenceEngine()
        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = SystemPromptProvider {
                "너는 몽아라는 AI다."
            },
            coreMemoryProvider = CoreMemoryProvider {
                "- 나는 녹차를 좋아한다."
            },
        )

        val result = coordinator.send(
            conversationId = 1L,
            content = "내가 좋아하는 음료가 뭐였지?",
        )

        assertEquals(ChatResult.Completed, result)

        val generated = engine.receivedMessages
        val systemMessage = generated.first {
            it.role == InferenceRole.SYSTEM
        }
        assertFalse(systemMessage.content.contains("나는 녹차를 좋아한다."))

        val userMessages = generated.filter {
            it.role == InferenceRole.USER
        }
        assertEquals("예전 질문", userMessages.first().content)

        val latestUserMessage = userMessages.last().content
        assertTrue(latestUserMessage.contains("[사용자 기억]"))
        assertTrue(latestUserMessage.contains("- 나는 녹차를 좋아한다."))
        assertTrue(latestUserMessage.contains("[현재 사용자 메시지]"))
        assertTrue(
            latestUserMessage.endsWith("내가 좋아하는 음료가 뭐였지?")
        )

        val persistedCurrentUser = store.savedMessages
            .last { it.role == MessageRole.USER }
        assertEquals(
            "내가 좋아하는 음료가 뭐였지?",
            persistedCurrentUser.content,
        )
        assertFalse(persistedCurrentUser.content.contains("[사용자 기억]"))
    }

    private class RecordingChatStore : ChatStore {
        val savedMessages = mutableListOf<Message>()

        fun seed(
            role: MessageRole,
            content: String,
        ) {
            savedMessages += Message(
                id = savedMessages.size.toLong() + 1,
                conversationId = 1L,
                role = role,
                content = content,
                createdAt = savedMessages.size.toLong(),
            )
        }

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
        ): List<Message> =
            savedMessages.filter {
                it.conversationId == conversationId
            }
    }

    private class CapturingInferenceEngine : InferenceEngine {
        private val _state = MutableStateFlow<InferenceState>(
            InferenceState.Ready
        )
        override val state: StateFlow<InferenceState> = _state

        var receivedMessages: List<InferenceMessage> = emptyList()
            private set

        override suspend fun loadModel(path: String) = Unit

        override fun generate(
            messages: List<InferenceMessage>,
        ): Flow<InferenceEvent> {
            receivedMessages = messages
            return flowOf(
                InferenceEvent.Token("응답"),
                InferenceEvent.Completed,
            )
        }

        override fun cancel() = Unit

        override suspend fun unload() = Unit
    }
}
