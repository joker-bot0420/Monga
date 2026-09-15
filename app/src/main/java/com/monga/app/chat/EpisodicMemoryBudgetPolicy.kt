package com.monga.app.chat

import com.monga.app.data.local.EpisodicMemory
import com.monga.app.util.toLocalDate
import java.time.ZoneId

internal object EpisodicMemoryBudgetPolicy {

    const val DEFAULT_TOKEN_BUDGET = 768

    fun build(
        memories: List<EpisodicMemory>,
        tokenBudget: Int = DEFAULT_TOKEN_BUDGET,
        tokenCounter: (String) -> Int,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): String {
        if (memories.isEmpty() || tokenBudget <= 0) {
            return ""
        }

        val selected = mutableListOf<EpisodicMemory>()

        for (memory in memories) {
            val candidate = selected + memory
            val rendered = render(candidate, zoneId)
            val tokenCount = tokenCounter(rendered)

            if (tokenCount <= 0) {
                throw IllegalStateException(
                    "과거 사건 기억의 토큰 수를 확인하지 못했습니다."
                )
            }

            if (tokenCount <= tokenBudget) {
                selected += memory
            }
        }

        return render(selected, zoneId)
    }

    private fun render(
        memories: List<EpisodicMemory>,
        zoneId: ZoneId,
    ): String =
        memories.joinToString(separator = "\n") { memory ->
            val date = memory.occurredAt.toLocalDate(zoneId)
            "- $date | ${memory.title}: ${memory.content}"
        }
}
