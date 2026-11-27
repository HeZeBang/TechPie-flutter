package club.geekpie.techpie.widgets

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.TimeZone

class WidgetSnapshotStoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private class InMemoryPreferenceBackend : WidgetPreferenceBackend {
        private val map = mutableMapOf<String, Any>()
        override fun getBoolean(key: String): Boolean? = map[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { map[key] = value }
        override fun getString(key: String): String? = map[key] as? String
        override fun putString(key: String, value: String) { map[key] = value }
        override fun remove(key: String) { map.remove(key) }
    }

    @Test
    fun atomicFileStorePreservesLastValidPayloadOnInvalidWrite() {
        val dir = tempFolder.newFolder("widgets")
        val file = AtomicRawSnapshotFile(dir, "deadlines.json")

        assertTrue(file.writeValidated("""{"ok":1}""") { it.contains("ok") })
        assertEquals("""{"ok":1}""", file.readText())

        assertFalse(file.writeValidated("""{"broken":true}""") { it.contains("ok") })
        assertEquals("""{"ok":1}""", file.readText())

        assertTrue(file.delete())
        assertNull(file.readText())
    }

    @Test
    fun ecardMaskOverrideSurvivesBalanceRefreshAndResetsWhenAppChangesSetting() {
        val prefs = WidgetPreferenceState(InMemoryPreferenceBackend())

        // Initial app state: show balance
        prefs.onEcardHideBalanceSynced(appHideBalance = false)
        assertNull(prefs.getEcardMaskOverride(appHideBalance = false))

        // User toggles eye button on widget -> masked locally
        assertTrue(prefs.toggleEcardMaskOverride(appHideBalance = false))
        assertEquals(true, prefs.getEcardMaskOverride(appHideBalance = false))

        // App publishes new balance with same hideBalance=false -> keep override
        prefs.onEcardHideBalanceSynced(appHideBalance = false)
        assertEquals(true, prefs.getEcardMaskOverride(appHideBalance = false))

        // App changes hideCampusCardBalance setting to true -> clear widget override
        prefs.onEcardHideBalanceSynced(appHideBalance = true)
        assertNull(prefs.getEcardMaskOverride(appHideBalance = true))
    }

    @Test
    fun scheduleDayModeResetsToAutoAfterMidnight() {
        val shanghai = TimeZone.getTimeZone("Asia/Shanghai")
        val prefs = WidgetPreferenceState(InMemoryPreferenceBackend())
        val afternoon = WidgetIso8601.parseUtcIsoMillis("2026-11-27T06:00:00Z")!! // 14:00 CST
        val nextMorning = WidgetIso8601.parseUtcIsoMillis("2026-11-27T17:00:00Z")!! // 01:00 CST next day

        assertEquals(ScheduleDayMode.AUTO, prefs.getScheduleDayMode(afternoon, shanghai))
        assertEquals(
            ScheduleDayMode.TOMORROW,
            prefs.toggleScheduleDayMode(currentlyShowingTomorrow = false, nowMillis = afternoon, tz = shanghai),
        )
        assertEquals(ScheduleDayMode.TOMORROW, prefs.getScheduleDayMode(afternoon, shanghai))
        assertEquals(ScheduleDayMode.AUTO, prefs.getScheduleDayMode(nextMorning, shanghai))
    }
}
