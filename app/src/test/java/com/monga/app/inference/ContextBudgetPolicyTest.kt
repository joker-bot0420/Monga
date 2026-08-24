package com.monga.app.inference

import org.junit.Assert.assertEquals
import org.junit.Test

class ContextBudgetPolicyTest {

    @Test
    fun dropsOldestTurnAndPreservesSystemAndCurrentUserMessage() {
        val messages = listOf(
            InferenceMessage(
                role = InferenceRole.SYSTEM,
                content = "system",
            ),
            InferenceMessage(
                role = InferenceRole.USER,
                content = "old user",
            ),
            InferenceMessage(
                role = InferenceRole.ASSISTANT,
                content = "old assistant",
            ),
            InferenceMessage(
                role = InferenceRole.USER,
                content = "current user",
            ),
        )

        val result =
            ContextBudgetPolicy.dropOldestTurn(messages)

        assertEquals(
            listOf(
                InferenceMessage(
                    role = InferenceRole.SYSTEM,
                    content = "system",
                ),
                InferenceMessage(
                    role = InferenceRole.USER,
                    content = "current user",
                ),
            ),
            result,
        )
    }

    @Test
    fun alsoWorksWithoutSystemMessage() {
        val messages = listOf(
            InferenceMessage(
                role = InferenceRole.USER,
                content = "old user",
            ),
            InferenceMessage(
                role = InferenceRole.ASSISTANT,
                content = "old assistant",
            ),
            InferenceMessage(
                role = InferenceRole.USER,
                content = "current user",
            ),
        )

        val result =
            ContextBudgetPolicy.dropOldestTurn(messages)

        assertEquals(
            listOf(
                InferenceMessage(
                    role = InferenceRole.USER,
                    content = "current user",
                ),
            ),
            result,
        )
    }

    @Test
    fun repeatedlyDropsOldestTurnsWhilePreservingCurrentUserMessage() {
        var messages = listOf(
            InferenceMessage(InferenceRole.SYSTEM, "system"),
            InferenceMessage(InferenceRole.USER, "user 1"),
            InferenceMessage(InferenceRole.ASSISTANT, "assistant 1"),
            InferenceMessage(InferenceRole.USER, "user 2"),
            InferenceMessage(InferenceRole.ASSISTANT, "assistant 2"),
            InferenceMessage(InferenceRole.USER, "current user"),
        )

        messages = ContextBudgetPolicy.dropOldestTurn(messages)
        messages = ContextBudgetPolicy.dropOldestTurn(messages)

        assertEquals(
            listOf(
                InferenceMessage(InferenceRole.SYSTEM, "system"),
                InferenceMessage(InferenceRole.USER, "current user"),
            ),
            messages,
        )
    }
}
