package club.geekpie.techpie

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.auth.Permission
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.service.OnServiceConnectionListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException
import org.json.JSONObject
import java.util.ArrayDeque

/**
 * 手环快应用（Vela system.interconnect）通信桥。
 * 快应用包名/签名必须与本 APK 一致；连接经由小米运动健康的穿戴服务中转。
 */
class BandBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var serviceConnected = false
    private var nodeId: String? = null
    private var nodeName: String? = null
    private var permissionGranted = false
    private var wearAppInstalled: Boolean? = null
    private var lastError: String? = null
    private var listenerNodeId: String? = null
    private var lastMessageAt: Long? = null
    private var lastPongAt: Long? = null
    private val recentMessages = ArrayDeque<String>()

    private val messageListener = OnMessageReceivedListener { nodeId, message ->
        val received = String(message, Charsets.UTF_8)
        lastMessageAt = System.currentTimeMillis()
        if (received.contains("\"t\":\"pong\"")) {
            lastPongAt = lastMessageAt
        }
        synchronized(recentMessages) {
            recentMessages.addLast(received)
            while (recentMessages.size > MAX_MESSAGES) {
                recentMessages.removeFirst()
            }
        }
        emit(mapOf("type" to "message", "data" to received))
        Log.i(TAG, "received wearable message (${message.size} bytes)")
        when (messageType(received)) {
            "schedule.req" -> requestSchedule(nodeId, received)
            "assignments.req" -> requestFromDart(
                nodeId,
                "assignmentsRequest",
                emptyMap(),
            )
            "ecard.req" -> requestFromDart(
                nodeId,
                "ecardRequest",
                emptyMap(),
            )
            "offline.cred.req" -> requestFromDart(
                nodeId,
                "offlineCredRequest",
                emptyMap(),
            )
            else -> reply(nodeId, received)
        }
    }

    private fun messageType(raw: String): String? = try {
        JSONObject(raw).optString("t")
    } catch (_: JSONException) {
        null
    }

    /** 手环请求课表快照：向 Dart 层取数据后回发 schedule.snap / schedule.week。 */
    private fun requestSchedule(nodeId: String, raw: String) {
        val json = try {
            JSONObject(raw)
        } catch (_: JSONException) {
            JSONObject()
        }
        requestFromDart(
            nodeId,
            "scheduleRequest",
            mapOf(
                "date" to json.optString("date"),
                "week" to json.optBoolean("week", false),
            ),
        )
    }

    /** 向 Dart 层取数据并把返回结果回发手环。 */
    private fun requestFromDart(
        nodeId: String,
        method: String,
        arguments: Map<String, Any?>,
    ) {
        mainHandler.post {
            methodChannel.invokeMethod(
                method,
                arguments,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val map = (result as? Map<*, *>) ?: emptyMap<String, Any>()
                        val image = map["png"] as? String
                        val text = image ?: JSONObject(map).toString()
                        val chunkType =
                            if (image != null) "ecard.chunk"
                            else (map["t"] as? String ?: "snap") + ".chunk"
                        Log.i(TAG, "snapshot for $nodeId ($method): ${text.length} chars")
                        if (text.length > CHUNK_SIZE) {
                            sendChunk(
                                nodeId,
                                text,
                                0,
                                (text.length + CHUNK_SIZE - 1) / CHUNK_SIZE,
                                chunkType,
                            )
                            return
                        }
                        Wearable.getMessageApi(context)
                            .sendMessage(nodeId, text.toByteArray())
                            .addOnFailureListener { error ->
                                Log.w(TAG, "send snapshot failed", error)
                            }
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.w(TAG, "scheduleRequest error: $code $message")
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "scheduleRequest not implemented")
                    }
                },
            )
        }
    }

    /** 超过通道单包大小的载荷分片发送（type.chunk / seq / total / data）。 */
    private fun sendChunk(
        nodeId: String,
        base64: String,
        seq: Int,
        total: Int,
        chunkType: String,
    ) {
        if (seq >= total) return
        val start = seq * CHUNK_SIZE
        val end = minOf(base64.length, start + CHUNK_SIZE)
        val payload = JSONObject()
            .put("t", chunkType)
            .put("seq", seq)
            .put("total", total)
            .put("data", base64.substring(start, end))
        Wearable.getMessageApi(context)
            .sendMessage(nodeId, payload.toString().toByteArray())
            .addOnSuccessListener { sendChunk(nodeId, base64, seq + 1, total, chunkType) }
            .addOnFailureListener { error ->
                Log.w(TAG, "send chunk $seq failed", error)
            }
    }

    private val serviceListener = object : OnServiceConnectionListener {
                override fun onServiceConnected() {
                    serviceConnected = true
                    emitState()
                    attachNodes()
                }

                override fun onServiceDisconnected() {
                    serviceConnected = false
                    emitState()
                }
            }

    fun dispose() {
        sink = null
        mainHandler.removeCallbacksAndMessages(null)
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        Wearable.getServiceApi(context).unregisterServiceConnectionListener(serviceListener)
        listenerNodeId?.let { Wearable.getMessageApi(context).removeListener(it) }
        listenerNodeId = null
    }

    fun start() {
        eventChannel.setStreamHandler(this)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(statusMap())
                "refresh" -> refreshStatus(result)
                "sendOfflineCred" -> {
                    val id = nodeId
                    if (id == null) {
                        result.error("no_device", "尚未连接手环", null)
                    } else {
                        requestFromDart(id, "offlineCredRequest", emptyMap())
                        result.success(statusMap())
                    }
                }
                "sendOfflineCredClear" -> {
                    val id = nodeId
                    if (id == null) {
                        result.error("no_device", "尚未连接手环", null)
                    } else {
                        val payload = JSONObject().put("t", "offline.cred.clear").toString()
                        Wearable.getMessageApi(context)
                            .sendMessage(id, payload.toByteArray())
                            .addOnSuccessListener { result.success(statusMap()) }
                            .addOnFailureListener { error ->
                                result.error("send_failed", error.message, null)
                            }
                    }
                }
                "requestPermission" -> requestPermission(result)
                "sendTest" -> sendTest(result)
                "sendNotification" -> sendNotification(call, result)
                "scheduleReminders" -> scheduleReminders(call, result)
                "cancelReminders" -> {
                    BandReminders.cancelAll(context)
                    result.success(true)
                }
                "requestExactAlarmPermission" -> {
                    result.success(openExactAlarmSettings())
                }
                else -> result.notImplemented()
            }
        }
        Wearable.getServiceApi(context).registerServiceConnectionListener(serviceListener)
        attachNodes()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun attachNodes() {
        Wearable.getNodeApi(context).getConnectedNodes()
            .addOnSuccessListener { nodes -> nodes.firstOrNull()?.let(::setupNode) }
            .addOnFailureListener { error ->
                Log.w(TAG, "getConnectedNodes failed", error)
                fail(error.message)
            }
    }

    /** 状态刷新：等探测链（节点→权限→手环应用）跑完再返回，避免读到旧快照。 */
    private fun refreshStatus(result: MethodChannel.Result) {
        Wearable.getNodeApi(context).getConnectedNodes()
            .addOnSuccessListener { nodes ->
                val node = nodes.firstOrNull()
                if (node == null) {
                    nodeId = null
                    nodeName = null
                    permissionGranted = false
                    wearAppInstalled = null
                    emitState()
                    result.success(statusMap())
                } else {
                    setupNode(node) { result.success(statusMap()) }
                }
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "refresh getConnectedNodes failed", error)
                fail(error.message)
                result.success(statusMap())
            }
    }

    private fun setupNode(node: Node, onDone: (() -> Unit)? = null) {
        nodeId = node.id
        nodeName = node.name?.trim()
        // 广播进程冷启动时靠它直接推提醒，不必重新等待设备发现。
        BandReminders.rememberNode(context, node.id)
        // 上次提醒时手环不在线、没送达的那条，在这里补发（过期的会自动丢弃）。
        BandReminders.flushPending(context, node.id)
        Log.i(TAG, "node ${node.id} ($nodeName)")
        Wearable.getAuthApi(context).checkPermission(node.id, Permission.DEVICE_MANAGER)
            .addOnSuccessListener { granted ->
                permissionGranted = granted
                queryInstalled(node.id) {
                    if (granted) listen(node.id) else emitState()
                    onDone?.invoke()
                }
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "checkPermission failed", error)
                fail(error.message)
                onDone?.invoke()
            }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val id = nodeId
        if (id == null) {
            result.error("no_device", "尚未连接手环", null)
            return
        }
        Wearable.getAuthApi(context)
            .requestPermission(id, Permission.DEVICE_MANAGER, Permission.NOTIFY)
            .addOnSuccessListener {
                permissionGranted = true
                listen(id)
                emitState()
                result.success(statusMap())
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "requestPermission failed", error)
                lastError = error.message
                emitState()
                result.error("permission_failed", error.message, null)
            }
    }

    private fun queryInstalled(id: String, onDone: (() -> Unit)? = null) {
        Wearable.getNodeApi(context).isWearAppInstalled(id)
            .addOnSuccessListener { installed ->
                wearAppInstalled = installed
                emitState()
                onDone?.invoke()
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "isWearAppInstalled failed", error)
                emitState()
                onDone?.invoke()
            }
    }

    private fun listen(id: String) {
        if (listenerNodeId == id) {
            emitState()
            return
        }
        listenerNodeId = id
        Wearable.getMessageApi(context).addListener(id, messageListener)
            .addOnSuccessListener {
                Log.i(TAG, "listener attached for $id")
                emitState()
            }
            .addOnFailureListener { error ->
                if (error is IllegalStateException) {
                    // The SDK keeps one registration per node; a duplicate
                    // addListener is harmless, treat it as attached.
                    Log.i(TAG, "listener already registered for $id")
                    emitState()
                } else {
                    listenerNodeId = null
                    Log.w(TAG, "addListener failed", error)
                    fail(error.message)
                }
            }
    }

    private fun sendTest(result: MethodChannel.Result) {
        val id = nodeId
        if (id == null) {
            result.error("no_device", "尚未连接手环", null)
            return
        }
        val payload = JSONObject().put("t", "ping").put("ts", System.currentTimeMillis())
        Wearable.getMessageApi(context).sendMessage(id, payload.toString().toByteArray())
            .addOnSuccessListener { result.success(statusMap()) }
            .addOnFailureListener { error ->
                Log.w(TAG, "sendMessage failed", error)
                lastError = error.message
                emitState()
                result.error("send_failed", error.message, null)
            }
    }

    private fun sendNotification(call: MethodCall, result: MethodChannel.Result) {
        val id = nodeId
        if (id == null) {
            result.error("no_device", "尚未连接手环", null)
            return
        }
        val title = call.argument<String>("title") ?: "TechPie"
        val message = call.argument<String>("message") ?: ""
        Wearable.getNotifyApi(context).sendNotify(id, title, message)
            .addOnSuccessListener { status ->
                // Task 成功只代表 IPC 完成，手环是否接受要看 Status。
                if (status.isSuccess) {
                    lastError = null
                    emitState()
                    result.success(true)
                } else {
                    lastError = "手环拒绝了通知（status ${status.code}）"
                    emitState()
                    result.error("notify_failed", lastError, null)
                }
            }
            .addOnFailureListener { error ->
                Log.w(TAG, "sendNotify failed", error)
                lastError = error.message
                emitState()
                result.error("notify_failed", error.message, null)
            }
    }

    private fun scheduleReminders(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<List<*>>("reminders") ?: emptyList<Any>()
        val now = System.currentTimeMillis()
        val items = raw.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val at = (map["at"] as? Number)?.toLong() ?: return@mapNotNull null
            if (at <= now) return@mapNotNull null
            BandReminders.Item(
                atMillis = at,
                title = map["title"] as? String ?: "TechPie",
                body = map["body"] as? String ?: "",
            )
        }
        BandReminders.schedule(context, items)
        result.success(items.size)
    }

    private fun reply(id: String, received: String) {
        val payload = JSONObject().put("t", "pong").put("echo", received)
        Wearable.getMessageApi(context).sendMessage(id, payload.toString().toByteArray())
            .addOnFailureListener { error -> Log.w(TAG, "reply failed", error) }
    }

    private fun exactAlarmsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    /** 打开系统的「闹钟和提醒」精确闹钟授权页；成功后需重排提醒。 */
    private fun openExactAlarmSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val intent = Intent(
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                context.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", context.packageName, null),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun statusMap(): Map<String, Any?> = mapOf(
        "serviceConnected" to serviceConnected,
        "nodeId" to nodeId,
        "nodeName" to nodeName,
        "permissionGranted" to permissionGranted,
        "wearAppInstalled" to wearAppInstalled,
        "lastError" to lastError,
        "lastMessageAt" to lastMessageAt,
        "lastPongAt" to lastPongAt,
        "exactAlarms" to exactAlarmsAllowed(),
        "lastReminderAt" to BandReminders.lastResultAt(context),
        "lastReminder" to BandReminders.lastResultText(context),
        "messages" to synchronized(recentMessages) { recentMessages.toList() },
    )

    private fun emitState() {
        val payload = statusMap().toMutableMap()
        payload["type"] = "state"
        emit(payload)
    }

    private fun fail(message: String?) {
        lastError = message
        emitState()
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post { sink?.success(payload) }
    }

    private companion object {
        private const val TAG = "BandBridge"
        private const val METHOD_CHANNEL = "techpie/band"
        private const val EVENT_CHANNEL = "techpie/band_events"
        private const val MAX_MESSAGES = 20
        private const val CHUNK_SIZE = 2400
    }
}
