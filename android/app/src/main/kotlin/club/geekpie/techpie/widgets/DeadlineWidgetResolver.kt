package club.geekpie.techpie.widgets

import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object DeadlineWidgetResolver {
    const val HOUR_MILLIS: Long = 3_600_000L
    const val DAY_MILLIS: Long = 24L * HOUR_MILLIS
    const val SOON_MILLIS: Long = 72L * HOUR_MILLIS
    const val MAX_REFRESH_MILLIS: Long = 6L * HOUR_MILLIS

    sealed class CountdownToken {
        data object DueSoon : CountdownToken()
        data class Hours(val hours: Int) : CountdownToken()
        data class DaysHours(val days: Int, val hours: Int) : CountdownToken()
        data class Days(val days: Int) : CountdownToken()
    }

    fun activeItems(snapshot: DeadlineSnapshot?, nowMillis: Long): List<DeadlineItem> {
        if (snapshot == null) return emptyList()
        return snapshot.items
            .filter { it.dueAtMillis > nowMillis }
            .sortedWith(compareBy<DeadlineItem> { it.dueAtMillis }.thenBy { it.id })
    }

    fun urgency(dueAtMillis: Long, nowMillis: Long): DeadlineUrgency {
        val remaining = dueAtMillis - nowMillis
        if (remaining <= DAY_MILLIS) return DeadlineUrgency.URGENT
        if (remaining <= SOON_MILLIS) return DeadlineUrgency.SOON
        return DeadlineUrgency.NORMAL
    }

    fun countdownToken(dueAtMillis: Long, nowMillis: Long): CountdownToken {
        val remainingMillis = dueAtMillis - nowMillis
        if (remainingMillis < HOUR_MILLIS) return CountdownToken.DueSoon
        val wholeHours = (remainingMillis / HOUR_MILLIS).toInt()
        if (wholeHours < 24) return CountdownToken.Hours(wholeHours)
        if (wholeHours < 48) {
            return CountdownToken.DaysHours(
                days = wholeHours / 24,
                hours = wholeHours % 24,
            )
        }
        return CountdownToken.Days(days = wholeHours / 24)
    }

    fun formatAbsoluteDate(
        dueAtMillis: Long,
        nowMillis: Long,
        tz: TimeZone = TimeZone.getDefault(),
        locale: Locale = Locale.getDefault(),
    ): String {
        val sameYear = WidgetIso8601.localYear(dueAtMillis, tz) == WidgetIso8601.localYear(nowMillis, tz)
        val pattern = when (locale.language.lowercase(Locale.US)) {
            "zh", "ja" -> if (sameYear) "M月d日 HH:mm" else "yyyy年M月d日 HH:mm"
            else -> if (sameYear) "MMM d, HH:mm" else "yyyy MMM d, HH:mm"
        }
        val formatter: DateFormat = SimpleDateFormat(pattern, locale).apply {
            timeZone = tz
        }
        return formatter.format(Date(dueAtMillis))
    }

    fun nextRefreshMillis(
        snapshot: DeadlineSnapshot?,
        nowMillis: Long,
        tz: TimeZone = TimeZone.getDefault(),
    ): Long {
        val candidates = mutableListOf<Long>()
        candidates.add(WidgetIso8601.startOfNextLocalDayMillis(nowMillis, tz))
        candidates.add(nowMillis + MAX_REFRESH_MILLIS)

        val upcoming = activeItems(snapshot, nowMillis)
        for (item in upcoming) {
            candidates.add(item.dueAtMillis)
            val oneHourMark = item.dueAtMillis - HOUR_MILLIS
            if (oneHourMark > nowMillis) candidates.add(oneHourMark)
            val urgentMark = item.dueAtMillis - DAY_MILLIS
            if (urgentMark > nowMillis) candidates.add(urgentMark)
            val soonMark = item.dueAtMillis - SOON_MILLIS
            if (soonMark > nowMillis) candidates.add(soonMark)
        }
        if (upcoming.any { it.dueAtMillis - nowMillis <= 48L * HOUR_MILLIS }) {
            candidates.add(WidgetIso8601.startOfNextLocalHourMillis(nowMillis, tz))
        }
        return candidates.filter { it > nowMillis }.minOrNull() ?: (nowMillis + MAX_REFRESH_MILLIS)
    }
}
