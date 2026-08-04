package com.monga.app.util

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class DateTimeTest {
    @Test fun epochRangeUsesNextLocalDayAsExclusiveEnd() {
        val range = LocalDate.of(2026, 8, 4).epochRange(ZoneId.of("Asia/Seoul"))
        assertEquals(24 * 60 * 60 * 1000L, range.endExclusive - range.start)
        assertEquals(LocalDate.of(2026, 8, 4), range.start.toLocalDate(ZoneId.of("Asia/Seoul")))
    }
}

