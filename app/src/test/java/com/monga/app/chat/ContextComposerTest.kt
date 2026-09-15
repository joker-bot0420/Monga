package com.monga.app.chat

import com.monga.app.inference.InferenceMessage
import com.monga.app.inference.InferenceRole
import org.junit.Assert.assertEquals
import org.junit.Test

class ContextComposerTest {

    @Test
    fun noMemoryPreservesConversationExactly() {
        val recentMessages = listOf(
            message(InferenceRole.USER, "first question"),
            message(InferenceRole.ASSISTANT, "first answer"),
            message(InferenceRole.USER, "current question"),
        )

        val result = ContextComposer.compose(
            systemPrompt = "system prompt",
            recentMessages = recentMessages,
            coreMemory = "",
        )

        assertEquals(
            listOf(
                message(InferenceRole.SYSTEM, "system prompt"),
                message(InferenceRole.USER, "first question"),
                message(InferenceRole.ASSISTANT, "first answer"),
                message(InferenceRole.USER, "current question"),
            ),
            result,
        )
    }

    @Test
    fun memoryDropsOnlyImmediatePriorTurnAndAttachesToLatestUserExactly() {
        val recentMessages = listOf(
            message(InferenceRole.USER, "older question"),
            message(InferenceRole.ASSISTANT, "older answer"),
            message(InferenceRole.USER, "prior question"),
            message(InferenceRole.ASSISTANT, "prior answer"),
            message(InferenceRole.USER, "current question"),
        )

        val result = ContextComposer.compose(
            systemPrompt = "system prompt",
            recentMessages = recentMessages,
            coreMemory = "- memory alpha",
        )

        assertEquals(
            listOf(
                message(InferenceRole.SYSTEM, "system prompt"),
                message(InferenceRole.USER, "older question"),
                message(InferenceRole.ASSISTANT, "older answer"),
                message(
                    InferenceRole.USER,
                    "[사용자 기억]\n" +
                        "다음은 현재 질문에 답할 때 참고할 user 본인의 정보다.\n" +
                        "- memory alpha\n" +
                        "\n" +
                        "[현재 질문]\n" +
                        "current question",
                ),
            ),
            result,
        )
    }

    @Test
    fun memoryOnFirstTurnKeepsCurrentUserAndAddsNoSyntheticHistory() {
        val result = ContextComposer.compose(
            systemPrompt = "system prompt",
            recentMessages = listOf(
                message(InferenceRole.USER, "current question"),
            ),
            coreMemory = "- memory alpha",
        )

        assertEquals(
            listOf(
                message(InferenceRole.SYSTEM, "system prompt"),
                message(
                    InferenceRole.USER,
                    "[사용자 기억]\n" +
                        "다음은 현재 질문에 답할 때 참고할 user 본인의 정보다.\n" +
                        "- memory alpha\n" +
                        "\n" +
                        "[현재 질문]\n" +
                        "current question",
                ),
            ),
            result,
        )
    }

    @Test
    fun episodicMemoryKeepsImmediatePriorTurn() {
        val recentMessages = listOf(
            message(InferenceRole.USER, "prior question"),
            message(InferenceRole.ASSISTANT, "prior answer"),
            message(InferenceRole.USER, "current question"),
        )

        val result = ContextComposer.compose(
            systemPrompt = "system prompt",
            recentMessages = recentMessages,
            coreMemory = "",
            episodicMemory = "- 2026-09-10 | 회사 어종 동정: 전갱이를 봤다.",
        )

        assertEquals(
            listOf(
                message(InferenceRole.SYSTEM, "system prompt"),
                message(InferenceRole.USER, "prior question"),
                message(InferenceRole.ASSISTANT, "prior answer"),
                message(
                    InferenceRole.USER,
                    "[과거 사건 기억]\n" +
                        "다음은 user의 과거 사건 기록이다.\n" +
                        "- 2026-09-10 | 회사 어종 동정: 전갱이를 봤다.\n" +
                        "\n" +
                        "[현재 질문]\n" +
                        "current question",
                ),
            ),
            result,
        )
    }

    @Test
    fun coreAndEpisodicMemoryShareLatestUserContext() {
        val recentMessages = listOf(
            message(InferenceRole.USER, "prior question"),
            message(InferenceRole.ASSISTANT, "prior answer"),
            message(InferenceRole.USER, "current question"),
        )

        val result = ContextComposer.compose(
            systemPrompt = "system prompt",
            recentMessages = recentMessages,
            coreMemory = "- 사용자가 녹차를 좋아한다.",
            episodicMemory = "- 2026-09-12 | 토익 공부: 녹차를 마셨다.",
        )

        assertEquals(
            listOf(
                message(InferenceRole.SYSTEM, "system prompt"),
                message(
                    InferenceRole.USER,
                    "[사용자 기억]\n" +
                        "다음은 현재 질문에 답할 때 참고할 user 본인의 정보다.\n" +
                        "- 사용자가 녹차를 좋아한다.\n" +
                        "\n" +
                        "[과거 사건 기억]\n" +
                        "다음은 user의 과거 사건 기록이다.\n" +
                        "- 2026-09-12 | 토익 공부: 녹차를 마셨다.\n" +
                        "\n" +
                        "[현재 질문]\n" +
                        "current question",
                ),
            ),
            result,
        )
    }

    private fun message(
        role: InferenceRole,
        content: String,
    ) = InferenceMessage(
        role = role,
        content = content,
    )
}
