package com.monga.app.chat

import com.monga.app.inference.InferenceMessage
import com.monga.app.inference.InferenceRole

internal object ContextComposer {

    fun compose(
        systemPrompt: String,
        recentMessages: List<InferenceMessage>,
        coreMemory: String,
        episodicMemory: String = "",
    ): List<InferenceMessage> {
        val focusedMessages =
            if (coreMemory.isNotEmpty()) {
                dropTurnImmediatelyBeforeLatestUser(recentMessages)
            } else {
                recentMessages
            }

        val contextualMessages = attachMemoryToLatestUserMessage(
            messages = focusedMessages,
            coreMemory = coreMemory,
            episodicMemory = episodicMemory,
        )

        return listOf(
            InferenceMessage(
                role = InferenceRole.SYSTEM,
                content = systemPrompt,
            )
        ) + contextualMessages
    }

    private fun dropTurnImmediatelyBeforeLatestUser(
        messages: List<InferenceMessage>,
    ): List<InferenceMessage> {
        val lastUserIndex = messages.indexOfLast {
            it.role == InferenceRole.USER
        }

        val assistantIndex = lastUserIndex - 1
        val priorUserIndex = assistantIndex - 1

        if (
            lastUserIndex < 0 ||
            assistantIndex < 0 ||
            priorUserIndex < 0 ||
            messages[assistantIndex].role != InferenceRole.ASSISTANT ||
            messages[priorUserIndex].role != InferenceRole.USER
        ) {
            return messages
        }

        return messages.toMutableList().also { focused ->
            focused.removeAt(assistantIndex)
            focused.removeAt(priorUserIndex)
        }
    }

    private fun attachMemoryToLatestUserMessage(
        messages: List<InferenceMessage>,
        coreMemory: String,
        episodicMemory: String,
    ): List<InferenceMessage> {
        if (coreMemory.isBlank() && episodicMemory.isBlank()) {
            return messages
        }

        val lastUserIndex = messages.indexOfLast {
            it.role == InferenceRole.USER
        }

        if (lastUserIndex < 0) {
            return messages
        }

        val userMessage = messages[lastUserIndex]
        val contextualContent = buildString {
            if (coreMemory.isNotBlank()) {
                appendLine("[사용자 기억]")
                appendLine("다음은 현재 질문에 답할 때 참고할 user 본인의 정보다.")
                appendLine(coreMemory)
            }

            if (episodicMemory.isNotBlank()) {
                if (isNotEmpty()) {
                    appendLine()
                }
                appendLine("[과거 사건 기억]")
                appendLine("다음은 user의 과거 사건 기록이다.")
                appendLine(episodicMemory)
            }

            appendLine()
            appendLine("[현재 질문]")
            append(userMessage.content)
        }

        return messages.toMutableList().also { contextualized ->
            contextualized[lastUserIndex] = userMessage.copy(
                content = contextualContent,
            )
        }
    }
}
