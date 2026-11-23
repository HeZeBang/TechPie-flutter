package club.geekpie.techpie.island

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

/**
 * The schedule-island channel: capability probing, frame updates and dismissal.
 *
 * The activity publishes cached state; native alarms publish later frames
 * without a running Flutter engine or foreground service.
 */
class IslandBridge(
    private val appContext: Context,
    messenger: BinaryMessenger,
    private val probe: IslandCapabilityProbe,
    private val factory: IslandNotificationFactory,
    private val requestPermission: (() -> Boolean)? = null,
) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(probe.snapshot().toMap())
                "refreshProbe" -> result.success(probe.refresh().toMap())
                "updateFrame" -> updateFrame(call, result)
                "dismiss" -> {
                    dismiss()
                    result.success(true)
                }
                "scheduleFrames" -> scheduleFrames(call, result)
                "cancelFrames" -> {
                    IslandAlarms.cancelAll(appContext)
                    IslandAlarms.cancelRepaint(appContext)
                    result.success(true)
                }
                "requestPermission" -> result.success(requestPermission?.invoke() ?: false)
                else -> result.notImplemented()
            }
        }
    }

    private fun dismiss() {
        IslandAlarms.cancelRepaint(appContext)
        factory.cancel(IslandNotificationFactory.NOTIFICATION_ID)
    }

    /** Precomputed frames from the Dart side, posted by AlarmManager later. */
    private fun scheduleFrames(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("frames") ?: "[]"
        val items = mutableListOf<IslandAlarms.Item>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val entry = array.getJSONObject(i)
                val frame = if (entry.isNull("frame")) {
                    null
                } else {
                    entry.getJSONObject("frame").toString()
                }
                items.add(IslandAlarms.Item(entry.getLong("at"), frame))
            }
        } catch (error: Exception) {
            result.error("BAD_FRAMES", error.message, null)
            return
        }
        IslandAlarms.schedule(appContext, items)
        result.success(items.size)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun updateFrame(call: MethodCall, result: MethodChannel.Result) {
        val frameJson = call.argument<String>("frame")
        val frame = frameJson?.let { IslandFrame.fromJson(it) }
        if (frame == null) {
            result.error("BAD_FRAME", "missing or unreadable frame json", null)
            return
        }
        // The caller may force a tier for testing; by default the device
        // decides, so a phone without the focus grant still gets the capsule
        // or a plain ongoing notification instead of nothing.
        val backend = call.argument<String>("backend")
            ?.let { name -> runCatching { IslandBackend.valueOf(name.uppercase()) }.getOrNull() }
            ?: probe.snapshot().backend
        try {
            factory.updateFrame(frame, backend, IslandNotificationFactory.NOTIFICATION_ID)
            // Keep a running class on the island even when the focus slot is
            // taken by another app's notification between frames.
            IslandAlarms.scheduleRepaint(appContext, frameJson)
            result.success(backend.name.lowercase())
        } catch (e: Exception) {
            result.error("ISLAND_ERROR", e.message, null)
        }
    }

    companion object {
        const val CHANNEL = "techpie/island"
    }
}
