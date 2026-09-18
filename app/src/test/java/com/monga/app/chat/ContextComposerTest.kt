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
    fun episodicMemoryKeepsImmediatePriorTurnAndGroundsSystemPrompt() {
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
                message(
                    InferenceRole.SYSTEM,
                    "system prompt\n" +
                        "\n" +
                        "[현재 질문의 사실 근거]\n" +
                        "다음은 앱이 현재 질문과 관련 있다고 선택한 user의 저장된 과거 사건 기록이다.\n" +
                        "질문의 표현과 기록의 표현이 달라도, 기록의 사실이 질문에 답이 되면 그 사실을 사용하라.\n" +
                        "질문의 날짜, 최근, 지난번 같은 시간 조건은 기록 선택에 이미 반영되어 있다.\n" +
                        "응/아니는 질문 전체의 참·거짓을 기록으로 확실히 판단할 수 있을 때만 사용하라.\n" +
                        "긍정 질문이 기록으로 확인되면 응이라고 답하고 사실을 말하라.\n" +
                        "부정 질문이 기록과 충돌하면 아니라고 답하고 기록된 사실을 말하라.\n" +
                        "기록이 질문의 내용을 뒷받침하면 그 사실을 분명히 인정하라.\n" +
                        "기록이 질문의 내용을 반박하면 기록된 사실을 기준으로 바로잡아라.\n" +
                        "기록이 일부만 확인해 주면 확인된 부분과 확인되지 않은 부분을 구분하라.\n" +
                        "기록에 적힌 사건이 있으면 그 사건이 없었다고 말하지 마라.\n" +
                        "기록이 없다는 것은 사건이 없었다는 뜻이 아니다. 확인할 수 없다고 말하고, 일어나지 않았다고 단정하지 마라.\n" +
                        "기록으로 확인되지 않는 감정, 상태, 원인, 평가, 세부사항은 만들지 마라.\n" +
                        "- 2026-09-10 | 회사 어종 동정: 전갱이를 봤다.",
                ),
                message(InferenceRole.USER, "prior question"),
                message(InferenceRole.ASSISTANT, "prior answer"),
                message(InferenceRole.USER, "current question"),
            ),
            result,
        )
    }

    @Test
    fun coreAndEpisodicMemoryUseSeparateContextChannels() {
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
                message(
                    InferenceRole.SYSTEM,
                    "system prompt\n" +
                        "\n" +
                        "[현재 질문의 사실 근거]\n" +
                        "다음은 앱이 현재 질문과 관련 있다고 선택한 user의 저장된 과거 사건 기록이다.\n" +
                        "질문의 표현과 기록의 표현이 달라도, 기록의 사실이 질문에 답이 되면 그 사실을 사용하라.\n" +
                        "질문의 날짜, 최근, 지난번 같은 시간 조건은 기록 선택에 이미 반영되어 있다.\n" +
                        "응/아니는 질문 전체의 참·거짓을 기록으로 확실히 판단할 수 있을 때만 사용하라.\n" +
                        "긍정 질문이 기록으로 확인되면 응이라고 답하고 사실을 말하라.\n" +
                        "부정 질문이 기록과 충돌하면 아니라고 답하고 기록된 사실을 말하라.\n" +
                        "기록이 질문의 내용을 뒷받침하면 그 사실을 분명히 인정하라.\n" +
                        "기록이 질문의 내용을 반박하면 기록된 사실을 기준으로 바로잡아라.\n" +
                        "기록이 일부만 확인해 주면 확인된 부분과 확인되지 않은 부분을 구분하라.\n" +
                        "기록에 적힌 사건이 있으면 그 사건이 없었다고 말하지 마라.\n" +
                        "기록이 없다는 것은 사건이 없었다는 뜻이 아니다. 확인할 수 없다고 말하고, 일어나지 않았다고 단정하지 마라.\n" +
                        "기록으로 확인되지 않는 감정, 상태, 원인, 평가, 세부사항은 만들지 마라.\n" +
                        "- 2026-09-12 | 토익 공부: 녹차를 마셨다.",
                ),
                message(
                    InferenceRole.USER,
                    "[사용자 기억]\n" +
                        "다음은 현재 질문에 답할 때 참고할 user 본인의 정보다.\n" +
                        "- 사용자가 녹차를 좋아한다.\n" +
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
