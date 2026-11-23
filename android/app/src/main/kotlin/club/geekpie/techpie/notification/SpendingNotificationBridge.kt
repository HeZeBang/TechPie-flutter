package club.geekpie.techpie.notification

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import club.geekpie.techpie.MainActivity
import club.geekpie.techpie.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** One synchronized native ledger for all Flutter engines in the app process. */
internal object SpendingNotificationState {
    private const val PREFS = "techpie_spending_alerts_v1"
    private const val TAG = "techpie.spending"
    private const val CHANNEL = "spending_alerts"
    private const val MAX_NOTIFICATIONS = 3
    private val lock = Any()
    private val opaqueKey = Regex("^[0-9a-f]{64}$")

    private fun read(context: Context): SpendingLedger {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val seen = mutableMapOf<String, Long>()
        runCatching {
            val json = JSONObject(prefs.getString("seen", "{}") ?: "{}")
            for (key in json.keys()) {
                if (opaqueKey.matches(key) && seen.size < SpendingLedger.LIMIT) seen[key] = json.getLong(key)
            }
        }
        return SpendingLedger(
            owner = prefs.getString("owner", null), generation = prefs.getLong("generation", 0),
            initialized = prefs.getBoolean("initialized", false), floor = prefs.getLong("floor", Long.MIN_VALUE),
            seen = seen,
        )
    }

    private fun save(context: Context, state: SpendingLedger): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("owner", state.owner).putLong("generation", state.generation)
            .putBoolean("initialized", state.initialized).putLong("floor", state.floor)
            .putString("seen", JSONObject(state.seen).toString()).commit()

    fun status(context: Context): Map<String, Any?> = synchronized(lock) {
        val state = read(context)
        mapOf("owner" to state.owner, "generation" to state.generation)
    }

    fun configure(context: Context, owner: String?): Boolean = synchronized(lock) {
        require(owner == null || opaqueKey.matches(owner)) { "Invalid notification scope" }
        val before = read(context)
        val next = before.configure(owner)
        if (before != next) {
            if (!save(context, next)) return@synchronized false
            SpendingRefreshScheduler.cancel(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.tag == TAG }.forEach { manager.cancel(TAG, it.id) }
        }
        updateSchedule(context, next)
        true
    }

    fun refreshSchedule(context: Context) = synchronized(lock) { updateSchedule(context, read(context)) }

    private fun updateSchedule(context: Context, state: SpendingLedger) {
        if (state.owner != null && NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            SpendingRefreshScheduler.schedule(context)
        } else {
            SpendingRefreshScheduler.cancel(context)
        }
    }

    fun observe(context: Context, owner: String, generation: Long, records: List<SpendingRecord>): Boolean = synchronized(lock) {
        val before = read(context)
        val update = before.observe(owner, generation, records, System.currentTimeMillis())
            ?: return@synchronized false
        // Persist before notifying: a concurrent engine cannot announce the same batch.
        if (!save(context, update.ledger)) return@synchronized false
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return@synchronized true
        ensureChannel(context)
        val shown = update.receipts.take(MAX_NOTIFICATIONS)
        val folded = update.receipts.size - shown.size
        shown.forEachIndexed { index, record ->
            val id = (owner + record.key).hashCode()
            val open = PendingIntent.getActivity(context, id,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val tail = if (index == shown.lastIndex && folded > 0) " · 另有 $folded 笔" else ""
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_spending_notification)
                .setContentTitle(record.title).setContentText(record.body + tail)
                .setStyle(NotificationCompat.BigTextStyle().bigText(record.body + tail))
                .setContentIntent(open).setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setGroup(TAG).setSilent(index > 0).build()
            try { NotificationManagerCompat.from(context).notify(TAG, id, notification) }
            catch (_: SecurityException) { /* Permission can be revoked between the check and post. */ }
        }
        true
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.spending_channel_name),
                NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = context.getString(R.string.spending_channel_desc)
                setShowBadge(false)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
            })
    }
}

class SpendingNotificationBridge(context: Context, messenger: BinaryMessenger,
                                 private val activity: Activity? = null) {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, "techpie/spending_alerts")
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> result.success(SpendingNotificationState.configure(appContext, call.argument<String>("owner")))
                    "status" -> result.success(SpendingNotificationState.status(appContext))
                    "observe" -> result.success(observe(call))
                    "requestPermission" -> result.success(requestPermission())
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("SPENDING_NOTIFICATION_FAILED", "通知暂不可用", null)
            }
        }
    }

    private fun observe(call: MethodCall): Boolean {
        val owner = call.argument<String>("owner") ?: return false
        val generation = call.argument<Number>("generation")?.toLong() ?: return false
        val raw = call.argument<List<Map<String, Any?>>>("records") ?: return false
        val records = raw.take(50).mapNotNull { item ->
            val key = (item["key"] as? String)?.takeIf { Regex("^[0-9a-f]{64}$").matches(it) } ?: return@mapNotNull null
            val at = (item["at"] as? Number)?.toLong() ?: return@mapNotNull null
            SpendingRecord(key, at, item["spending"] == true,
                (item["title"] as? String).orEmpty().take(80), (item["body"] as? String).orEmpty().take(500))
        }
        return SpendingNotificationState.observe(appContext, owner, generation, records)
    }

    private fun requestPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (!granted && activity != null) ActivityCompat.requestPermissions(activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS), 48293)
        return granted
    }

    fun refreshSchedule() = SpendingNotificationState.refreshSchedule(appContext)

    fun dispose() = channel.setMethodCallHandler(null)
}
