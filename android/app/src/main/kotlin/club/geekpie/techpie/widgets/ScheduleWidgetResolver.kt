package club.geekpie.techpie.widgets

import java.util.TimeZone

data class ResolvedScheduleCourse(
    val course: ScheduleCourse,
    val isInProgress: Boolean,
    val progressPercent: Int,
)

data class ScheduleResolution(
    val hasSnapshot: Boolean,
    val effectiveMode: ScheduleDayMode,
    val selectedMode: ScheduleDayMode,
    val isRolledOver: Boolean,
    val displayDay: ScheduleDay?,
    val inProgressCourse: ResolvedScheduleCourse?,
    val upcomingCourses: List<ScheduleCourse>,
    val allDisplayCourses: List<ScheduleCourse>,
    val weekNumber: Int?,
)

object ScheduleWidgetResolver {
    private const val PROGRESS_REFRESH_MILLIS: Long = 5L * 60_000L
    private const val FALLBACK_REFRESH_MILLIS: Long = 6L * 3_600_000L

    fun resolve(
        snapshot: ScheduleSnapshot?,
        nowMillis: Long,
        mode: ScheduleDayMode = ScheduleDayMode.AUTO,
        tz: TimeZone = TimeZone.getDefault(),
    ): ScheduleResolution {
        if (snapshot == null) {
            return ScheduleResolution(
                hasSnapshot = false,
                effectiveMode = mode,
                selectedMode = mode,
                isRolledOver = false,
                displayDay = null,
                inProgressCourse = null,
                upcomingCourses = emptyList(),
                allDisplayCourses = emptyList(),
                weekNumber = null,
            )
        }

        val todayKey = WidgetIso8601.formatLocalDayKey(nowMillis, tz)
        val tomorrowKey = WidgetIso8601.addDaysToLocalDayKey(nowMillis, 1, tz)
        val sortedDays = snapshot.days.sortedBy { it.date }
        val todayDay = sortedDays.firstOrNull { it.date == todayKey }
        val tomorrowDay = sortedDays.firstOrNull { it.date == tomorrowKey }

        if (mode == ScheduleDayMode.TOMORROW) {
            val courses = tomorrowDay?.courses?.sortedBy { it.startAtMillis }.orEmpty()
            return ScheduleResolution(
                hasSnapshot = true,
                effectiveMode = ScheduleDayMode.TOMORROW,
                selectedMode = mode,
                isRolledOver = false,
                displayDay = tomorrowDay,
                inProgressCourse = null,
                upcomingCourses = courses,
                allDisplayCourses = courses,
                weekNumber = tomorrowDay?.weekNumber ?: snapshot.weekNumber,
            )
        }

        val todayCourses = todayDay?.courses?.sortedBy { it.startAtMillis }.orEmpty()
        val activeToday = todayCourses.firstOrNull { it.startAtMillis <= nowMillis && it.endAtMillis > nowMillis }
        val futureToday = todayCourses.filter { it.startAtMillis > nowMillis }

        if (mode == ScheduleDayMode.TODAY) {
            val resolvedActive = activeToday?.let { toResolvedCourse(it, nowMillis) }
            val displayList = listOfNotNull(resolvedActive?.course) + futureToday
            return ScheduleResolution(
                hasSnapshot = true,
                effectiveMode = ScheduleDayMode.TODAY,
                selectedMode = mode,
                isRolledOver = false,
                displayDay = todayDay,
                inProgressCourse = resolvedActive,
                upcomingCourses = futureToday,
                allDisplayCourses = displayList,
                weekNumber = todayDay?.weekNumber ?: snapshot.weekNumber,
            )
        }

        // AUTO mode: active/future classes today; otherwise roll over to next teaching day in window.
        if (activeToday != null || futureToday.isNotEmpty()) {
            val resolvedActive = activeToday?.let { toResolvedCourse(it, nowMillis) }
            val displayList = listOfNotNull(resolvedActive?.course) + futureToday
            return ScheduleResolution(
                hasSnapshot = true,
                effectiveMode = ScheduleDayMode.TODAY,
                selectedMode = mode,
                isRolledOver = false,
                displayDay = todayDay,
                inProgressCourse = resolvedActive,
                upcomingCourses = futureToday,
                allDisplayCourses = displayList,
                weekNumber = todayDay?.weekNumber ?: snapshot.weekNumber,
            )
        }

        val nextTeachingDay = sortedDays.firstOrNull { it.date > todayKey && it.courses.isNotEmpty() }
        if (nextTeachingDay != null) {
            val courses = nextTeachingDay.courses.sortedBy { it.startAtMillis }
            return ScheduleResolution(
                hasSnapshot = true,
                effectiveMode = ScheduleDayMode.TOMORROW,
                selectedMode = mode,
                isRolledOver = true,
                displayDay = nextTeachingDay,
                inProgressCourse = null,
                upcomingCourses = courses,
                allDisplayCourses = courses,
                weekNumber = nextTeachingDay.weekNumber ?: snapshot.weekNumber,
            )
        }

        return ScheduleResolution(
            hasSnapshot = true,
            effectiveMode = ScheduleDayMode.TODAY,
            selectedMode = mode,
            isRolledOver = false,
            displayDay = todayDay,
            inProgressCourse = null,
            upcomingCourses = emptyList(),
            allDisplayCourses = emptyList(),
            weekNumber = todayDay?.weekNumber ?: snapshot.weekNumber,
        )
    }

    fun progressPercent(startAtMillis: Long, endAtMillis: Long, nowMillis: Long): Int {
        val duration = endAtMillis - startAtMillis
        if (duration <= 0L) return 0
        val elapsed = nowMillis - startAtMillis
        return ((elapsed.toDouble() / duration.toDouble()).coerceIn(0.0, 1.0) * 100.0).toInt()
    }

    fun nextRefreshMillis(
        snapshot: ScheduleSnapshot?,
        nowMillis: Long,
        mode: ScheduleDayMode = ScheduleDayMode.AUTO,
        tz: TimeZone = TimeZone.getDefault(),
    ): Long {
        val candidates = mutableListOf<Long>()
        candidates.add(WidgetIso8601.startOfNextLocalDayMillis(nowMillis, tz))
        candidates.add(nowMillis + FALLBACK_REFRESH_MILLIS)

        if (snapshot != null) {
            val todayKey = WidgetIso8601.formatLocalDayKey(nowMillis, tz)
            for (day in snapshot.days) {
                if (day.date < todayKey) continue
                for (course in day.courses) {
                    if (course.startAtMillis > nowMillis) candidates.add(course.startAtMillis)
                    if (course.endAtMillis > nowMillis) candidates.add(course.endAtMillis)
                    if (course.startAtMillis <= nowMillis && course.endAtMillis > nowMillis) {
                        candidates.add(minOf(course.endAtMillis, nowMillis + PROGRESS_REFRESH_MILLIS))
                    }
                }
            }
            val resolution = resolve(snapshot, nowMillis, mode, tz)
            if (resolution.inProgressCourse != null) {
                candidates.add(
                    minOf(
                        resolution.inProgressCourse.course.endAtMillis,
                        nowMillis + PROGRESS_REFRESH_MILLIS,
                    ),
                )
            }
        }
        return candidates.filter { it > nowMillis }.minOrNull() ?: (nowMillis + FALLBACK_REFRESH_MILLIS)
    }

    private fun toResolvedCourse(course: ScheduleCourse, nowMillis: Long): ResolvedScheduleCourse =
        ResolvedScheduleCourse(
            course = course,
            isInProgress = true,
            progressPercent = progressPercent(course.startAtMillis, course.endAtMillis, nowMillis),
        )
}
