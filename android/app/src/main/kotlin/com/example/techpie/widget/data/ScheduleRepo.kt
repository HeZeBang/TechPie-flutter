package com.example.techpie.widget.data

import android.content.Context
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** A single class block to display in a widget. */
data class DisplayCourse(
    val name: String,
    val classroom: String,
    val teachers: String,
    val startPeriod: Int,
    val endPeriod: Int,
    val startTime: String,  // "HH:mm" or empty
    val endTime: String,
    /** 0..6 — index into a fixed palette so widget chooses a consistent hue. */
    val colorIndex: Int,
)

data class TodaySchedule(
    val courses: List<DisplayCourse>,
    val dateLabel: String,        // "2026-05-08 周五"
    val semesterLabel: String?,   // "2024-2025 春学期"  (or null)
    val currentWeek: Int,         // 1..25, or 0 if termBegin unknown
)

object ScheduleRepo {

    private val WEEKDAY_CN = arrayOf("一", "二", "三", "四", "五", "六", "日")

    fun loadToday(context: Context): TodaySchedule {
        val prefs = FlutterPrefs.open(context)

        val semesters = FlutterPrefs.string(prefs, "schedule_semesters")
            ?.let { runCatching { widgetJson.parseToJsonElement(it).jsonObject }.getOrNull() }
            ?.let { SemesterInfo.fromJson(it) }

        val selectedId = FlutterPrefs.string(prefs, "schedule_selected_semester")
            ?: semesters?.defaultSemester
            ?: ""

        val tableJson = if (selectedId.isNotEmpty())
            FlutterPrefs.string(prefs, "schedule_course_table_$selectedId")
        else null

        val table: CourseTable? = tableJson
            ?.let { runCatching { widgetJson.parseToJsonElement(it).jsonObject }.getOrNull() }
            ?.let { CourseTable.fromJson(it) }

        val termBegin = FlutterPrefs.string(prefs, "schedule_term_begin_$selectedId")
            ?.let { parseIsoLocalDate(it) }

        val today = LocalDate.now()
        // java.time DayOfWeek already uses 1=Monday..7=Sunday — same as Dart.
        val todayDow = today.dayOfWeek.value

        val week = currentWeek(termBegin, today)

        val periodsByIndex: Map<Int, CoursePeriod> =
            table?.periods?.associateBy { it.index } ?: emptyMap()

        val courses = mutableListOf<DisplayCourse>()
        if (table != null) {
            table.courses.forEachIndexed { courseIdx, eams ->
                val active = week == 0 || eams.isActiveInWeek(week)
                if (!active) return@forEachIndexed
                val periods = eams.times[todayDow] ?: return@forEachIndexed
                if (periods.isEmpty()) return@forEachIndexed

                // Group consecutive periods into one block (matches Dart eamsToDisplayCourses).
                var start = periods.first()
                var end = start
                for (i in 1 until periods.size) {
                    if (periods[i] == end + 1) {
                        end = periods[i]
                    } else {
                        courses += build(eams, courseIdx, start, end, periodsByIndex)
                        start = periods[i]; end = periods[i]
                    }
                }
                courses += build(eams, courseIdx, start, end, periodsByIndex)
            }
        }
        courses.sortBy { it.startPeriod }

        val dateLabel = "%04d-%02d-%02d 周%s".format(
            today.year, today.monthValue, today.dayOfMonth,
            WEEKDAY_CN[todayDow - 1],
        )

        return TodaySchedule(
            courses = courses,
            dateLabel = dateLabel,
            semesterLabel = semesters?.findLabel(selectedId),
            currentWeek = week,
        )
    }

    private fun build(
        eams: EamsCourse,
        courseIdx: Int,
        start: Int,
        end: Int,
        periodsByIndex: Map<Int, CoursePeriod>,
    ): DisplayCourse = DisplayCourse(
        name = eams.name,
        classroom = eams.classroom,
        teachers = eams.teachers,
        startPeriod = start,
        endPeriod = end,
        startTime = periodsByIndex[start]?.startTime.orEmpty(),
        endTime = periodsByIndex[end]?.endTime.orEmpty(),
        colorIndex = courseIdx % 7,
    )

    /** Mirrors ScheduleService.currentWeek. Returns 0 when termBegin missing. */
    private fun currentWeek(termBegin: LocalDate?, today: LocalDate): Int {
        if (termBegin == null) return 0
        val days = ChronoUnit.DAYS.between(termBegin, today)
        if (days < 0) return 1
        return ((days / 7) + 1).coerceIn(1, 25).toInt()
    }

    /**
     * Dart writes term begin as `DateTime.toIso8601String()`, which may be
     * `2024-09-02T00:00:00.000` (no zone) or `…Z` (UTC). Either way we just
     * need the date portion.
     */
    private fun parseIsoLocalDate(s: String): LocalDate? {
        return runCatching {
            // Try as offset/zoned first.
            OffsetDateTime.parse(s).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
        }.recoverCatching {
            LocalDate.parse(s.substringBefore('T'))
        }.getOrNull()
    }
}
