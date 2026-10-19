package club.geekpie.techpie.wear

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.huawei.hmf.tasks.Tasks
import com.huawei.wearengine.HiWear
import com.huawei.wearengine.auth.Permission
import com.huawei.wearengine.notify.Notification
import com.huawei.wearengine.notify.NotificationTemplate
import org.json.JSONObject
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/** WorkManager reminders survive Flutter shutdown; Android may delay execution. */
object WearReminders {
    private const val TAG = "techpie-wear-reminders"
    private val lock = Any()
    private fun prefs(context: Context) = context.getSharedPreferences(TAG, Context.MODE_PRIVATE)
    private fun key(id: String) = MessageDigest.getInstance("SHA-256")
        .digest(id.toByteArray()).joinToString("") { "%02x".format(it) }

    fun replace(context: Context, json: String) = synchronized(lock) {
        val spec = JSONObject(json)
        require(spec.getString("deviceId").isNotBlank())
        require(spec.getString("bindingId").isNotBlank())
        require(spec.getLong("leaseUntilMs") > System.currentTimeMillis())
        val items = spec.getJSONArray("items")
        require(items.length() <= 500)
        for (i in 0 until items.length()) validate(items.getJSONObject(i))
        val store = prefs(context)
        val old = store.getString("spec", null)?.let { JSONObject(it) }
        if (old?.optString("bindingId") != spec.getString("bindingId")) {
            check(store.edit().clear().commit())
        }
        check(store.edit().putString("spec", spec.toString()).commit())
        val manager = WorkManager.getInstance(context)
        // Same reminder keeps its unique work (including its original due time).
        val ids = mutableSetOf<String>()
        for (i in 0 until items.length()) {
            val reminder = items.getJSONObject(i)
            val id = reminder.getString("reminderId")
            val name = "$TAG-${key(id)}"
            ids.add(name)
            if (store.contains("sent:${key(id)}")) continue
            val delay = (reminder.getLong("scheduledAtMs") - System.currentTimeMillis()).coerceAtLeast(0)
            val request = OneTimeWorkRequestBuilder<WearReminderWorker>()
                .setInputData(workDataOf("reminderId" to id))
                .setInitialDelay(delay, TimeUnit.MILLISECONDS).addTag(TAG).build()
            manager.enqueueUniqueWork(name, ExistingWorkPolicy.KEEP, request)
        }
        val previous = store.getStringSet("workNames", emptySet()) ?: emptySet()
        (previous - ids).forEach { manager.cancelUniqueWork(it) }
        check(store.edit().putStringSet("workNames", ids).commit())
    }

    fun clear(context: Context) = synchronized(lock) {
        // Leave sent receipts for this installation to avoid duplicating old reminders.
        check(prefs(context).edit().remove("spec").commit())
        WorkManager.getInstance(context).cancelAllWorkByTag(TAG)
    }

    private fun validate(reminder: JSONObject) {
        require(reminder.getString("reminderId").length in 1..128)
        require(reminder.getString("title").isNotBlank())
        require(reminder.getLong("expiresAtMs") > reminder.getLong("scheduledAtMs"))
        require(reminder.getLong("expiresAtMs") - reminder.getLong("scheduledAtMs") <= 600_000)
        require(reminder.getLong("dueAtMs") > 0)
    }

    private fun current(context: Context, id: String): Pair<JSONObject, JSONObject>? {
        val raw = prefs(context).getString("spec", null) ?: return null
        val spec = JSONObject(raw)
        if (spec.getLong("leaseUntilMs") <= System.currentTimeMillis()) return null
        val items = spec.getJSONArray("items")
        for (i in 0 until items.length()) {
            val item = items.getJSONObject(i)
            if (item.getString("reminderId") == id) return spec to item
        }
        return null
    }

    fun send(context: Context, json: String, success: (String) -> Unit, failure: (Exception) -> Unit) {
        // SDK tasks and permission/device lookups never block Flutter's UI thread.
        java.util.concurrent.Executors.newSingleThreadExecutor().let { executor ->
            executor.execute {
                try {
                    val requested = JSONObject(json)
                    val id = requested.getString("reminderId")
                    success(deliver(context, id))
                } catch (error: Exception) { failure(error) }
                finally { executor.shutdown() }
            }
        }
    }

    fun deliver(context: Context, id: String): String {
        val pair = synchronized(lock) { current(context, id) } ?: return "expired"
        val (spec, reminder) = pair
        validate(reminder)
        val now = System.currentTimeMillis()
        if (now < reminder.getLong("scheduledAtMs")) return "notDue"
        if (now >= reminder.getLong("expiresAtMs")) return "expired"
        val receipt = "sent:${key(id)}"
        prefs(context).getString(receipt, null)?.let { return it }
        if (!Tasks.await(HiWear.getAuthClient(context).checkPermission(Permission.NOTIFY), 15, TimeUnit.SECONDS)) {
            return "unsupported"
        }
        val device = Tasks.await(HiWear.getDeviceClient(context).bondedDevices, 15, TimeUnit.SECONDS)
            .firstOrNull { it.uuid == spec.getString("deviceId") && it.isConnected }
            ?: return "disconnected"
        val format = SimpleDateFormat("MM-dd HH:mm", Locale.CHINA).apply { timeZone = TimeZone.getTimeZone("Asia/Shanghai") }
        val text = reminder.getString("title").take(16) + " " + format.format(Date(reminder.getLong("dueAtMs")))
        val notification = Notification.Builder()
            .setTemplateId(NotificationTemplate.NOTIFICATION_TEMPLATE_NO_BUTTON)
            .setPackageName(context.packageName).setTitle("DDL 提醒").setText(text).build()
        val task = synchronized(lock) {
            val latest = current(context, id) ?: return "expired"
            if (latest.first.getString("bindingId") != spec.getString("bindingId") ||
                latest.first.getString("deviceId") != spec.getString("deviceId") ||
                System.currentTimeMillis() >= latest.second.getLong("expiresAtMs")) return "expired"
            prefs(context).getString(receipt, null)?.let { return it }
            // Persist before the irreversible call. A crash/timeout must not auto-send twice.
            check(prefs(context).edit().putString(receipt, "deliveryUnknown").commit())
            HiWear.getNotifyClient(context).notify(device, notification)
        }
        return try {
            Tasks.await(task, 15, TimeUnit.SECONDS)
            synchronized(lock) { prefs(context).edit().putString(receipt, "submitted").commit() }
            "submitted"
        } catch (_: Exception) { "deliveryUnknown" }
    }
}

class WearReminderWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result {
        val id = inputData.getString("reminderId") ?: return Result.failure()
        return try {
            when (WearReminders.deliver(applicationContext, id)) {
                "disconnected" -> if (runAttemptCount == 0) Result.retry() else Result.success()
                else -> Result.success()
            }
        } catch (_: Exception) {
            if (runAttemptCount == 0) Result.retry() else Result.failure()
        }
    }
}
