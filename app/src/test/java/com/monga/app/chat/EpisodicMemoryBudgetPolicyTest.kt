package com.monga.app.chat

import com.monga.app.data.local.EpisodicMemory
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

class EpisodicMemoryBudgetPolicyTest {

    @Test
    fun preservesSelectorOrderAndSkipsOversizedEpisode() {
        val zoneId = ZoneId.of("Asia/Seoul")
        val memories = listOf(
            memory(
                id = 1,
                date = LocalDate.of(2026, 9, 10),
                title = "very long title",
                content = "this episode is intentionally much too long",
                zoneId = zoneId,
            ),
            memory(
                id = 2,
                date = LocalDate.of(2026, 9, 12),
                title = "짧은 기록",
                content = "녹차",
                zoneId = zoneId,
            ),
        )

        val result = EpisodicMemoryBudgetPolicy.build(
            memories = memories,
            tokenBudget = 35,
            tokenCounter = { text -> text.length },
            zoneId = zoneId,
        )

        assertEquals(
            "- 2026-09-12 | 짧은 기록: 녹차",
            result,
        )
    }

    private fun memory(
        id: Long,
        date: LocalDate,
        title: String,
        content: String,
        zoneId: ZoneId,
    ): EpisodicMemory = EpisodicMemory(
        id = id,
        title = title,
        content = content,
        occurredAt = date.atStartOfDay(zoneId).toInstant().toEpochMilli(),
        createdAt = id,
    )
}
