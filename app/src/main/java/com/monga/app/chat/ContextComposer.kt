package com.monga.app.chat

import com.monga.app.inference.InferenceMessage
import com.monga.app.inference.InferenceRole

internal object ContextComposer {

    fun compose(
        systemPrompt: String,
        recentMessages: List<InferenceMessage>,
        coreMemory: String,
    ): List<InferenceMessage> {
        val contextualMessages =
            if (coreMemory.isNotEmpty()) {
                attachCoreMemoryToLatestUserMessage(
                    messages = dropTurnImmediatelyBeforeLatestUser(
                        recentMessages
                    ),
                    coreMemory = coreMemory,
                )
            } else {
                recentMessages
            }

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

    private fun attachCoreMemoryToLatestUserMessage(
        messages: List<InferenceMessage>,
        coreMemory: String,
    ): List<InferenceMessage> {
        if (coreMemory.isBlank()) {
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
            appendLine("[사용자 기억]")
            appendLine("다음은 현재 질문에 답할 때 참고할 user 본인의 정보다.")
            appendLine(coreMemory)
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
