package club.geekpie.techpie.widgets

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WidgetSystemChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED -> {
                WidgetRefreshScheduler.updateAllAndSchedule(context)
            }
        }
    }
}
