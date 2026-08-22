package com.monga.app.chat

import com.monga.app.data.ChatStore
import com.monga.app.data.local.MessageRole
import com.monga.app.inference.InferenceEngine
import com.monga.app.inference.InferenceEvent
import kotlinx.coroutines.CancellationException
import com.monga.app.inference.InferenceMessage
import com.monga.app.inference.InferenceRole

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
) {
    suspend fun send(
        conversationId: Long,
        content: String,
        onToken: (String) -> Unit = {},
    ): ChatResult {
        val text = content.trim()
        if (text.isEmpty()) {
            return ChatResult.Ignored
        }

        chatStore.saveMessage(
            conversationId = conversationId,
            role = MessageRole.USER,
            content = text,
        )

        val messages = listOf(
            InferenceMessage(
                role = InferenceRole.SYSTEM,
                content = systemPromptProvider.buildPrompt(),
            )
        ) + chatStore.recentMessages(conversationId)
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

    fun cancel() {
        inferenceEngine.cancel()
    }
}
