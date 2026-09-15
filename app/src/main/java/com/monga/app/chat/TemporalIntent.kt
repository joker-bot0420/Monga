package com.monga.app.chat

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.TemporalAdjusters

sealed interface TemporalIntent {
    data object None : TemporalIntent
    data class ExactDate(val date: LocalDate) : TemporalIntent
    data class DateRange(
        val startInclusive: LocalDate,
        val endExclusive: LocalDate,
    ) : TemporalIntent
    data object LastTime : TemporalIntent
    data object Recent : TemporalIntent
    data object OldPast : TemporalIntent
}

internal object TemporalIntentParser {

    private val isoDate = Regex(
        "(?<!\\d)(\\d{4})[-./](\\d{1,2})[-./](\\d{1,2})(?!\\d)"
    )
    private val koreanDate = Regex(
        "(?<!\\d)(?:(\\d{4})년\\s*)?(\\d{1,2})월\\s*(\\d{1,2})일"
    )

    fun parse(
        query: String,
        today: LocalDate,
    ): TemporalIntent {
        val normalized = query.lowercase()

        if ("오늘" in normalized) {
            return TemporalIntent.ExactDate(today)
        }
        if ("어제" in normalized) {
            return TemporalIntent.ExactDate(today.minusDays(1))
        }

        parseExplicitDate(normalized, today)?.let {
            return TemporalIntent.ExactDate(it)
        }

        if ("이번주" in normalized || "이번 주" in normalized) {
            val start = today.with(
                TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)
            )
            return TemporalIntent.DateRange(
                startInclusive = start,
                endExclusive = start.plusDays(7),
            )
        }

        if ("지난주" in normalized || "지난 주" in normalized) {
            val thisWeekStart = today.with(
                TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)
            )
            val start = thisWeekStart.minusDays(7)
            return TemporalIntent.DateRange(
                startInclusive = start,
                endExclusive = thisWeekStart,
            )
        }

        if ("지난번" in normalized || "저번" in normalized) {
            return TemporalIntent.LastTime
        }
        if ("최근" in normalized || "요즘" in normalized) {
            return TemporalIntent.Recent
        }
        if (
            "예전에" in normalized ||
            "옛날" in normalized ||
            "오래전" in normalized
        ) {
            return TemporalIntent.OldPast
        }

        return TemporalIntent.None
    }

    private fun parseExplicitDate(
        query: String,
        today: LocalDate,
    ): LocalDate? {
        isoDate.find(query)?.let { match ->
            return runCatching {
                LocalDate.of(
                    match.groupValues[1].toInt(),
                    match.groupValues[2].toInt(),
                    match.groupValues[3].toInt(),
                )
            }.getOrNull()
        }

        koreanDate.find(query)?.let { match ->
            val explicitYear = match.groupValues[1]
                .takeIf(String::isNotEmpty)
                ?.toInt()
            val month = match.groupValues[2].toInt()
            val day = match.groupValues[3].toInt()

            if (explicitYear != null) {
                return runCatching {
                    LocalDate.of(explicitYear, month, day)
                }.getOrNull()
            }

            val thisYear = runCatching {
                LocalDate.of(today.year, month, day)
            }.getOrNull() ?: return null

            return if (thisYear.isAfter(today)) {
                runCatching {
                    LocalDate.of(today.year - 1, month, day)
                }.getOrNull()
            } else {
                thisYear
            }
        }

        return null
    }
}
