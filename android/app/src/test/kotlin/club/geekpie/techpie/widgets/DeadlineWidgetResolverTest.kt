package club.geekpie.techpie.widgets

import club.geekpie.techpie.widgets.DeadlineWidgetResolver.CountdownToken
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale
import java.util.TimeZone

class DeadlineWidgetResolverTest {
    private val now = WidgetIso8601.parseUtcIsoMillis("2026-11-27T08:00:00Z")!!
    private val hour = DeadlineWidgetResolver.HOUR_MILLIS

    @Test
    fun filtersExpiredAndSortsDeterministicallyByDueThenId() {
        val snapshot = DeadlineSnapshot(
            schemaVersion = 1,
            writtenAtMillis = now,
            items = listOf(
                DeadlineItem("expired", DeadlineKind.ASSIGNMENT, "Old", "CS", now - 1000L),
                DeadlineItem("b", DeadlineKind.EXAM, "Exam B", "Room 1", now + 5 * hour),
                DeadlineItem("a", DeadlineKind.ASSIGNMENT, "HW A", "Math", now + 5 * hour),
                DeadlineItem("c", DeadlineKind.ASSIGNMENT, "HW C", "Bio", now + 2 * hour),
            ),
        )
        val active = DeadlineWidgetResolver.activeItems(snapshot, now)
        assertEquals(listOf("c", "a", "b"), active.map { it.id })
    }

    @Test
    fun urgencyAndCountdownTokensMatchThresholdBoundaries() {
        assertEquals(DeadlineUrgency.URGENT, DeadlineWidgetResolver.urgency(now + 24 * hour, now))
        assertEquals(DeadlineUrgency.SOON, DeadlineWidgetResolver.urgency(now + 24 * hour + 1, now))
        assertEquals(DeadlineUrgency.SOON, DeadlineWidgetResolver.urgency(now + 72 * hour, now))
        assertEquals(DeadlineUrgency.NORMAL, DeadlineWidgetResolver.urgency(now + 72 * hour + 1, now))

        assertEquals(CountdownToken.DueSoon, DeadlineWidgetResolver.countdownToken(now + 45 * 60_000L, now))
        assertEquals(CountdownToken.Hours(5), DeadlineWidgetResolver.countdownToken(now + 5 * hour + 1800_000L, now))
        assertEquals(CountdownToken.DaysHours(1, 6), DeadlineWidgetResolver.countdownToken(now + 30 * hour, now))
        assertEquals(CountdownToken.Days(3), DeadlineWidgetResolver.countdownToken(now + 80 * hour, now))
    }

    @Test
    fun includesYearInFormattedDateAcrossYearBoundary() {
        val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
        val sameYear = WidgetIso8601.parseUtcIsoMillis("2026-12-01T12:00:00Z")!!
        val nextYear = WidgetIso8601.parseUtcIsoMillis("2027-01-05T12:00:00Z")!!

        val sameText = DeadlineWidgetResolver.formatAbsoluteDate(sameYear, now, shanghai, Locale.US)
        val nextText = DeadlineWidgetResolver.formatAbsoluteDate(nextYear, now, shanghai, Locale.US)
        assertFalse(sameText.contains("2026"))
        assertTrue(nextText.contains("2027"))
    }
}
