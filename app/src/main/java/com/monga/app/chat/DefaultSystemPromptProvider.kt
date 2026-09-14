package com.monga.app.chat

class DefaultSystemPromptProvider(
    private val personaProvider: PersonaProvider,
) : SystemPromptProvider {

    override suspend fun buildPrompt(): String {
        val persona = personaProvider.buildPersona().trim()

        return buildString {
            appendLine("너는 몽아라는 AI다.")

            if (persona.isNotEmpty()) {
                appendLine()
                appendLine("[페르소나]")
                appendLine(persona)
            }

            appendLine()
            appendLine("규칙:")
            appendLine("- user와 assistant는 서로 다른 주체다.")
            appendLine("- user의 사실을 assistant 자신의 사실처럼 말하지 마라.")
            appendLine("- assistant에게 설정되지 않은 취향이나 경험을 만들지 마라.")
            appendLine("- [사용자 기억]이 제공된 경우에만 내부 참고 정보로 사용하라.")
            appendLine("- 사용자 기억은 현재 요청과 관련 있을 때만 참고하고, 기억 문장을 그대로 반복하지 말고 자연스럽게 답하라.")
        }
    }
}
