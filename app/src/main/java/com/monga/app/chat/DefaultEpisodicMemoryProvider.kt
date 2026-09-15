package com.monga.app.chat

import com.monga.app.data.local.EpisodicMemory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import java.time.LocalDate
import java.time.ZoneId

class DefaultEpisodicMemoryProvider(
    private val episodicMemories: Flow<List<EpisodicMemory>>,
    private val tokenCounter: (String) -> Int,
    private val selector: EpisodicMemorySelector = DefaultEpisodicMemorySelector(),
    private val todayProvider: () -> LocalDate = { LocalDate.now() },
    private val zoneId: ZoneId = ZoneId.systemDefault(),
    private val tokenBudget: Int = EpisodicMemoryBudgetPolicy.DEFAULT_TOKEN_BUDGET,
) : EpisodicMemoryProvider {

    override suspend fun buildMemory(userMessage: String): String {
        val selected = selector.select(
            userMessage = userMessage,
            memories = episodicMemories.first(),
            today = todayProvider(),
        )

        if (selected.isEmpty()) {
            return ""
        }

        return EpisodicMemoryBudgetPolicy.build(
            memories = selected,
            tokenBudget = tokenBudget,
            tokenCounter = tokenCounter,
            zoneId = zoneId,
        )
    }
}
