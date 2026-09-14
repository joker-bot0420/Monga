package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreMemoryBudgetPolicyTest {

    @Test
    fun keepsMemoriesInProvidedPriorityOrderWhenTheyFit() {
        val memories = listOf(
            CoreMemory(
                id = 2,
                content = "higher",
                createdAt = 200,
                updatedAt = 200,
            ),
            CoreMemory(
                id = 1,
                content = "lower",
                createdAt = 100,
                updatedAt = 100,
            ),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 100,
            tokenCounter = { text -> text.length },
        )

        assertEquals(
            "- higher\n- lower",
            result,
        )
    }

    @Test
    fun keepsHigherPriorityMemoriesWhenBudgetIsExceeded() {
        val memories = listOf(
            CoreMemory(3, "top", 300L, 300L),
            CoreMemory(2, "mid", 200L, 200L),
            CoreMemory(1, "low", 100L, 100L),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 11,
            tokenCounter = { text -> text.length },
        )

        assertEquals("- top\n- mid", result)
    }

    @Test
    fun returnsEmptyStringForEmptyMemoryList() {
        val result = CoreMemoryBudgetPolicy.build(
            memories = emptyList(),
            tokenCounter = {
                error("tokenCounter should not be called")
            },
        )

        assertEquals("", result)
    }

    @Test
    fun skipsOversizedMemoryAndKeepsLaterPriorityMemoryThatFits() {
        val memories = listOf(
            CoreMemory(2, "1234567890", 200L, 200L),
            CoreMemory(1, "ok", 100L, 100L),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 7,
            tokenCounter = { it.length },
        )

        assertEquals("- ok", result)
    }

    @Test
    fun rejectsNonPositiveTokenCounts() {
        val memories = listOf(
            CoreMemory(1, "memory", 100L, 100L),
        )

        for (invalidCount in listOf(0, -1)) {
            val error = assertThrows(IllegalStateException::class.java) {
                CoreMemoryBudgetPolicy.build(
                    memories = memories,
                    tokenCounter = { invalidCount },
                )
            }

            assertTrue(error.message.orEmpty().contains("토큰 수"))
        }
    }

    @Test
    fun returnsEmptyStringForNonPositiveBudgetsWithoutCounting() {
        val memories = listOf(
            CoreMemory(1, "memory", 100L, 100L),
        )

        for (budget in listOf(0, -1)) {
            val result = CoreMemoryBudgetPolicy.build(
                memories = memories,
                tokenBudget = budget,
                tokenCounter = {
                    error("tokenCounter should not be called")
                },
            )

            assertEquals("", result)
        }
    }
}
