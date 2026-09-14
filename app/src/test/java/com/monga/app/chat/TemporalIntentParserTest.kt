package com.monga.app.chat

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

class TemporalIntentParserTest {

    private val today = LocalDate.of(2026, 9, 14)

    @Test
    fun parsesExactKoreanDateWithoutYear() {
        assertEquals(
            TemporalIntent.ExactDate(LocalDate.of(2026, 9, 10)),
            TemporalIntentParser.parse("9월 10일에 뭐 했었지?", today),
        )
    }

    @Test
    fun futureMonthWithoutYearResolvesToPreviousYear() {
        assertEquals(
            TemporalIntent.ExactDate(LocalDate.of(2025, 12, 25)),
            TemporalIntentParser.parse("12월 25일에 뭐 했지?", today),
        )
    }

    @Test
    fun parsesRelativeDaysAndWeekRanges() {
        assertEquals(
            TemporalIntent.ExactDate(today.minusDays(1)),
            TemporalIntentParser.parse("어제 뭐 했지?", today),
        )
        assertEquals(
            TemporalIntent.DateRange(
                startInclusive = LocalDate.of(2026, 9, 14),
                endExclusive = LocalDate.of(2026, 9, 21),
            ),
            TemporalIntentParser.parse("이번 주에 뭐 했지?", today),
        )
        assertEquals(
            TemporalIntent.DateRange(
                startInclusive = LocalDate.of(2026, 9, 7),
                endExclusive = LocalDate.of(2026, 9, 14),
            ),
            TemporalIntentParser.parse("지난주에 뭐 했지?", today),
        )
    }

    @Test
    fun parsesRecallDirections() {
        assertEquals(
            TemporalIntent.LastTime,
            TemporalIntentParser.parse("지난번 회사에서 뭐 봤지?", today),
        )
        assertEquals(
            TemporalIntent.Recent,
            TemporalIntentParser.parse("최근에 녹차 마신 적 있어?", today),
        )
        assertEquals(
            TemporalIntent.OldPast,
            TemporalIntentParser.parse("예전에 회사에서 뭐 했지?", today),
        )
    }
}
