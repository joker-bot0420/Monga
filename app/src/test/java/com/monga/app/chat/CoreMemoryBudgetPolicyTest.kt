package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import org.junit.Assert.assertEquals
import org.junit.Test

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
}
