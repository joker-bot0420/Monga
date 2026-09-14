package com.monga.app.chat

import com.monga.app.data.local.EpisodicMemory
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EpisodicMemorySelectorTest {

    private val zoneId = ZoneId.of("Asia/Seoul")
    private val today = LocalDate.of(2026, 9, 14)
    private val selector = DefaultEpisodicMemorySelector(zoneId)

    private val memories = listOf(
        memory(
            id = 1,
            date = LocalDate.of(2026, 9, 10),
            title = "회사 어종 동정",
            content = "회사에서 전갱이와 가자미류를 동정했다.",
        ),
        memory(
            id = 2,
            date = LocalDate.of(2026, 9, 12),
            title = "토익 공부",
            content = "녹차를 마시면서 TOEIC 공부를 했다.",
        ),
        memory(
            id = 3,
            date = LocalDate.of(2026, 9, 13),
            title = "자동차 매물 확인",
            content = "중고차 매물을 비교했다.",
        ),
        memory(
            id = 4,
            date = LocalDate.of(2026, 9, 14),
            title = "점심",
            content = "회사에서 점심을 먹었다.",
        ),
    )

    @Test
    fun lastTimeUsesRelevantEpisodeInsteadOfNewestUnrelatedEpisode() {
        val result = selector.select(
            userMessage = "지난번 회사에서 어떤 어종 봤었지?",
            memories = memories,
            today = today,
        )

        assertEquals(listOf(1L), result.map { it.id })
    }

    @Test
    fun recentRecallFindsRelevantEpisode() {
        val result = selector.select(
            userMessage = "최근에 녹차 마신 적 있었지?",
            memories = memories,
            today = today,
        )

        assertEquals(listOf(2L), result.map { it.id })
    }

    @Test
    fun exactDateCanRecallEpisodeWithoutTopicKeywords() {
        val result = selector.select(
            userMessage = "9월 10일에 뭐 했었지?",
            memories = memories,
            today = today,
        )

        assertEquals(listOf(1L), result.map { it.id })
    }

    @Test
    fun genericRecentRecallFallsBackToNewestEpisode() {
        val result = selector.select(
            userMessage = "최근에 뭐 했었지?",
            memories = memories,
            today = today,
        )

        assertEquals(listOf(4L), result.map { it.id })
    }

    @Test
    fun unrelatedTodayQuestionDoesNotInjectTodaysEpisode() {
        val result = selector.select(
            userMessage = "오늘 기분 어때?",
            memories = memories,
            today = today,
        )

        assertTrue(result.isEmpty())
    }

    @Test
    fun referentialLastTimeQuestionDoesNotForceUnrelatedEpisode() {
        val result = selector.select(
            userMessage = "지난번에 그거 어떻게 됐어?",
            memories = memories,
            today = today,
        )

        assertTrue(result.isEmpty())
    }

    @Test
    fun explicitRangeCanReturnTwoEpisodesForMultipleRequest() {
        val result = selector.select(
            userMessage = "지난주에 무슨 일 몇 개 있었지?",
            memories = memories,
            today = today,
        )

        assertEquals(listOf(3L, 2L), result.map { it.id })
    }

    private fun memory(
        id: Long,
        date: LocalDate,
        title: String,
        content: String,
    ): EpisodicMemory = EpisodicMemory(
        id = id,
        title = title,
        content = content,
        occurredAt = date
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli(),
        createdAt = id,
    )
}
