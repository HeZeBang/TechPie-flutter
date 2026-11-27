package club.geekpie.techpie.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class ScheduleWidgetResolverTest {
    private val shanghai: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")

    private fun course(
        id: String,
        title: String,
        startIso: String,
        endIso: String,
        location: String = "SIST 1A-204",
    ) = ScheduleCourse(
        id = id,
        title = title,
        location = location,
        teacher = "Prof. Li",
        startAtMillis = WidgetIso8601.parseUtcIsoMillis(startIso)!!,
        endAtMillis = WidgetIso8601.parseUtcIsoMillis(endIso)!!,
        startPeriod = 1,
        endPeriod = 2,
        periodLabel = "1-2",
        colorLightHex = "#217AD0",
        colorDarkHex = "#5BA5F6",
    )

    private fun sampleSnapshot(): ScheduleSnapshot {
        val dayToday = ScheduleDay(
            date = "2026-11-27",
            weekday = 5,
            weekNumber = 12,
            courses = listOf(
                course("c1", "Linear Algebra", "2026-11-27T00:15:00Z", "2026-11-27T01:55:00Z"),
                course("c2", "Operating Systems", "2026-11-27T06:00:00Z", "2026-11-27T07:40:00Z"),
            ),
        )
        val dayNextTeaching = ScheduleDay(
            date = "2026-11-30",
            weekday = 1,
            weekNumber = 13,
            courses = listOf(
                course("c3", "Compilers", "2026-11-30T02:00:00Z", "2026-11-30T03:40:00Z"),
            ),
        )
        return ScheduleSnapshot(
            schemaVersion = 1,
            generatedAtMillis = WidgetIso8601.parseUtcIsoMillis("2026-11-27T00:00:00Z")!!,
            weekNumber = 12,
            days = listOf(dayToday, dayNextTeaching),
        )
    }

    @Test
    fun detectsInProgressCourseAndComputesProgressPercent() {
        // 09:05 CST == 01:05Z -> 50 min into a 100 min class (50%)
        val now = WidgetIso8601.parseUtcIsoMillis("2026-11-27T01:05:00Z")!!
        val res = ScheduleWidgetResolver.resolve(sampleSnapshot(), now, ScheduleDayMode.AUTO, shanghai)

        assertTrue(res.hasSnapshot)
        assertEquals(ScheduleDayMode.TODAY, res.effectiveMode)
        assertFalse(res.isRolledOver)
        assertNotNull(res.inProgressCourse)
        assertEquals("Linear Algebra", res.inProgressCourse!!.course.title)
        assertEquals(50, res.inProgressCourse!!.progressPercent)
        assertEquals(listOf("Operating Systems"), res.upcomingCourses.map { it.title })
        assertEquals(12, res.weekNumber)
    }

    @Test
    fun rollsOverToNextTeachingDayWhenTodayClassesHaveEnded() {
        // 20:00 CST == 12:00Z after both courses on 2026-11-27 ended
        val now = WidgetIso8601.parseUtcIsoMillis("2026-11-27T12:00:00Z")!!
        val res = ScheduleWidgetResolver.resolve(sampleSnapshot(), now, ScheduleDayMode.AUTO, shanghai)

        assertTrue(res.isRolledOver)
        assertEquals(ScheduleDayMode.TOMORROW, res.effectiveMode)
        assertEquals("2026-11-30", res.displayDay?.date)
        assertEquals(listOf("Compilers"), res.allDisplayCourses.map { it.title })
        assertEquals(13, res.weekNumber)
    }

    @Test
    fun explicitTodayAndTomorrowModesRespectUserSelection() {
        val now = WidgetIso8601.parseUtcIsoMillis("2026-11-27T12:00:00Z")!!
        val todayExplicit = ScheduleWidgetResolver.resolve(sampleSnapshot(), now, ScheduleDayMode.TODAY, shanghai)
        assertFalse(todayExplicit.isRolledOver)
        assertTrue(todayExplicit.allDisplayCourses.isEmpty())

        val tomorrowExplicit = ScheduleWidgetResolver.resolve(sampleSnapshot(), now, ScheduleDayMode.TOMORROW, shanghai)
        assertFalse(tomorrowExplicit.isRolledOver)
        assertEquals(ScheduleDayMode.TOMORROW, tomorrowExplicit.effectiveMode)
        assertNull(tomorrowExplicit.displayDay)
        assertTrue(tomorrowExplicit.allDisplayCourses.isEmpty())
    }

    @Test
    fun schedulesNextRefreshAtClassBoundaryOrProgressInterval() {
        val now = WidgetIso8601.parseUtcIsoMillis("2026-11-27T01:05:00Z")!!
        val next = ScheduleWidgetResolver.nextRefreshMillis(sampleSnapshot(), now, ScheduleDayMode.AUTO, shanghai)
        assertEquals(now + 5L * 60_000L, next)
    }
}
