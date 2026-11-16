package club.geekpie.techpie

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.service.OnServiceConnectionListener
import org.json.JSONArray
import org.json.JSONObject

/** 上课提醒排程：AlarmManager 触发广播，即使 app 进程不在前台也能推送到手环。 */
object BandReminders {
    const val ACTION = "club.geekpie.techpie.BAND_REMINDER"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_AT = "at"

    private const val PREFS = "techpie_band_reminders"
    private const val ITEMS_KEY = "items"
    private const val PENDING_KEY = "pending"
    private const val NODE_ID_KEY = "band_node_id"
    private const val LAST_AT_KEY = "last_at"
    private const val LAST_TEXT_KEY = "last_text"
    private const val MAX_REMINDERS = 64
    private const val MAX_PENDING = 8

    /** 未送达提醒只在原定时间后这段时间内补发；更早的已经过时。 */
    private const val PENDING_WINDOW_MS = 10 * 60 * 1000L

    data class Item(val atMillis: Long, val title: String, val body: String)

    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    // 穿戴 SDK 的服务连接是进程级的：冷启动广播要先等它连上，否则 sendNotify
    // 打到还没绑定好的服务上直接失败。只注册一次监听，进程结束自然释放。
    @Volatile private var serviceListenerInstalled = false
    @Volatile private var serviceReady = false
    @Volatile private var readyWaiter: (() -> Unit)? = null

    /** 记住最近连上的手环节点：广播进程冷启动时不必重新等设备发现。 */
    fun rememberNode(context: Context, nodeId: String) {
        if (nodeId.isBlank()) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(NODE_ID_KEY, nodeId).apply()
    }

    fun knownNode(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(NODE_ID_KEY, null)?.takeIf { it.isNotBlank() }

    fun schedule(context: Context, items: List<Item>) {
        cancelAll(context)
        persist(context, items)
        register(context, items)
    }

    /** 开机、时间跳变、应用更新都会清掉 AlarmManager 闹钟；用持久化副本恢复未来的提醒。 */
    fun restore(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(ITEMS_KEY, null) ?: return
        val items = try {
            val now = System.currentTimeMillis()
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val at = item.getLong("at")
                    if (at > now) {
                        add(Item(at, item.getString("title"), item.getString("body")))
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
        if (items.isEmpty()) return
        register(context, items)
        Log.i("BandReminders", "restored ${items.size} reminders")
    }

    fun cancelAll(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (index in 0 until MAX_REMINDERS) {
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                index,
                intentFor(context, "", "", 0L),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: continue
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }
        // 取消提醒时同步清掉持久化副本，避免开机恢复已取消的提醒。
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(ITEMS_KEY).apply()
    }

    private fun register(context: Context, items: List<Item>) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
        items.forEachIndexed { index, item ->
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                index,
                intentFor(context, item.title, item.body, item.atMillis),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            if (exact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    item.atMillis,
                    pendingIntent,
                )
            } else {
                // 未授予精确闹钟权限时退化为非精确调度，仍可提醒但可能延迟。
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    item.atMillis,
                    pendingIntent,
                )
            }
        }
        Log.i("BandReminders", "registered ${items.size} reminders (exact=$exact)")
    }

    private fun persist(context: Context, items: List<Item>) {
        val array = JSONArray()
        items.forEach { item ->
            array.put(
                JSONObject()
                    .put("at", item.atMillis)
                    .put("title", item.title)
                    .put("body", item.body),
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(ITEMS_KEY, array.toString()).apply()
    }

    private fun intentFor(context: Context, title: String, body: String, at: Long): Intent =
        Intent(context, BandReminderReceiver::class.java).apply {
            action = ACTION
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_AT, at)
        }

    /** 广播进程冷启动：等穿戴服务连上，超时也继续（可能本来就已连好）。 */
    fun whenServiceReady(context: Context, timeoutMs: Long, onReady: () -> Unit) {
        if (serviceReady) {
            onReady()
            return
        }
        installServiceListener(context)
        var fired = false
        val once = {
            if (!fired) {
                fired = true
                readyWaiter = null
                onReady()
            }
        }
        readyWaiter = once
        mainHandler.postDelayed(once, timeoutMs)
    }

    private fun installServiceListener(context: Context) {
        if (serviceListenerInstalled) return
        serviceListenerInstalled = true
        try {
            Wearable.getServiceApi(context).registerServiceConnectionListener(
                object : OnServiceConnectionListener {
                    override fun onServiceConnected() {
                        serviceReady = true
                        readyWaiter?.invoke()
                        readyWaiter = null
                    }

                    override fun onServiceDisconnected() {
                        serviceReady = false
                    }
                },
            )
        } catch (error: Exception) {
            // 旧版 SDK 没有该接口时退回超时路径，提醒仍然尝试投递。
            Log.w("BandReminders", "service listener unavailable: ${error.message}")
        }
    }

    // 投递前不再预检 NOTIFY 权限：冷进程里穿戴服务刚绑定时 checkPermission
    // 可能返回过期的"未授权"，把本来能送达的提醒拦在发送之前（手动测试通知
    // 不走这道门，所以一直正常）。直接发送，让返回的 Status 说出真实原因。

    /** Status.code 的可读名称（取值来自 xms-wearable-lib 1.4 的 Status 常量）。 */
    fun statusName(code: Int): String = when (code) {
        0 -> "成功"
        -1 -> "已取消"
        -2 -> "对端处理超时"
        -3 -> "被中断"
        -4 -> "手环连接已断开"
        -5 -> "小米运动健康未安装"
        -6 -> "签名校验失败"
        -7 -> "手环通知权限未开启"
        -8 -> "手环快应用未安装"
        else -> "status $code"
    }

    /**
     * 一次投递失败往往只是连接抖动，重试一次能把"手环没反应"变成送达。
     * 注意 sendNotify 的 Task 成功只代表 IPC 完成，手环是否接受要看 Status：
     * 旧实现把任何 Status 都当送达，于是权限被拒、快应用缺失、对端超时
     * 全部被记成"已送达"，设置页永远查不出原因。
     */
    fun send(
        context: Context,
        nodeId: String,
        title: String,
        body: String,
        attempts: Int = 2,
        onDone: (Boolean, String) -> Unit,
    ) {
        Wearable.getNotifyApi(context).sendNotify(nodeId, title, body)
            .addOnSuccessListener { status ->
                if (status.isSuccess) {
                    Log.i("BandReminders", "band reminder delivered to $nodeId")
                    onDone(true, "已推送到手环")
                } else {
                    Log.w("BandReminders", "sendNotify to $nodeId status ${status.code}")
                    retryOrFail(context, nodeId, title, body, attempts, "推送被手环拒绝：${statusName(status.code)}", onDone)
                }
            }
            .addOnFailureListener { error ->
                Log.w("BandReminders", "sendNotify to $nodeId failed: ${error.message}")
                retryOrFail(context, nodeId, title, body, attempts, "推送失败：${error.message}", onDone)
            }
    }

    private fun retryOrFail(
        context: Context,
        nodeId: String,
        title: String,
        body: String,
        attempts: Int,
        detail: String,
        onDone: (Boolean, String) -> Unit,
    ) {
        if (attempts > 1) {
            mainHandler.postDelayed(
                { send(context, nodeId, title, body, attempts - 1, onDone) },
                SEND_RETRY_MS,
            )
        } else {
            onDone(false, detail)
        }
    }

    /**
     * 手环当时不在线、或服务没起来时的提醒不能就这样丢掉：留一份副本，
     * 等下次 app 连上手环（通常就是用户打开 app）在 10 分钟窗口内补发。
     */
    fun enqueuePending(context: Context, item: Item) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = readArray(prefs.getString(PENDING_KEY, null))
        array.put(
            JSONObject()
                .put("at", item.atMillis)
                .put("title", item.title)
                .put("body", item.body),
        )
        while (array.length() > MAX_PENDING) {
            array.remove(0)
        }
        prefs.edit().putString(PENDING_KEY, array.toString()).apply()
    }

    /** app 内已连上手环时补发未送达提醒；过期的直接丢弃，不打扰用户。 */
    fun flushPending(context: Context, nodeId: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(PENDING_KEY, null) ?: return
        prefs.edit().remove(PENDING_KEY).apply()
        val now = System.currentTimeMillis()
        val array = readArray(raw)
        for (i in 0 until array.length()) {
            val item = try {
                val obj = array.getJSONObject(i)
                Item(obj.getLong("at"), obj.getString("title"), obj.getString("body"))
            } catch (_: Exception) {
                continue
            }
            if (now - item.atMillis > PENDING_WINDOW_MS) continue
            send(context, nodeId, item.title, item.body) { delivered, _ ->
                if (!delivered) enqueuePending(context, item)
            }
        }
    }

    fun recordResult(context: Context, delivered: Boolean, detail: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(LAST_AT_KEY, System.currentTimeMillis())
            .putString(LAST_TEXT_KEY, (if (delivered) "已送达" else "未送达") + " · " + detail)
            .apply()
    }

    fun lastResultAt(context: Context): Long? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(LAST_AT_KEY, 0L).takeIf { it > 0L }

    fun lastResultText(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(LAST_TEXT_KEY, null)

    private fun readArray(raw: String?): JSONArray = try {
        if (raw.isNullOrBlank()) JSONArray() else JSONArray(raw)
    } catch (_: Exception) {
        JSONArray()
    }

    const val SERVICE_WAIT_MS = 3500L
    const val SEND_RETRY_MS = 700L
}

/**
 * 到点时系统可能为新进程触发广播：穿戴 SDK 的服务绑定是异步的，第一次
 * getConnectedNodes() 往往还是空列表，而旧实现只查一次就静默放弃，于是
 * 手机有通知、手环没动静。现在的顺序是：等穿戴服务连上 → 试上次连过的
 * 节点 → 校验通知权限 → 带重试投递 → 仍失败就留副本待下次补发，并记录
 * 结果供设置页显示。全程留在广播的 10 秒预算内。
 */
class BandReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != BandReminders.ACTION) return
        val title = intent.getStringExtra(BandReminders.EXTRA_TITLE) ?: "TechPie"
        val body = intent.getStringExtra(BandReminders.EXTRA_BODY) ?: ""
        val at = intent.getLongExtra(BandReminders.EXTRA_AT, System.currentTimeMillis())
        // 手机端同时震动提醒；手环不在连接时用户也不会错过。
        notifyPhone(context, title, body)
        val appContext = context.applicationContext
        val pendingResult = goAsync()
        var finished = false
        val finish = { delivered: Boolean, detail: String ->
            if (!finished) {
                finished = true
                BandReminders.recordResult(appContext, delivered, detail)
                if (!delivered) {
                    BandReminders.enqueuePending(
                        appContext,
                        BandReminders.Item(at, title, body),
                    )
                }
                runCatching { pendingResult.finish() }
            }
        }
        // 看门狗：穿戴服务挂起时 checkPermission/sendNotify 的 Task 可能永不回调，
        // 旧实现就这样死在广播里，不留任何记录。预留 500ms 收尾，保证在系统
        // 杀掉进程前把"超时"写进诊断并留副本补发。
        Handler(Looper.getMainLooper()).postDelayed(
            { finish(false, "投递超时：穿戴服务无响应") },
            TIMEOUT_GUARD_MS,
        )

        BandReminders.whenServiceReady(appContext, BandReminders.SERVICE_WAIT_MS) {
            val known = BandReminders.knownNode(appContext)
            if (known != null) {
                deliver(appContext, known, title, body) { delivered, reason ->
                    if (delivered) {
                        finish(true, reason)
                    } else {
                        discover(appContext, ATTEMPTS) { nodeId ->
                            if (nodeId == null) {
                                finish(false, "手环未连接")
                            } else {
                                deliver(appContext, nodeId, title, body) { retried, retryReason ->
                                    finish(retried, retryReason)
                                }
                            }
                        }
                    }
                }
            } else {
                discover(appContext, ATTEMPTS) { nodeId ->
                    if (nodeId == null) {
                        finish(false, "手环未连接")
                    } else {
                        deliver(appContext, nodeId, title, body) { delivered, reason ->
                            finish(delivered, reason)
                        }
                    }
                }
            }
        }
    }

    /** 直接投递（与手动测试通知同一路径）；失败原因由 Status 透传到诊断。 */
    private fun deliver(
        context: Context,
        nodeId: String,
        title: String,
        body: String,
        onDone: (Boolean, String) -> Unit,
    ) {
        BandReminders.send(context, nodeId, title, body, onDone = onDone)
    }

    /** 冷启动时 SDK 可能还没绑定好，轮询几次再判定"没有设备"。 */
    private fun discover(context: Context, attemptsLeft: Int, onDone: (String?) -> Unit) {
        Wearable.getNodeApi(context).getConnectedNodes()
            .addOnSuccessListener { nodes ->
                val id = nodes.firstOrNull()?.id
                if (id != null) {
                    BandReminders.rememberNode(context, id)
                    onDone(id)
                } else {
                    retryDiscovery(context, attemptsLeft, onDone)
                }
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "getConnectedNodes failed: ${error.message}")
                retryDiscovery(context, attemptsLeft, onDone)
            }
    }

    private fun retryDiscovery(context: Context, attemptsLeft: Int, onDone: (String?) -> Unit) {
        if (attemptsLeft <= 1) {
            onDone(null)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed(
            { discover(context, attemptsLeft - 1, onDone) },
            DISCOVERY_INTERVAL_MS,
        )
    }

    private fun notifyPhone(context: Context, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return // Android 13+ 未授予通知权限时静默丢弃。
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "上课提醒", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "上课前在手机上震动提醒"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 250, 500)
                },
            )
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(NOTIFY_ID, notification)
    }

    private companion object {
        const val TAG = "BandReminders"
        const val CHANNEL_ID = "band_reminder"
        const val NOTIFY_ID = 48292

        /** 服务 3.5s + 发现 4×0.9s + 重试投递，留在广播的 10s 预算内。 */
        const val ATTEMPTS = 4
        const val DISCOVERY_INTERVAL_MS = 900L

        /** 看门狗：goAsync 预算 10s，留 500ms 给记录与 finish。 */
        const val TIMEOUT_GUARD_MS = 9500L
    }
}

/** 重启/时间跳变/应用更新会把 AlarmManager 闹钟清掉，用持久化副本恢复。 */
class BandReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> {
                BandReminders.restore(context)
            }
        }
    }
}