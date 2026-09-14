package com.monga.app.chat

import com.monga.app.data.local.EpisodicMemory
import com.monga.app.util.toLocalDate
import java.time.LocalDate
import java.time.ZoneId

fun interface EpisodicMemorySelector {
    fun select(
        userMessage: String,
        memories: List<EpisodicMemory>,
        today: LocalDate,
    ): List<EpisodicMemory>
}

internal class DefaultEpisodicMemorySelector(
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : EpisodicMemorySelector {

    companion object {
        private const val MIN_SCORE = 4
        private const val DEFAULT_MAX_SELECTED = 1
        private const val MULTIPLE_MAX_SELECTED = 2
        private const val RECENT_WINDOW_DAYS = 30L
    }

    private data class ScoredMemory(
        val memory: EpisodicMemory,
        val score: Int,
    )

    override fun select(
        userMessage: String,
        memories: List<EpisodicMemory>,
        today: LocalDate,
    ): List<EpisodicMemory> {
        if (userMessage.isBlank() || memories.isEmpty()) {
            return emptyList()
        }

        val scored = memories.map { memory ->
            ScoredMemory(
                memory = memory,
                score = MemoryRelevanceScorer.score(
                    query = userMessage,
                    memory = "${memory.title} ${memory.content}",
                ),
            )
        }
        val maxSelected = if (asksForMultiple(userMessage)) {
            MULTIPLE_MAX_SELECTED
        } else {
            DEFAULT_MAX_SELECTED
        }

        return when (
            val intent = TemporalIntentParser.parse(
                query = userMessage,
                today = today,
            )
        ) {
            TemporalIntent.None ->
                selectRelevant(
                    candidates = scored,
                    maxSelected = maxSelected,
                    newestFirst = true,
                )

            is TemporalIntent.ExactDate ->
                selectExplicitRange(
                    query = userMessage,
                    candidates = scored,
                    startInclusive = intent.date,
                    endExclusive = intent.date.plusDays(1),
                    maxSelected = maxSelected,
                )

            is TemporalIntent.DateRange ->
                selectExplicitRange(
                    query = userMessage,
                    candidates = scored,
                    startInclusive = intent.startInclusive,
                    endExclusive = intent.endExclusive,
                    maxSelected = maxSelected,
                )

            TemporalIntent.LastTime ->
                selectTemporalRecall(
                    query = userMessage,
                    candidates = scored,
                    maxSelected = 1,
                    newestFirst = true,
                )

            TemporalIntent.Recent -> {
                val start = today.minusDays(RECENT_WINDOW_DAYS - 1)
                selectTemporalRecall(
                    query = userMessage,
                    candidates = scored.filter {
                        val date = it.memory.occurredAt.toLocalDate(zoneId)
                        !date.isBefore(start) && !date.isAfter(today)
                    },
                    maxSelected = maxSelected,
                    newestFirst = true,
                )
            }

            TemporalIntent.OldPast ->
                selectTemporalRecall(
                    query = userMessage,
                    candidates = scored,
                    maxSelected = maxSelected,
                    newestFirst = false,
                )
        }
    }

    private fun selectExplicitRange(
        query: String,
        candidates: List<ScoredMemory>,
        startInclusive: LocalDate,
        endExclusive: LocalDate,
        maxSelected: Int,
    ): List<EpisodicMemory> {
        val inRange = candidates.filter { scored ->
            val date = scored.memory.occurredAt.toLocalDate(zoneId)
            !date.isBefore(startInclusive) && date.isBefore(endExclusive)
        }

        if (inRange.isEmpty()) {
            return emptyList()
        }

        val relevant = inRange.filter { it.score >= MIN_SCORE }
        val source = when {
            relevant.isNotEmpty() -> relevant
            hasGenericEventRecall(query) -> inRange
            else -> return emptyList()
        }

        return source
            .sortedWith(
                compareByDescending<ScoredMemory> { it.score }
                    .thenByDescending { it.memory.occurredAt }
                    .thenByDescending { it.memory.id }
            )
            .take(maxSelected)
            .map { it.memory }
    }

    private fun selectTemporalRecall(
        query: String,
        candidates: List<ScoredMemory>,
        maxSelected: Int,
        newestFirst: Boolean,
    ): List<EpisodicMemory> {
        if (candidates.isEmpty()) {
            return emptyList()
        }

        val relevant = candidates.filter { it.score >= MIN_SCORE }
        if (relevant.isNotEmpty()) {
            return sortByRelevanceAndTime(
                candidates = relevant,
                newestFirst = newestFirst,
            )
                .take(maxSelected)
                .map { it.memory }
        }

        if (hasReferentialHint(query) || !hasGenericEventRecall(query)) {
            return emptyList()
        }

        return sortByTimeOnly(
            candidates = candidates,
            newestFirst = newestFirst,
        )
            .take(maxSelected)
            .map { it.memory }
    }

    private fun selectRelevant(
        candidates: List<ScoredMemory>,
        maxSelected: Int,
        newestFirst: Boolean,
    ): List<EpisodicMemory> =
        sortByRelevanceAndTime(
            candidates = candidates.filter { it.score >= MIN_SCORE },
            newestFirst = newestFirst,
        )
            .take(maxSelected)
            .map { it.memory }

    private fun sortByRelevanceAndTime(
        candidates: List<ScoredMemory>,
        newestFirst: Boolean,
    ): List<ScoredMemory> {
        val comparator = if (newestFirst) {
            compareByDescending<ScoredMemory> { it.score }
                .thenByDescending { it.memory.occurredAt }
                .thenByDescending { it.memory.id }
        } else {
            compareByDescending<ScoredMemory> { it.score }
                .thenBy { it.memory.occurredAt }
                .thenBy { it.memory.id }
        }

        return candidates.sortedWith(comparator)
    }

    private fun sortByTimeOnly(
        candidates: List<ScoredMemory>,
        newestFirst: Boolean,
    ): List<ScoredMemory> =
        if (newestFirst) {
            candidates.sortedWith(
                compareByDescending<ScoredMemory> { it.memory.occurredAt }
                    .thenByDescending { it.memory.id }
            )
        } else {
            candidates.sortedWith(
                compareBy<ScoredMemory> { it.memory.occurredAt }
                    .thenBy { it.memory.id }
            )
        }

    private fun asksForMultiple(query: String): Boolean {
        val normalized = query.lowercase()
        return listOf(
            "몇 개",
            "몇개",
            "뭐뭐",
            "여러",
            "일들",
            "것들",
        ).any(normalized::contains)
    }

    private fun hasGenericEventRecall(query: String): Boolean {
        val normalized = query.lowercase()
        return listOf(
            "뭐 했",
            "뭐했",
            "뭘 했",
            "뭘했",
            "무슨 일",
            "어떤 일",
            "일 있었",
        ).any(normalized::contains)
    }

    private fun hasReferentialHint(query: String): Boolean {
        val normalized = query.lowercase()
        return listOf(
            "그거",
            "그건",
            "그게",
            "그걸",
            "그때",
            "그 일",
            "그것",
        ).any(normalized::contains)
    }
}
