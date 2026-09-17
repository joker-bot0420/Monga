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
                        "- 2026-09-10 | 회사 어종 동정: 전갱이를 봤다.\n" +
                        "\n" +
                        "[기억 사용 규칙]\n" +
                        "위 기록은 앱이 현재 질문과 관련 있다고 선택한 사실 기록이다.\n" +
                        "질문의 표현과 기록의 표현이 달라도, 기록의 사실이 질문에 답이 되면 그 사실을 사용하라.\n" +
                        "질문에 날짜, 최근, 지난번 같은 시간 조건이 있으면 선택 단계에서 이미 반영되었다.\n" +
                        "기록이 질문의 일부에만 답할 수 있으면 확인되는 부분은 먼저 답하고, 나머지만 기록에 없다고 말하라.\n" +
                        "기록에 적힌 사건이 있으면 그 사건이 없었다고 부정하지 마라.\n" +
                        "기록에 없는 감정, 상태, 원인, 평가, 세부사항은 추측하지 마라.\n" +
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
                        "- 2026-09-12 | 토익 공부: 녹차를 마셨다.\n" +
                        "\n" +
                        "[기억 사용 규칙]\n" +
                        "위 기록은 앱이 현재 질문과 관련 있다고 선택한 사실 기록이다.\n" +
                        "질문의 표현과 기록의 표현이 달라도, 기록의 사실이 질문에 답이 되면 그 사실을 사용하라.\n" +
                        "질문에 날짜, 최근, 지난번 같은 시간 조건이 있으면 선택 단계에서 이미 반영되었다.\n" +
                        "기록이 질문의 일부에만 답할 수 있으면 확인되는 부분은 먼저 답하고, 나머지만 기록에 없다고 말하라.\n" +
                        "기록에 적힌 사건이 있으면 그 사건이 없었다고 부정하지 마라.\n" +
                        "기록에 없는 감정, 상태, 원인, 평가, 세부사항은 추측하지 마라.\n" +
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
