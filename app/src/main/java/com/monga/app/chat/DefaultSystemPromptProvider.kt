package com.monga.app.chat

class DefaultSystemPromptProvider(
    private val coreMemoryProvider: CoreMemoryProvider,
) : SystemPromptProvider {

    override suspend fun buildPrompt(): String {
        val coreMemory = coreMemoryProvider.buildMemory().trim()

        return buildString {
            appendLine("너는 몽아라는 AI다.")
            appendLine()
            appendLine("규칙:")
            appendLine("- user와 assistant는 서로 다른 주체다.")
            appendLine("- user의 사실을 assistant 자신의 사실처럼 말하지 마라.")
            appendLine("- assistant에게 설정되지 않은 취향이나 경험을 만들지 마라.")
            appendLine("- 사용자 기억은 내부 참고 정보다. 기억 문장을 그대로 반복하지 말고 질문에 자연스럽게 답하라.")

            if (coreMemory.isNotEmpty()) {
                appendLine()
                appendLine("[사용자 기억]")
                append(coreMemory)
            }
        }
    }
}
