package club.geekpie.techpie

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class EcardWidgetBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "techpie/ecard_deep_link")
    private var pendingRoute: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePendingRoute" -> result.success(pendingRoute)
                "acknowledgePendingRoute" -> {
                    pendingRoute = null
                    result.success(null)
                }
                "widgetAvailability" -> result.success(availability())
                "requestPinWidget" -> {
                    if (Build.VERSION.SDK_INT >= 26 && availability() == "nativePin") {
                        val provider = ComponentName(activity, EcardPayWidgetProvider::class.java)
                        result.success(AppWidgetManager.getInstance(activity).requestPinAppWidget(provider, null, null))
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun availability(): String {
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_APP_WIDGETS)) return "unsupported"
        if (Build.VERSION.SDK_INT >= 26 && AppWidgetManager.getInstance(activity).isRequestPinAppWidgetSupported) return "nativePin"
        return "manual"
    }

    fun capture(intent: Intent?, notifyFlutter: Boolean) {
        val uri = intent?.data ?: return
        if (uri.scheme?.lowercase() != "techpie" || uri.host?.lowercase() != "ecard" || uri.path != "/pay") return
        pendingRoute = "pay"
        if (notifyFlutter) channel.invokeMethod("openPayCode", null)
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
