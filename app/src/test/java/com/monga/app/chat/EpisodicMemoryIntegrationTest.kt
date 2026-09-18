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

class EpisodicMemoryIntegrationTest {

    @Test
    fun selectedEpisodeKeepsRecentConversationAndOnlyChangesInferenceCopy() =
        runBlocking {
            val store = RecordingChatStore().apply {
                seed(MessageRole.USER, "아까 회사 얘기했었지?")
                seed(MessageRole.ASSISTANT, "응, 회사 얘기를 했어.")
            }
            val engine = CapturingInferenceEngine()
            var receivedQuery = ""

            val coordinator = ChatCoordinator(
                chatStore = store,
                inferenceEngine = engine,
                systemPromptProvider = SystemPromptProvider {
                    "너는 몽아라는 AI다."
                },
                episodicMemoryProvider = EpisodicMemoryProvider { query ->
                    receivedQuery = query
                    "- 2026-09-10 | 회사 어종 동정: 전갱이와 가자미류를 봤다."
                },
            )

            val result = coordinator.send(
                conversationId = 1L,
                content = "지난번 회사에서 어떤 어종 봤었지?",
            )

            assertEquals(ChatResult.Completed, result)
            assertEquals("지난번 회사에서 어떤 어종 봤었지?", receivedQuery)

            assertTrue(
                engine.receivedMessages.any {
                    it.role == InferenceRole.USER &&
                        it.content == "아까 회사 얘기했었지?"
                }
            )
            assertTrue(
                engine.receivedMessages.any {
                    it.role == InferenceRole.ASSISTANT &&
                        it.content == "응, 회사 얘기를 했어."
                }
            )

            val system = engine.receivedMessages.first {
                it.role == InferenceRole.SYSTEM
            }.content
            assertTrue(system.contains("[현재 질문의 사실 근거]"))
            assertTrue(system.contains("전갱이와 가자미류"))
            assertTrue(system.contains("응/아니는 질문 전체의 참·거짓을 기록으로 확실히 판단할 수 있을 때만 사용하라."))
            assertTrue(system.contains("긍정 질문이 기록으로 확인되면 응이라고 답하고 사실을 말하라."))
            assertTrue(system.contains("부정 질문이 기록과 충돌하면 아니라고 답하고 기록된 사실을 말하라."))
            assertTrue(system.contains("기록에 적힌 사건이 있으면 그 사건이 없었다고 말하지 마라."))

            val latestUser = engine.receivedMessages.last {
                it.role == InferenceRole.USER
            }.content
            assertEquals("지난번 회사에서 어떤 어종 봤었지?", latestUser)
            assertFalse(latestUser.contains("[과거 사건 기억]"))
            assertFalse(latestUser.contains("[현재 질문]"))
            assertFalse(latestUser.contains("[사용자 기억]"))

            val persistedCurrentUser = store.savedMessages.last {
                it.role == MessageRole.USER
            }
            assertEquals(
                "지난번 회사에서 어떤 어종 봤었지?",
                persistedCurrentUser.content,
            )
            assertFalse(persistedCurrentUser.content.contains("[과거 사건 기억]"))
            assertFalse(persistedCurrentUser.content.contains("[현재 질문의 사실 근거]"))
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
        ): List<Message> = savedMessages.filter {
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
            return flowOf(InferenceEvent.Completed)
        }

        override fun cancel() = Unit
        override suspend fun unload() = Unit
    }
}
