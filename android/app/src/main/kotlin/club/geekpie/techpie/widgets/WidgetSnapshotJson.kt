package club.geekpie.techpie.widgets

import org.json.JSONArray
import org.json.JSONObject

object WidgetSnapshotJson {
    private const val MAX_YEAR_2500_MILLIS = 16725225600_000L

    fun parseDeadlineSnapshot(raw: String): DeadlineSnapshot? {
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        if (obj.optInt("schemaVersion", -1) != 1) return null
        val writtenSec = obj.optDouble("writtenAt", Double.NaN)
        if (writtenSec.isNaN() || writtenSec < 0) return null
        val itemsArray = obj.optJSONArray("items") ?: return null

        val seen = HashSet<String>(itemsArray.length())
        val items = ArrayList<DeadlineItem>(itemsArray.length())
        for (i in 0 until itemsArray.length()) {
            val row = itemsArray.optJSONObject(i) ?: return null
            val id = row.optStringSafe("id")
            val title = row.optStringSafe("title")
            val dueSec = row.optDouble("dueAt", Double.NaN)
            if (id.isEmpty() || title.isEmpty() || dueSec.isNaN() || dueSec < 0) return null
            if (!seen.add(id)) return null
            val dueMillis = (dueSec * 1000.0).toLong()
            if (dueMillis > MAX_YEAR_2500_MILLIS) return null
            items.add(
                DeadlineItem(
                    id = id,
                    kind = DeadlineKind.fromRaw(row.optStringSafe("kind").ifEmpty { "assignment" }),
                    title = title,
                    subtitle = row.optStringSafe("subtitle"),
                    dueAtMillis = dueMillis,
                ),
            )
        }
        return DeadlineSnapshot(
            schemaVersion = 1,
            writtenAtMillis = (writtenSec * 1000.0).toLong(),
            items = items,
        )
    }

    fun parseScheduleSnapshot(raw: String): ScheduleSnapshot? {
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        if (obj.optInt("schemaVersion", -1) != 1) return null
        val generatedAtMillis =
            WidgetIso8601.parseUtcIsoMillis(obj.optString("generatedAt", "")) ?: return null
        val daysArray = obj.optJSONArray("days") ?: return null

        val seenDates = HashSet<String>(daysArray.length())
        val days = ArrayList<ScheduleDay>(daysArray.length())
        for (i in 0 until daysArray.length()) {
            val dayObj = daysArray.optJSONObject(i) ?: return null
            val date = dayObj.optStringSafe("date")
            if (date.isEmpty() || !seenDates.add(date)) return null
            val weekday = dayObj.optInt("weekday", 0)
            if (weekday !in 1..7) return null
            val weekNum = dayObj.optIntOrNull("weekNumber")
            val coursesArray = dayObj.optJSONArray("courses") ?: JSONArray()
            val seenCourseIds = HashSet<String>(coursesArray.length())
            val courses = ArrayList<ScheduleCourse>(coursesArray.length())
            for (j in 0 until coursesArray.length()) {
                val c = coursesArray.optJSONObject(j) ?: return null
                val id = c.optStringSafe("id")
                val title = c.optStringSafe("title")
                val startAt = WidgetIso8601.parseUtcIsoMillis(c.optStringSafe("startAt")) ?: return null
                val endAt = WidgetIso8601.parseUtcIsoMillis(c.optStringSafe("endAt")) ?: return null
                if (id.isEmpty() || title.isEmpty() || endAt <= startAt) return null
                if (!seenCourseIds.add(id)) return null
                courses.add(
                    ScheduleCourse(
                        id = id,
                        title = title,
                        location = c.optStringSafe("location"),
                        teacher = c.optStringSafe("teacher"),
                        startAtMillis = startAt,
                        endAtMillis = endAt,
                        startPeriod = c.optIntOrNull("startPeriod"),
                        endPeriod = c.optIntOrNull("endPeriod"),
                        periodLabel = c.optStringOrNull("periodLabel"),
                        isExam = c.optBoolean("isExam", false),
                        colorLightHex = c.optStringOrNull("colorLightHex"),
                        colorDarkHex = c.optStringOrNull("colorDarkHex"),
                    ),
                )
            }
            days.add(ScheduleDay(date = date, weekday = weekday, weekNumber = weekNum, courses = courses))
        }
        return ScheduleSnapshot(
            schemaVersion = 1,
            generatedAtMillis = generatedAtMillis,
            weekNumber = obj.optIntOrNull("weekNumber"),
            days = days,
        )
    }

    fun parseEcardSnapshot(raw: String): EcardSnapshot? {
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return null
        if (obj.optInt("schemaVersion", -1) != 1) return null
        val generatedAtMillis =
            WidgetIso8601.parseUtcIsoMillis(obj.optString("generatedAt", "")) ?: return null
        return EcardSnapshot(
            schemaVersion = 1,
            generatedAtMillis = generatedAtMillis,
            configured = obj.optBoolean("configured", false),
            balanceText = obj.optStringOrNull("balanceText"),
            hideBalance = obj.optBoolean("hideBalance", false),
        )
    }

    private fun JSONObject.optIntOrNull(key: String): Int? =
        if (!has(key) || isNull(key)) null else optInt(key)

    private fun JSONObject.optStringSafe(key: String): String =
        if (!has(key) || isNull(key)) "" else optString(key, "").trim()

    private fun JSONObject.optStringOrNull(key: String): String? =
        optStringSafe(key).takeIf { it.isNotEmpty() }
}
