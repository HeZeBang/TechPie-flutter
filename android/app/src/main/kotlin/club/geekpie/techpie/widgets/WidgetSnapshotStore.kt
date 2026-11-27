package club.geekpie.techpie.widgets

import android.content.Context
import android.content.SharedPreferences
import java.io.File
import java.util.TimeZone

interface WidgetPreferenceBackend {
    fun getBoolean(key: String): Boolean?
    fun putBoolean(key: String, value: Boolean)
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun remove(key: String)
}

class SharedPreferencesBackend(
    private val prefs: SharedPreferences,
) : WidgetPreferenceBackend {
    override fun getBoolean(key: String): Boolean? =
        if (prefs.contains(key)) prefs.getBoolean(key, false) else null

    override fun putBoolean(key: String, value: Boolean) {
        prefs.edit().putBoolean(key, value).commit()
    }

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).commit()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).commit()
    }
}

/**
 * Pure-JVM atomic text file helper so invalid incoming JSON never corrupts or
 * overwrites the last known valid widget snapshot on disk.
 */
internal class AtomicRawSnapshotFile(
    private val directory: File,
    private val fileName: String,
) {
    private val lock = Any()
    private val target: File get() = File(directory, fileName)

    fun readText(): String? = synchronized(lock) {
        val file = target
        if (!file.isFile) return null
        runCatching { file.readText(Charsets.UTF_8) }.getOrNull()
    }

    fun writeValidated(raw: String, validate: (String) -> Boolean): Boolean = synchronized(lock) {
        if (!validate(raw)) return false
        if (!directory.exists() && !directory.mkdirs()) return false
        val tmp = File(directory, "$fileName.tmp")
        val ok = runCatching {
            tmp.writeText(raw, Charsets.UTF_8)
            if (!tmp.renameTo(target)) {
                target.writeText(raw, Charsets.UTF_8)
                tmp.delete()
            }
            true
        }.getOrElse {
            runCatching { tmp.delete() }
            false
        }
        ok
    }

    fun delete(): Boolean = synchronized(lock) {
        val file = target
        !file.exists() || file.delete()
    }
}

/**
 * Pure-JVM preference coordinator shared by Android widget providers and unit tests:
 * - Clears any local widget mask override whenever the main app changes its own
 *   `hideBalance` setting, while keeping manual eye toggles across balance refreshes.
 * - Auto-resets the Today/Tomorrow toggle when local date changes at midnight.
 */
internal class WidgetPreferenceState(
    private val backend: WidgetPreferenceBackend,
) {
    fun onEcardHideBalanceSynced(appHideBalance: Boolean) {
        val prevSynced = backend.getBoolean(KEY_ECARD_SYNCED_HIDE)
        if (prevSynced != appHideBalance) {
            backend.putBoolean(KEY_ECARD_SYNCED_HIDE, appHideBalance)
            backend.remove(KEY_ECARD_MASK_OVERRIDE)
        }
    }

    fun getEcardMaskOverride(appHideBalance: Boolean? = null): Boolean? {
        val overrideVal = backend.getBoolean(KEY_ECARD_MASK_OVERRIDE) ?: return null
        val storedSynced = backend.getBoolean(KEY_ECARD_SYNCED_HIDE)
        if (appHideBalance != null && storedSynced != appHideBalance) {
            return null
        }
        return overrideVal
    }

    fun toggleEcardMaskOverride(appHideBalance: Boolean): Boolean {
        val currentEffective = getEcardMaskOverride(appHideBalance) ?: appHideBalance
        val next = !currentEffective
        backend.putBoolean(KEY_ECARD_SYNCED_HIDE, appHideBalance)
        backend.putBoolean(KEY_ECARD_MASK_OVERRIDE, next)
        return next
    }

    fun clearEcardOverride() {
        backend.remove(KEY_ECARD_MASK_OVERRIDE)
        backend.remove(KEY_ECARD_SYNCED_HIDE)
    }

    fun getScheduleDayMode(
        nowMillis: Long,
        tz: TimeZone = TimeZone.getDefault(),
    ): ScheduleDayMode {
        val todayKey = WidgetIso8601.formatLocalDayKey(nowMillis, tz)
        if (backend.getString(KEY_SCHEDULE_DAY_DATE) != todayKey) {
            return ScheduleDayMode.AUTO
        }
        return ScheduleDayMode.fromWire(backend.getString(KEY_SCHEDULE_DAY_MODE))
    }

    fun toggleScheduleDayMode(
        currentlyShowingTomorrow: Boolean,
        nowMillis: Long,
        tz: TimeZone = TimeZone.getDefault(),
    ): ScheduleDayMode {
        val next = if (currentlyShowingTomorrow) {
            ScheduleDayMode.TODAY
        } else {
            ScheduleDayMode.TOMORROW
        }
        val todayKey = WidgetIso8601.formatLocalDayKey(nowMillis, tz)
        backend.putString(KEY_SCHEDULE_DAY_MODE, next.wireValue)
        backend.putString(KEY_SCHEDULE_DAY_DATE, todayKey)
        return next
    }

    companion object {
        private const val KEY_ECARD_MASK_OVERRIDE = "ecard_mask_override"
        private const val KEY_ECARD_SYNCED_HIDE = "ecard_synced_hide"
        private const val KEY_SCHEDULE_DAY_MODE = "schedule_day_mode"
        private const val KEY_SCHEDULE_DAY_DATE = "schedule_day_date"
    }
}

class WidgetSnapshotStore(context: Context) {
    private val appContext = context.applicationContext
    private val dir = File(appContext.filesDir, WIDGET_DIR)
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val prefState = WidgetPreferenceState(SharedPreferencesBackend(prefs))

    private val deadlineFile = AtomicRawSnapshotFile(dir, DEADLINE_FILE)
    private val scheduleFile = AtomicRawSnapshotFile(dir, SCHEDULE_FILE)
    private val ecardFile = AtomicRawSnapshotFile(dir, ECARD_FILE)

    fun saveDeadlines(rawJson: String): Boolean =
        deadlineFile.writeValidated(rawJson) { WidgetSnapshotJson.parseDeadlineSnapshot(it) != null }

    fun loadDeadlines(): DeadlineSnapshot? =
        deadlineFile.readText()?.let(WidgetSnapshotJson::parseDeadlineSnapshot)

    fun clearDeadlines() {
        deadlineFile.delete()
    }

    fun saveSchedule(rawJson: String): Boolean =
        scheduleFile.writeValidated(rawJson) { WidgetSnapshotJson.parseScheduleSnapshot(it) != null }

    fun loadSchedule(): ScheduleSnapshot? =
        scheduleFile.readText()?.let(WidgetSnapshotJson::parseScheduleSnapshot)

    fun clearSchedule() {
        scheduleFile.delete()
    }

    fun saveEcard(rawJson: String): Boolean {
        val parsed = WidgetSnapshotJson.parseEcardSnapshot(rawJson) ?: return false
        val wrote = ecardFile.writeValidated(rawJson) { true }
        if (wrote) {
            prefState.onEcardHideBalanceSynced(parsed.hideBalance)
        }
        return wrote
    }

    fun loadEcard(): EcardSnapshot? =
        ecardFile.readText()?.let(WidgetSnapshotJson::parseEcardSnapshot)

    fun clearEcard() {
        ecardFile.delete()
        prefState.clearEcardOverride()
    }

    fun getEcardMaskOverride(): Boolean? =
        prefState.getEcardMaskOverride(loadEcard()?.hideBalance)

    fun toggleEcardMaskOverride(): Boolean {
        val appHide = loadEcard()?.hideBalance ?: false
        return prefState.toggleEcardMaskOverride(appHide)
    }

    fun getScheduleDayMode(
        nowMillis: Long = System.currentTimeMillis(),
        tz: TimeZone = TimeZone.getDefault(),
    ): ScheduleDayMode = prefState.getScheduleDayMode(nowMillis, tz)

    fun toggleScheduleDayMode(
        nowMillis: Long = System.currentTimeMillis(),
        tz: TimeZone = TimeZone.getDefault(),
    ): ScheduleDayMode {
        val currentMode = getScheduleDayMode(nowMillis, tz)
        val resolution = ScheduleWidgetResolver.resolve(loadSchedule(), nowMillis, currentMode, tz)
        val currentlyShowingTomorrow = resolution.effectiveMode == ScheduleDayMode.TOMORROW
        return prefState.toggleScheduleDayMode(currentlyShowingTomorrow, nowMillis, tz)
    }

    companion object {
        private const val WIDGET_DIR = "widgets"
        private const val DEADLINE_FILE = "deadline-widget-v1.json"
        private const val SCHEDULE_FILE = "schedule-widget-v1.json"
        private const val ECARD_FILE = "ecard-widget-v1.json"
        private const val PREFS_NAME = "techpie_widgets_prefs_v1"
    }
}
