package com.monga.app.chat

import com.monga.app.data.local.EpisodicMemory
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class DefaultEpisodicMemoryProviderTest {

    @Test
    fun passesQueryAndTodayToSelectorAndRendersSelectedEpisode() = runBlocking {
        val zoneId = ZoneId.of("Asia/Seoul")
        val today = LocalDate.of(2026, 9, 14)
        val values = listOf(
            EpisodicMemory(
                id = 1L,
                title = "회사 어종 동정",
                content = "전갱이와 가자미류를 봤다.",
                occurredAt = LocalDate.of(2026, 9, 10)
                    .atStartOfDay(zoneId)
                    .toInstant()
                    .toEpochMilli(),
                createdAt = 100L,
            )
        )
        var receivedQuery = ""
        var receivedToday: LocalDate? = null

        val provider = DefaultEpisodicMemoryProvider(
            episodicMemories = flowOf(values),
            tokenCounter = { text -> text.length },
            selector = EpisodicMemorySelector { query, memories, selectorToday ->
                receivedQuery = query
                receivedToday = selectorToday
                memories
            },
            todayProvider = { today },
            zoneId = zoneId,
            tokenBudget = 500,
        )

        val result = provider.buildMemory("지난번 회사에서 뭐 봤지?")

        assertEquals("지난번 회사에서 뭐 봤지?", receivedQuery)
        assertEquals(today, receivedToday)
        assertEquals(
            "- 2026-09-10 | 회사 어종 동정: 전갱이와 가자미류를 봤다.",
            result,
        )
    }

    @Test
    fun returnsEmptyWhenSelectorFindsNoEpisode() = runBlocking {
        val provider = DefaultEpisodicMemoryProvider(
            episodicMemories = flowOf(emptyList()),
            tokenCounter = { text -> text.length },
            selector = EpisodicMemorySelector { _, _, _ -> emptyList() },
            todayProvider = { LocalDate.of(2026, 9, 14) },
        )

        assertEquals("", provider.buildMemory("오늘 기분 어때?"))
    }
}
