package com.monga.app.chat

class DefaultSystemPromptProvider(
    private val personaProvider: PersonaProvider,
    private val coreMemoryProvider: CoreMemoryProvider,
) : SystemPromptProvider {

    override suspend fun buildPrompt(): String {
        val persona = personaProvider.buildPersona().trim()
        val coreMemory = coreMemoryProvider.buildMemory().trim()

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
            appendLine("- [사용자 사실]은 오직 user에 관한 정보다.")
            appendLine("- 사용자 사실은 현재 요청에 직접 관련될 때만 사용하라.")
            appendLine("- 답변에 [사용자 사실]이나 '사용자에 대한 사실' 같은 내부 라벨을 노출하지 마라.")

            if (coreMemory.isNotEmpty()) {
                appendLine()
                appendLine("[사용자 사실]")
                appendLine("아래 항목의 주체는 모두 user이며 assistant가 아니다.")
                append(coreMemory)
            }
        }
    }
}
