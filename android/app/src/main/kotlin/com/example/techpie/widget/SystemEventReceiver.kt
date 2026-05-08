package com.example.techpie.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Refreshes both Glance widgets on calendar-relevant system events:
 *   - DATE_CHANGED  → 00:00 every day, so "今日课程" and overdue flags roll over
 *   - TIMEZONE_CHANGED / LOCALE_CHANGED → date label / weekday text follow
 *
 * BOOT_COMPLETED is intentionally NOT registered — Android already sends
 * ACTION_APPWIDGET_UPDATE on boot, which Glance handles natively.
 */
class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                refreshAll(context)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        suspend fun refreshAll(context: Context) {
            val widgets: List<GlanceAppWidget> = listOf(
                TodayScheduleWidget(),
                TodayAndAssignmentsWidget(),
            )
            for (w in widgets) {
                runCatching { w.updateAll(context) }
            }
        }
    }
}
