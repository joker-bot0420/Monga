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

        val contextualMessages = attachCoreMemoryToLatestUserMessage(
            messages = focusedMessages,
            coreMemory = coreMemory,
        )
        val groundedSystemPrompt = attachEpisodicMemoryToSystemPrompt(
            systemPrompt = systemPrompt,
            episodicMemory = episodicMemory,
        )

        return listOf(
            InferenceMessage(
                role = InferenceRole.SYSTEM,
                content = groundedSystemPrompt,
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

    private fun attachEpisodicMemoryToSystemPrompt(
        systemPrompt: String,
        episodicMemory: String,
    ): String {
        if (episodicMemory.isBlank()) {
            return systemPrompt
        }

        return buildString {
            append(systemPrompt)
            if (isNotEmpty() && last() != '\n') {
                appendLine()
            }
            appendLine()
            appendLine("[현재 질문의 사실 근거]")
            appendLine("다음은 앱이 현재 질문과 관련 있다고 선택한 user의 저장된 과거 사건 기록이다.")
            appendLine("질문의 표현과 기록의 표현이 달라도, 기록의 사실이 질문에 답이 되면 그 사실을 사용하라.")
            appendLine("질문의 날짜, 최근, 지난번 같은 시간 조건은 기록 선택에 이미 반영되어 있다.")
            appendLine("질문이 언제, 며칠, 날짜를 묻고 기록에 날짜가 있으면 그 날짜를 직접 답하라. 날짜를 알고도 질문을 되묻지 마라.")
            appendLine("응/아니는 질문 전체의 참·거짓을 기록으로 확실히 판단할 수 있을 때만 사용하라.")
            appendLine("긍정 질문이 기록으로 확인되면 응이라고 답하고 사실을 말하라.")
            appendLine("부정 질문이 기록과 충돌하면 아니라고 답하고 기록된 사실을 말하라.")
            appendLine("기록이 질문의 내용을 뒷받침하면 그 사실을 분명히 인정하라.")
            appendLine("기록이 질문의 내용을 반박하면 기록된 사실을 기준으로 바로잡아라.")
            appendLine("기록이 일부만 확인해 주면 확인된 부분과 확인되지 않은 부분을 구분하라.")
            appendLine("기록에 적힌 사건이 있으면 그 사건이 없었다고 말하지 마라.")
            appendLine("기록이 없다는 것은 사건이 없었다는 뜻이 아니다. 확인할 수 없다고 말하고, 일어나지 않았다고 단정하지 마라.")
            appendLine("기록으로 확인되지 않는 감정, 상태, 원인, 평가, 세부사항은 만들지 마라.")
            append(episodicMemory)
        }
    }
}
