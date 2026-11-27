package club.geekpie.techpie.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class WidgetIso8601Test {
    @Test
    fun parsesUtcIsoAndFractionalSecondsAndRejectsInvalidDates() {
        val t1 = WidgetIso8601.parseUtcIsoMillis("2026-11-27T08:15:00Z")
        val t2 = WidgetIso8601.parseUtcIsoMillis("2026-11-27T08:15:00.250Z")
        val t3 = WidgetIso8601.parseUtcIsoMillis("2026-11-27T16:15:00+08:00")
        assertNotNull(t1)
        assertNotNull(t2)
        assertEquals(t1!! + 250L, t2!!)
        assertEquals(t1, t3!!)

        assertNull(WidgetIso8601.parseUtcIsoMillis("2026-02-30T10:00:00Z"))
        assertNull(WidgetIso8601.parseUtcIsoMillis("2026-13-01T10:00:00Z"))
        assertNull(WidgetIso8601.parseUtcIsoMillis("not-a-timestamp"))
    }

    @Test
    fun formatsLocalDayKeyAndNextDayAcrossTimezoneBoundaries() {
        val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
        // 2026-11-27 16:30:00Z == 2026-11-28 00:30:00+08:00
        val utcMillis = WidgetIso8601.parseUtcIsoMillis("2026-11-27T16:30:00Z")!!
        assertEquals("2026-11-28", WidgetIso8601.formatLocalDayKey(utcMillis, shanghai))
        assertEquals("2026-11-29", WidgetIso8601.addDaysToLocalDayKey(utcMillis, 1, shanghai))

        val nextMidnight = WidgetIso8601.startOfNextLocalDayMillis(utcMillis, shanghai)
        assertEquals("2026-11-29", WidgetIso8601.formatLocalDayKey(nextMidnight, shanghai))
        assertTrue(nextMidnight > utcMillis)
        assertEquals("00:30", WidgetIso8601.formatLocalTimeHHmm(utcMillis, shanghai))
    }
}
