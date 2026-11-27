package club.geekpie.techpie.widgets

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class DeadlineWidgetsBridge(context: Context, messenger: BinaryMessenger) {
    private val appContext = context.applicationContext
    private val store = WidgetSnapshotStore(appContext)
    private val channel = MethodChannel(messenger, "techpie/deadline_widgets")
    private var pendingDeadlinesRoute = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    val raw = call.arguments as? String
                    if (raw == null || !store.saveDeadlines(raw)) {
                        result.error("invalid_snapshot", "Invalid deadline widget snapshot.", null)
                    } else {
                        WidgetRefreshScheduler.updateAllAndSchedule(appContext)
                        result.success(null)
                    }
                }
                "clear" -> {
                    store.clearDeadlines()
                    WidgetRefreshScheduler.updateAllAndSchedule(appContext)
                    result.success(null)
                }
                "consumePendingRoute" -> result.success(pendingDeadlinesRoute)
                "acknowledgePendingRoute" -> {
                    pendingDeadlinesRoute = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun capture(intent: Intent?, notifyFlutter: Boolean) {
        val uri = intent?.data ?: return
        if (uri.scheme?.lowercase() != "techpie" || uri.host?.lowercase() != "deadlines") return
        pendingDeadlinesRoute = true
        if (notifyFlutter) channel.invokeMethod("openDeadlines", null)
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
