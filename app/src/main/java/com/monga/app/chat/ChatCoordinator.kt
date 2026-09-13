package com.monga.app.chat

import com.monga.app.data.ChatStore
import com.monga.app.data.local.MessageRole
import com.monga.app.inference.InferenceEngine
import com.monga.app.inference.InferenceEvent
import kotlinx.coroutines.CancellationException
import com.monga.app.inference.InferenceMessage
import com.monga.app.inference.InferenceRole
import com.monga.app.inference.InferenceState
import kotlinx.coroutines.sync.Mutex

sealed interface ChatResult {
    data object Completed : ChatResult
    data object Cancelled : ChatResult
    data object Ignored : ChatResult
    data class Failed(val cause: Throwable) : ChatResult
}

class ChatCoordinator(
    private val chatStore: ChatStore,
    private val inferenceEngine: InferenceEngine,
    private val systemPromptProvider: SystemPromptProvider,
    private val coreMemoryProvider: CoreMemoryProvider = CoreMemoryProvider { "" },
) {

    private val sendMutex = Mutex()

    suspend fun send(
        conversationId: Long,
        content: String,
        onUserMessageSaved: (String) -> Unit = {},
        onToken: (String) -> Unit = {},
    ): ChatResult {
        if (content.isBlank()) return ChatResult.Ignored
        if (!sendMutex.tryLock()) return ChatResult.Ignored

        return try {
            sendInternal(
                conversationId = conversationId,
                content = content,
                onToken = onToken,
                onUserMessageSaved = onUserMessageSaved,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (t: Throwable) {
            ChatResult.Failed(t)
        } finally {
            sendMutex.unlock()
        }
    }

    private suspend fun sendInternal(
        conversationId: Long,
        content: String,
        onToken: (String) -> Unit = {},
        onUserMessageSaved: (String) -> Unit = {},
    ): ChatResult {
        val text = content.trim()
        if (text.isEmpty()) {
            return ChatResult.Ignored
        }

        val currentState = inferenceEngine.state.value

        if (currentState != InferenceState.Ready) {
            return ChatResult.Failed(
                IllegalStateException(
                    "모델이 준비되지 않았습니다. 현재 상태: $currentState"
                )
            )
        }

        chatStore.saveMessage(
            conversationId = conversationId,
            role = MessageRole.USER,
            content = text,
        )
        onUserMessageSaved(text)

        val recentMessages = chatStore.recentMessages(conversationId)
            .map { message ->
                InferenceMessage(
                    role = when (message.role) {
                        MessageRole.SYSTEM -> InferenceRole.SYSTEM
                        MessageRole.USER -> InferenceRole.USER
                        MessageRole.ASSISTANT -> InferenceRole.ASSISTANT
                    },
                    content = message.content,
                )
            }

        val coreMemoryContext = buildCoreMemoryContext(
            coreMemory = coreMemoryProvider.buildMemory().trim(),
        )

        val messages = listOf(
            InferenceMessage(
                role = InferenceRole.SYSTEM,
                content = systemPromptProvider.buildPrompt(),
            )
        ) + coreMemoryContext + recentMessages

        val response = StringBuilder()
        var result: ChatResult? = null

        try {
            inferenceEngine.generate(messages).collect { event ->
                if (result != null) {
                    return@collect
                }

                when (event) {
                    is InferenceEvent.Token -> {
                        response.append(event.text)
                        onToken(response.toString())
                    }

                    InferenceEvent.Completed -> {
                        chatStore.saveMessage(
                            conversationId = conversationId,
                            role = MessageRole.ASSISTANT,
                            content = response.toString(),
                        )

                        result = ChatResult.Completed
                    }

                    InferenceEvent.Cancelled -> {
                        result = ChatResult.Cancelled
                    }

                    is InferenceEvent.Failed -> {
                        result = ChatResult.Failed(event.cause)
                    }
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (t: Throwable) {
            return ChatResult.Failed(t)
        }

        return result ?: ChatResult.Failed(
            IllegalStateException("추론이 종료 이벤트 없이 끝났습니다.")
        )
    }

    private fun buildCoreMemoryContext(
        coreMemory: String,
    ): List<InferenceMessage> {
        if (coreMemory.isBlank()) {
            return emptyList()
        }

        val userContext = buildString {
            appendLine("[사용자 기억 컨텍스트]")
            appendLine("다음은 이 대화를 하는 user가 자신에 대해 제공한 배경 정보다.")
            appendLine("각 항목의 1인칭 표현(나, 나는, 내가)은 user를 뜻한다.")
            appendLine("현재 요청과 관련 있을 때만 참고하라.")
            append(coreMemory)
        }

        return listOf(
            InferenceMessage(
                role = InferenceRole.USER,
                content = userContext,
            ),
            InferenceMessage(
                role = InferenceRole.ASSISTANT,
                content = "확인했다. 위 정보의 주체는 user다. 관련 있는 요청에만 참고한다.",
            ),
        )
    }

    fun cancel() {
        inferenceEngine.cancel()
    }
}
