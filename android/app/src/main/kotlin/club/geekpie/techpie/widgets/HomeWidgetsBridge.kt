package club.geekpie.techpie.widgets

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class HomeWidgetsBridge(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val store = WidgetSnapshotStore(appContext)
    private val channel = MethodChannel(messenger, "techpie/home_widgets")
    private var pendingRoute: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "publishSchedule" -> {
                    val raw = call.arguments as? String
                    if (raw == null || !store.saveSchedule(raw)) {
                        result.error("invalid_snapshot", "Invalid schedule widget snapshot.", null)
                    } else {
                        WidgetRefreshScheduler.updateAllAndSchedule(appContext)
                        result.success(null)
                    }
                }
                "clearSchedule" -> {
                    store.clearSchedule()
                    WidgetRefreshScheduler.updateAllAndSchedule(appContext)
                    result.success(null)
                }
                "publishEcard" -> {
                    val raw = call.arguments as? String
                    if (raw == null || !store.saveEcard(raw)) {
                        result.error("invalid_snapshot", "Invalid e-card widget snapshot.", null)
                    } else {
                        WidgetRefreshScheduler.updateAllWidgets(appContext)
                        result.success(null)
                    }
                }
                "clearEcard" -> {
                    store.clearEcard()
                    WidgetRefreshScheduler.updateAllWidgets(appContext)
                    result.success(null)
                }
                "consumePendingRoute" -> result.success(pendingRoute)
                "acknowledgePendingRoute" -> {
                    pendingRoute = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun capture(intent: Intent?, notifyFlutter: Boolean) {
        val uri = intent?.data ?: return
        if (uri.scheme?.lowercase() != "techpie" || uri.host?.lowercase() != "schedule") return
        pendingRoute = "schedule"
        if (notifyFlutter) channel.invokeMethod("openSchedule", null)
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
