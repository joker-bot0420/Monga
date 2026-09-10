package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue

class CoreMemoryBudgetPolicyTest {

    @Test
    fun keepsMemoriesWhenTheyFitWithinBudget() {
        val memories = listOf(
            CoreMemory(
                id = 1,
                content = "older",
                createdAt = 100,
                updatedAt = 100,
            ),
            CoreMemory(
                id = 2,
                content = "newer",
                createdAt = 200,
                updatedAt = 200,
            ),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 100,
            tokenCounter = { text -> text.length },
        )

        assertEquals(
            "- newer\n- older",
            result,
        )
    }

    @Test
    fun keepsNewerMemoriesWhenBudgetIsExceeded() {
        val memories = listOf(
            CoreMemory(
                id = 1,
                content = "old",
                createdAt = 100,
                updatedAt = 100,
            ),
            CoreMemory(
                id = 2,
                content = "mid",
                createdAt = 200,
                updatedAt = 200,
            ),
            CoreMemory(
                id = 3,
                content = "new",
                createdAt = 300,
                updatedAt = 300,
            ),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 11,
            tokenCounter = { text -> text.length },
        )

        assertEquals(
            "- new\n- mid",
            result,
        )
    }

    @Test
    fun returnsEmptyStringForEmptyMemoryList() {
        val result = CoreMemoryBudgetPolicy.build(
            memories = emptyList(),
            tokenCounter = {
                error("tokenCounter should not be called")
            },
        )

        assertEquals(
            "",
            result,
        )
    }

    @Test
    fun skipsOversizedMemoryAndKeepsSmallerOlderMemory() {
        val memories = listOf(
            CoreMemory(
                id = 1,
                content = "ok",
                createdAt = 100L,
                updatedAt = 100L,
            ),
            CoreMemory(
                id = 2,
                content = "1234567890",
                createdAt = 200L,
                updatedAt = 200L,
            ),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 7,
            tokenCounter = { it.length },
        )

        assertEquals("- ok", result)
    }

    @Test
    fun usesCreatedAtAndIdToBreakUpdatedAtTies() {
        val memories = listOf(
            CoreMemory(1, "a", 100L, 300L),
            CoreMemory(2, "b", 200L, 300L),
            CoreMemory(3, "c", 200L, 300L),
        )

        val result = CoreMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 7,
            tokenCounter = { it.length },
        )

        assertEquals("- c\n- b", result)
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
