package com.monga.app.chat

import com.monga.app.data.local.CoreMemory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreMemorySelectorTest {

    private val memories = listOf(
        CoreMemory(
            id = 1,
            content = "내가 좋아하는 음료는 녹차다.",
            createdAt = 100L,
            updatedAt = 100L,
        ),
        CoreMemory(
            id = 2,
            content = "내 생일은 7월 17일이다.",
            createdAt = 200L,
            updatedAt = 200L,
        ),
        CoreMemory(
            id = 3,
            content = "나는 포항에 산다.",
            createdAt = 300L,
            updatedAt = 300L,
        ),
        CoreMemory(
            id = 4,
            content = "나는 해양생태 연구자가 되고 싶다.",
            createdAt = 400L,
            updatedAt = 400L,
        ),
        CoreMemory(
            id = 5,
            content = "나는 추위에 약하다.",
            createdAt = 500L,
            updatedAt = 500L,
        ),
    )

    @Test
    fun selectsOnlyBeverageMemoryForRecall() {
        val result = DefaultCoreMemorySelector.select(
            userMessage = "내가 좋아하는 음료가 뭐였지?",
            memories = memories,
        )

        assertEquals(listOf(1L), result.map { it.id })
    }

    @Test
    fun selectsOnlyBirthdayMemory() {
        val result = DefaultCoreMemorySelector.select(
            userMessage = "내 생일이 언제였지?",
            memories = memories,
        )

        assertEquals(listOf(2L), result.map { it.id })
    }

    @Test
    fun selectsOnlyLocationMemory() {
        val result = DefaultCoreMemorySelector.select(
            userMessage = "나는 어디에 살지?",
            memories = memories,
        )

        assertEquals(listOf(3L), result.map { it.id })
    }

    @Test
    fun selectsBeverageMemoryForTeaRecommendation() {
        val result = DefaultCoreMemorySelector.select(
            userMessage = "내 취향에 맞는 차 추천해줘.",
            memories = memories,
        )

        assertEquals(listOf(1L), result.map { it.id })
    }

    @Test
    fun returnsNoMemoryForUnrelatedQuestion() {
        val result = DefaultCoreMemorySelector.select(
            userMessage = "오늘 기분 어때?",
            memories = memories,
        )

        assertTrue(result.isEmpty())
    }

    @Test
    fun doesNotTreatCarPreferenceAsTeaPreference() {
        val customMemories = listOf(
            CoreMemory(
                id = 20,
                content = "나는 자동차를 좋아한다.",
                createdAt = 200L,
                updatedAt = 200L,
            ),
            CoreMemory(
                id = 21,
                content = "내가 좋아하는 음료는 녹차다.",
                createdAt = 100L,
                updatedAt = 100L,
            ),
        )

        val result = DefaultCoreMemorySelector.select(
            userMessage = "내 취향에 맞는 차 추천해줘.",
            memories = customMemories,
        )

        assertEquals(listOf(21L), result.map { it.id })
    }

    @Test
    fun doesNotTreatBuyingSomethingAsResidence() {
        val customMemories = listOf(
            CoreMemory(
                id = 30,
                content = "나는 녹차를 자주 산다.",
                createdAt = 200L,
                updatedAt = 200L,
            ),
            CoreMemory(
                id = 31,
                content = "나는 포항에 산다.",
                createdAt = 100L,
                updatedAt = 100L,
            ),
        )

        val result = DefaultCoreMemorySelector.select(
            userMessage = "나는 어디에 살지?",
            memories = customMemories,
        )

        assertEquals(listOf(31L), result.map { it.id })
    }

    @Test
    fun fallsBackToStrongKeywordOverlapForUnlistedTopics() {
        val customMemories = listOf(
            CoreMemory(
                id = 10,
                content = "내 최애 포켓몬은 킬가르도다.",
                createdAt = 100L,
                updatedAt = 100L,
            ),
            CoreMemory(
                id = 11,
                content = "나는 포항에 산다.",
                createdAt = 200L,
                updatedAt = 200L,
            ),
        )

        val result = DefaultCoreMemorySelector.select(
            userMessage = "내 최애 포켓몬이 뭐였지?",
            memories = customMemories,
        )

        assertEquals(listOf(10L), result.map { it.id })
    }
}
