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
            appendLine("- 추측한 내용을 user의 사실이나 기억으로 단정하지 마라.")
        }
    }
}
