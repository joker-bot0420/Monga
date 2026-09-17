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
                appendLine(episodicMemory)
                appendLine()
                appendLine("[기억 사용 규칙]")
                appendLine("위 기록은 앱이 현재 질문과 관련 있다고 선택한 사실 기록이다.")
                appendLine("질문의 표현과 기록의 표현이 달라도, 기록의 사실이 질문에 답이 되면 그 사실을 사용하라.")
                appendLine("질문에 날짜, 최근, 지난번 같은 시간 조건이 있으면 선택 단계에서 이미 반영되었다.")
                appendLine("기록이 질문의 일부에만 답할 수 있으면 확인되는 부분은 먼저 답하고, 나머지만 기록에 없다고 말하라.")
                appendLine("기록에 적힌 사건이 있으면 그 사건이 없었다고 부정하지 마라.")
                appendLine("기록에 없는 감정, 상태, 원인, 평가, 세부사항은 추측하지 마라.")
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
