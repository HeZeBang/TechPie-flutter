package club.geekpie.techpie.island

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationManagerCompat
import com.xzakota.hyper.notification.focus.util.FocusUtils

/**
 * Reads what this device can show the island as and resolves the active tier.
 *
 * The focus-permission check is a ContentProvider round trip, so it is cached;
 * [refresh] drops the cache after the user returns from system settings.
 */
class IslandCapabilityProbe(context: Context) {
    private val appContext = context.applicationContext
    private val manager = appContext.getSystemService(NotificationManager::class.java)

    data class Snapshot(
        /** The tier that will actually be used. */
        val backend: IslandBackend,
        val postNotifications: Boolean,
        val liveUpdateAvailable: Boolean,
        val liveUpdateGranted: Boolean,
        val islandLikely: Boolean,
        val islandGranted: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "backend" to backend.name.lowercase(),
            "postNotifications" to postNotifications,
            "liveUpdateAvailable" to liveUpdateAvailable,
            "liveUpdateGranted" to liveUpdateGranted,
            "islandLikely" to islandLikely,
            "islandGranted" to islandGranted,
        )
    }

    // Protocol version and the island feature flag are read-only system state.
    private val islandLikely: Boolean by lazy {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 && runCatching {
            FocusUtils.getFocusProtocolVersion(appContext) >= 3 || FocusUtils.isSupportIsland()
        }.getOrDefault(false)
    }

    @Volatile
    private var islandGrantCache: Pair<Long, Boolean>? = null

    fun snapshot(): Snapshot {
        val likely = islandLikely
        val granted = likely && islandGranted()
        return Snapshot(
            backend = IslandBackends.resolve(granted, liveUpdateGranted()),
            postNotifications = NotificationManagerCompat.from(appContext).areNotificationsEnabled(),
            liveUpdateAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA,
            liveUpdateGranted = liveUpdateGranted(),
            islandLikely = likely,
            islandGranted = granted,
        )
    }

    /** Drop the focus-permission cache (user may have just toggled it in settings). */
    fun refresh(): Snapshot {
        islandGrantCache = null
        return snapshot()
    }

    private fun islandGranted(): Boolean {
        val now = SystemClock.elapsedRealtime()
        islandGrantCache?.let { (at, value) -> if (now - at < ISLAND_GRANT_CACHE_MS) return value }
        val granted = runCatching { FocusUtils.hasFocusPermission(appContext) }.getOrDefault(false)
        islandGrantCache = now to granted
        return granted
    }

    private fun liveUpdateGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) return false
        // One UI does not expose the system switch; the query is always false
        // there but requests still work.
        if (Build.MANUFACTURER.equals("samsung", ignoreCase = true)) return true
        return runCatching { manager.canPostPromotedNotifications() }.getOrDefault(false)
    }

    private companion object {
        const val ISLAND_GRANT_CACHE_MS = 30_000L
    }
}
