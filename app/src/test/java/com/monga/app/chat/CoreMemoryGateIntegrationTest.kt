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

class CoreMemoryGateIntegrationTest {

    @Test
    fun unrelatedMessageDoesNotBuildOrInjectCoreMemory() = runBlocking {
        val store = RecordingChatStore()
        val engine = CapturingInferenceEngine()
        var memoryBuildCount = 0

        val coordinator = ChatCoordinator(
            chatStore = store,
            inferenceEngine = engine,
            systemPromptProvider = SystemPromptProvider {
                "너는 몽아라는 AI다."
            },
            coreMemoryProvider = CoreMemoryProvider {
                memoryBuildCount++
                "- 사용자는 녹차를 좋아한다."
            },
            coreMemoryRelevanceGate = DefaultCoreMemoryRelevanceGate,
        )

        val result = coordinator.send(
            conversationId = 1L,
            content = "오늘 기분 어때?",
        )

        assertEquals(ChatResult.Completed, result)
        assertEquals(0, memoryBuildCount)

        val system = engine.receivedMessages.first {
            it.role == InferenceRole.SYSTEM
        }
        assertFalse(system.content.contains("[사용자 기억]"))
        assertFalse(system.content.contains("녹차"))

        val latestUser = engine.receivedMessages.last {
            it.role == InferenceRole.USER
        }
        assertEquals("오늘 기분 어때?", latestUser.content)
    }

    @Test
    fun recallRequestSuppressesPriorAssistantAndAttachesMemoryToLatestUser() =
        runBlocking {
            val store = RecordingChatStore().apply {
                seed(MessageRole.USER, "오늘 기분 어때?")
                seed(MessageRole.ASSISTANT, "오늘 기분이 좋구요. 😊")
            }
            val engine = CapturingInferenceEngine()
            var memoryBuildCount = 0

            val coordinator = ChatCoordinator(
                chatStore = store,
                inferenceEngine = engine,
                systemPromptProvider = SystemPromptProvider {
                    "너는 몽아라는 AI다."
                },
                coreMemoryProvider = CoreMemoryProvider {
                    memoryBuildCount++
                    "- 사용자는 녹차를 좋아한다."
                },
                coreMemoryRelevanceGate = DefaultCoreMemoryRelevanceGate,
            )

            val result = coordinator.send(
                conversationId = 1L,
                content = "내가 좋아하는 음료가 뭐였지?",
            )

            assertEquals(ChatResult.Completed, result)
            assertEquals(1, memoryBuildCount)

            val system = engine.receivedMessages.first {
                it.role == InferenceRole.SYSTEM
            }
            assertFalse(system.content.contains("[사용자 기억]"))
            assertFalse(system.content.contains("녹차"))

            assertFalse(
                engine.receivedMessages.any {
                    it.role == InferenceRole.ASSISTANT &&
                        it.content == "오늘 기분이 좋구요. 😊"
                }
            )

            val userMessages = engine.receivedMessages.filter {
                it.role == InferenceRole.USER
            }
            assertEquals("오늘 기분 어때?", userMessages.first().content)

            val latestUser = userMessages.last().content
            assertTrue(latestUser.contains("[사용자 기억]"))
            assertTrue(latestUser.contains("- 사용자는 녹차를 좋아한다."))
            assertTrue(latestUser.contains("[현재 질문]"))
            assertTrue(latestUser.endsWith("내가 좋아하는 음료가 뭐였지?"))

            val persistedAssistant = store.savedMessages.first {
                it.role == MessageRole.ASSISTANT
            }
            assertEquals("오늘 기분이 좋구요. 😊", persistedAssistant.content)

            val persistedCurrentUser = store.savedMessages.last {
                it.role == MessageRole.USER
            }
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
