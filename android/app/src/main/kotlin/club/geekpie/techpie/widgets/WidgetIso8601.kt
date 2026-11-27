package club.geekpie.techpie.widgets

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

object WidgetIso8601 {
    private val utcTimeZone: TimeZone = TimeZone.getTimeZone("UTC")
    private val isoRegex = Regex(
        """^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:?\d{2})$""",
    )

    fun parseUtcIsoMillis(raw: String): Long? {
        val match = isoRegex.matchEntire(raw.trim()) ?: return null
        val year = match.groupValues[1].toIntOrNull() ?: return null
        val month = match.groupValues[2].toIntOrNull() ?: return null
        val day = match.groupValues[3].toIntOrNull() ?: return null
        val hour = match.groupValues[4].toIntOrNull() ?: return null
        val minute = match.groupValues[5].toIntOrNull() ?: return null
        val second = match.groupValues[6].toIntOrNull() ?: return null
        val fraction = match.groupValues[7]
        val offsetToken = match.groupValues[8]

        if (month !in 1..12 || day !in 1..31 || hour !in 0..23 || minute !in 0..59 || second !in 0..59) {
            return null
        }

        val millis = if (fraction.isEmpty()) {
            0
        } else {
            fraction.padEnd(3, '0').take(3).toIntOrNull() ?: return null
        }

        val cal = Calendar.getInstance(utcTimeZone, Locale.US).apply {
            isLenient = false
            clear()
            set(year, month - 1, day, hour, minute, second)
            set(Calendar.MILLISECOND, millis)
        }

        val baseUtc = try {
            cal.timeInMillis
        } catch (_: IllegalArgumentException) {
            return null
        }

        if (offsetToken == "Z") return baseUtc

        val sign = if (offsetToken.startsWith("-")) -1 else 1
        val digits = offsetToken.substring(1).replace(":", "")
        if (digits.length != 4) return null
        val offHours = digits.substring(0, 2).toIntOrNull() ?: return null
        val offMinutes = digits.substring(2, 4).toIntOrNull() ?: return null
        if (offHours > 23 || offMinutes > 59) return null
        val offsetMillis = sign * ((offHours * 60L + offMinutes) * 60_000L)
        return baseUtc - offsetMillis
    }

    fun formatLocalDayKey(millis: Long, tz: TimeZone = TimeZone.getDefault()): String {
        val cal = Calendar.getInstance(tz, Locale.US).apply { timeInMillis = millis }
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val day = cal.get(Calendar.DAY_OF_MONTH)
        return String.format(Locale.US, "%04d-%02d-%02d", year, month, day)
    }

    fun addDaysToLocalDayKey(
        millis: Long,
        days: Int,
        tz: TimeZone = TimeZone.getDefault(),
    ): String {
        val cal = Calendar.getInstance(tz, Locale.US).apply {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 12)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, days)
        }
        return formatLocalDayKey(cal.timeInMillis, tz)
    }

    fun startOfLocalDayMillis(millis: Long, tz: TimeZone = TimeZone.getDefault()): Long {
        val cal = Calendar.getInstance(tz, Locale.US).apply {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis
    }

    fun startOfNextLocalDayMillis(millis: Long, tz: TimeZone = TimeZone.getDefault()): Long {
        val cal = Calendar.getInstance(tz, Locale.US).apply {
            timeInMillis = millis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_YEAR, 1)
        }
        return cal.timeInMillis
    }

    fun startOfNextLocalHourMillis(millis: Long, tz: TimeZone = TimeZone.getDefault()): Long {
        val cal = Calendar.getInstance(tz, Locale.US).apply {
            timeInMillis = millis
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.HOUR_OF_DAY, 1)
        }
        return cal.timeInMillis
    }

    fun localYear(millis: Long, tz: TimeZone = TimeZone.getDefault()): Int {
        val cal = Calendar.getInstance(tz, Locale.US).apply { timeInMillis = millis }
        return cal.get(Calendar.YEAR)
    }

    fun formatLocalTimeHHmm(millis: Long, tz: TimeZone = TimeZone.getDefault()): String {
        val cal = Calendar.getInstance(tz, Locale.US).apply { timeInMillis = millis }
        return String.format(
            Locale.US,
            "%02d:%02d",
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE),
        )
    }
}
