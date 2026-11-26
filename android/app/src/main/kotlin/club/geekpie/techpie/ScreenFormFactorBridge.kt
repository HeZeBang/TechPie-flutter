package club.geekpie.techpie

import android.app.Activity
import android.os.Build
import android.view.Display
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reports the form factor of the screen this activity is currently on.
 *
 * Xiaomi exposes no public rear-screen API; the official Flip guidance is to
 * detect the device family through `MiuiMultiDisplayTypeInfo` and to react to
 * the window size for fold continuity. The rear screen is the secondary
 * display, so its id is the only reliable signal that the app is running there.
 */
class ScreenFormFactorBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(info())
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun info(): Map<String, Any?> {
        val display = currentDisplay()
        val displayId = display?.displayId ?: Display.DEFAULT_DISPLAY
        val metrics = activity.resources.displayMetrics
        val bounds = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.windowManager.currentWindowMetrics.bounds
        } else {
            android.graphics.Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
        }
        return mapOf(
            "isFlipDevice" to miuiFlag("isFlipDevice"),
            "isRearDevice" to miuiFlag("isRearDevice"),
            "displayId" to displayId,
            "windowWidthPx" to bounds.width(),
            "windowHeightPx" to bounds.height(),
            "density" to metrics.density.toDouble(),
            "densityDpi" to metrics.densityDpi,
            "isDefaultDisplay" to (displayId == Display.DEFAULT_DISPLAY),
            "isInMultiWindowMode" to activity.isInMultiWindowMode,
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }

    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }

    /**
     * The class is absent on most devices and hidden on some HyperOS builds;
     * a failed probe simply means "not this form factor", never a crash.
     */
    private fun miuiFlag(method: String): Boolean = try {
        val type = Class.forName("miui.util.MiuiMultiDisplayTypeInfo")
        type.getMethod(method).invoke(null) as? Boolean ?: false
    } catch (_: ReflectiveOperationException) {
        false
    } catch (_: SecurityException) {
        false
    } catch (_: LinkageError) {
        false
    }

    private companion object {
        const val CHANNEL = "techpie/screen_form_factor"
    }
}
