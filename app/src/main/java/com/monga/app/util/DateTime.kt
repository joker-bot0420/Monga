package com.monga.app.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

data class EpochRange(val start: Long, val endExclusive: Long)

fun LocalDate.epochRange(zoneId: ZoneId = ZoneId.systemDefault()): EpochRange = EpochRange(
    atStartOfDay(zoneId).toInstant().toEpochMilli(),
    plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli(),
)

fun Long.toLocalDate(zoneId: ZoneId = ZoneId.systemDefault()): LocalDate =
    Instant.ofEpochMilli(this).atZone(zoneId).toLocalDate()

