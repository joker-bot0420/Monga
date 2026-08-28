package com.monga.app.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultSystemPromptProviderTest {

    @Test
    fun buildsPromptWithPersonaAndCoreMemoryInSeparateSections() = runBlocking {
        val provider = DefaultSystemPromptProvider(
            personaProvider = PersonaProvider {
                "- 친근하게 대화한다."
            },
            coreMemoryProvider = CoreMemoryProvider {
                "- 사용자는 녹차를 좋아한다."
            },
        )

        val prompt = provider.buildPrompt()

        assertTrue(prompt.contains("너는 몽아라는 AI다."))
        assertTrue(prompt.contains("[페르소나]"))
        assertTrue(prompt.contains("- 친근하게 대화한다."))
        assertTrue(prompt.contains("규칙:"))
        assertTrue(prompt.contains("[사용자 기억]"))
        assertTrue(prompt.contains("- 사용자는 녹차를 좋아한다."))

        assertTrue(
            prompt.indexOf("[페르소나]") <
                    prompt.indexOf("[사용자 기억]")
        )
    }
}
