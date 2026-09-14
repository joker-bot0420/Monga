package com.monga.app.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultSystemPromptProviderTest {

    @Test
    fun buildsStaticPromptWithoutMemoryMarker() = runBlocking {
        val provider = DefaultSystemPromptProvider(
            personaProvider = PersonaProvider {
                "- 친근하게 대화한다."
            },
        )

        val prompt = provider.buildPrompt()

        assertTrue(prompt.contains("너는 몽아라는 AI다."))
        assertTrue(prompt.contains("[페르소나]"))
        assertTrue(prompt.contains("- 친근하게 대화한다."))
        assertTrue(prompt.contains("규칙:"))
        assertTrue(
            prompt.contains(
                "- 추측한 내용을 user의 사실이나 기억으로 단정하지 마라."
            )
        )
        assertFalse(prompt.contains("[사용자 기억]"))
        assertFalse(prompt.contains("녹차"))

        assertTrue(
            prompt.indexOf("[페르소나]") <
                    prompt.indexOf("규칙:")
        )
    }
}
