package club.geekpie.techpie.wear

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.huawei.wearengine.HiWear
import com.huawei.wearengine.WearEngineException
import com.huawei.wearengine.auth.AuthCallback
import com.huawei.wearengine.auth.Permission
import com.huawei.wearengine.client.ServiceConnectionListener
import com.huawei.wearengine.device.Device
import com.huawei.wearengine.p2p.Message
import com.huawei.wearengine.p2p.Receiver
import com.huawei.wearengine.p2p.SendCallback
import com.huawei.wearengine.p2p.PingCallback
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** Native transport only. Product acknowledgements are processed in Dart. */
class WearEngineBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "techpie/wear_engine")
    private val handler = Handler(Looper.getMainLooper())
    private var selected: Device? = null
    private var receiver: Receiver? = null
    private var disposed = false
    private var serviceReady = false
    private var releasing = false
    private var generation = 0
    private val poll = object : Runnable {
        override fun run() {
            val device = selected ?: return
            val epoch = generation
            HiWear.getDeviceClient(activity).bondedDevices.addOnSuccessListener { devices ->
                if (epoch == generation && devices.none { it.uuid == device.uuid && it.isConnected }) {
                    closeTransport()
                    event("state", mapOf("device" to "disconnected"))
                }
            }.addOnFailureListener { event("state", mapOf("service" to "unavailable")) }
            handler.postDelayed(this, 5000)
        }
    }
    private val p2p by lazy { HiWear.getP2pClient(activity) }
    private val auth by lazy { HiWear.getAuthClient(activity) }
    private val service by lazy {
        HiWear.getWearEngineClient(activity, object : ServiceConnectionListener {
            override fun onServiceConnect() {
                if (!releasing && !disposed) { serviceReady = true; emitState("ready") }
            }
            override fun onServiceDisconnect() {
                serviceReady = false
                if (!releasing && selected != null) {
                    generation++
                    selected = null
                    receiver = null
                    emitState("unavailable")
                }
            }
        })
    }

    init { channel.setMethodCallHandler(::handle) }

    private fun event(method: String, data: Any?) = handler.post {
        if (!disposed) channel.invokeMethod(method, data)
    }
    private fun emitState(state: String) = event("state", mapOf("service" to state))
    private fun fail(result: MethodChannel.Result, error: Exception) {
        val code = (error as? WearEngineException)?.errorCode
        Log.w("TechPieWear", "SDK failure: code=$code, type=${error.javaClass.simpleName}")
        handler.post { result.error("SERVICE_UNAVAILABLE", "Wear Engine operation failed", code) }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "status" -> {
                    auth.checkPermissions(arrayOf(Permission.DEVICE_MANAGER, Permission.NOTIFY))
                        .addOnSuccessListener { grants ->
                            handler.post { result.success(mapOf(
                                "service" to if (serviceReady) "ready" else "unavailable",
                                "device" to if (selected?.isConnected == true) "connected" else "disconnected",
                                "permission" to mapOf("p2p" to (grants.getOrNull(0) == true),
                                    "notify" to (grants.getOrNull(1) == true)))) }
                        }.addOnFailureListener { fail(result, it) }
                }
                "authorize" -> {
                    Log.i("TechPieWear", "Requesting device authorization")
                    val includeNotify = call.argument<Boolean>("notify") == true
                    val permissions = if (includeNotify) arrayOf(Permission.DEVICE_MANAGER, Permission.NOTIFY)
                        else arrayOf(Permission.DEVICE_MANAGER)
                    val answered = AtomicBoolean(false)
                    auth.requestPermission(object : AuthCallback {
                        override fun onOk(grants: Array<Permission>) {
                            Log.i("TechPieWear", "Device authorization granted=${grants.contains(Permission.DEVICE_MANAGER)}")
                            if (answered.compareAndSet(false, true)) handler.post {
                                result.success(mapOf("p2p" to grants.contains(Permission.DEVICE_MANAGER),
                                    "notify" to grants.contains(Permission.NOTIFY)))
                            }
                        }
                        override fun onCancel() {
                            if (answered.compareAndSet(false, true)) handler.post {
                                result.error("PERMISSION_DENIED", "Wear Engine authorization cancelled", null)
                            }
                        }
                    }, *permissions).addOnFailureListener {
                        if (answered.compareAndSet(false, true)) fail(result, it)
                    }
                }
                "devices" -> HiWear.getDeviceClient(activity).bondedDevices
                    .addOnSuccessListener { devices -> handler.post {
                        Log.i("TechPieWear", "Device query count=${devices.size}")
                        result.success(devices.map { mapOf("id" to it.uuid, "name" to it.name,
                            "model" to it.model, "connected" to it.isConnected) })
                    } }.addOnFailureListener { fail(result, it) }
                "open" -> {
                    val id = requireNotNull(call.argument<String>("deviceId"))
                    val fingerprint = requireNotNull(call.argument<String>("fingerprint"))
                    require(fingerprint.length in 1..512 && fingerprint.none { it.isWhitespace() })
                    closeTransport()
                    val epoch = generation
                    HiWear.getDeviceClient(activity).bondedDevices.addOnSuccessListener { devices ->
                        if (epoch != generation || disposed) {
                            handler.post { result.error("SESSION_MISMATCH", "Connection was cancelled", null) }
                            return@addOnSuccessListener
                        }
                        val device = devices.firstOrNull { it.uuid == id && it.isConnected }
                        if (device == null) {
                            handler.post { result.error("DEVICE_DISCONNECTED", "Selected device is not connected", null) }
                            return@addOnSuccessListener
                        }
                        p2p.setPeerPkgName("com.geekpie.techpie.watch").setPeerFingerPrint(fingerprint)
                        val listener = Receiver { message ->
                            if (epoch == generation && message.type == Message.MESSAGE_TYPE_DATA) {
                                message.data?.let { event("frame", it) }
                            }
                        }
                        receiver = listener
                        selected = device
                        p2p.registerReceiver(device, listener).addOnSuccessListener {
                            if (epoch == generation && !disposed) {
                                service.registerServiceConnectionListener()
                                serviceReady = true
                                handler.postDelayed(poll, 5000)
                                val answered = AtomicBoolean(false)
                                p2p.ping(device, object : PingCallback {
                                    override fun onPingResult(code: Int) {
                                        if (answered.compareAndSet(false, true)) handler.post {
                                            if (epoch != generation || disposed) result.error("SESSION_MISMATCH", "Connection was cancelled", null)
                                            else if (code == 202) result.success(null)
                                            else result.error("PEER_NOT_READY", "Watch app is not ready", code)
                                        }
                                    }
                                }).addOnFailureListener { if (answered.compareAndSet(false, true)) fail(result, it) }
                            } else handler.post { result.error("SESSION_MISMATCH", "Connection was cancelled", null) }
                        }.addOnFailureListener { closeTransport(); fail(result, it) }
                    }.addOnFailureListener { fail(result, it) }
                }
                "send" -> {
                    val data = requireNotNull(call.argument<ByteArray>("bytes"))
                    require(data.size <= 1024)
                    val device = selected ?: run {
                        result.error("DEVICE_DISCONNECTED", "No active device", null); return
                    }
                    val answered = AtomicBoolean(false)
                    p2p.send(device, Message.Builder().setPayload(data).build(), object : SendCallback {
                        override fun onSendProgress(progress: Long) {}
                        override fun onSendResult(code: Int) {
                            if (answered.compareAndSet(false, true)) handler.post {
                                if (code == 207) result.success(null)
                                else result.error("TRANSPORT_FAILED", "Wear Engine send failed", code)
                            }
                        }
                    }).addOnFailureListener { if (answered.compareAndSet(false, true)) fail(result, it) }
                }
                "close" -> { closeTransport(); releaseService(result) }
                "scheduleReminders" -> {
                    val json = requireNotNull(call.argument<String>("json"))
                    WearReminders.replace(activity, json)
                    result.success(null)
                }
                "cancelReminders" -> { WearReminders.clear(activity); result.success(null) }
                "sendReminder" -> WearReminders.send(activity,
                    requireNotNull(call.argument<String>("json")),
                    { value -> handler.post { result.success(value) } },
                    { error -> fail(result, error) })
                else -> result.notImplemented()
            }
        } catch (error: Exception) { fail(result, error) }
    }

    private fun closeTransport() {
        generation++
        handler.removeCallbacks(poll)
        receiver?.let { p2p.unregisterReceiver(it) }
        receiver = null
        selected = null
    }
    private fun releaseService(result: MethodChannel.Result? = null) {
        if (!serviceReady) { result?.success(null); return }
        releasing = true
        serviceReady = false
        // Finish teardown before a new open; an intentional disconnect is not a peer failure.
        service.unregisterServiceConnectionListener().addOnCompleteListener {
            service.releaseConnection().addOnCompleteListener {
                releasing = false
                handler.post { result?.success(null) }
            }
        }
    }
    fun dispose() {
        closeTransport()
        releaseService()
        disposed = true
        channel.setMethodCallHandler(null)
    }
}
