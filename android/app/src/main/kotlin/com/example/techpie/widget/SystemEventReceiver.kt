package com.example.techpie.widget

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

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
        refreshAll(context)
    }

    companion object {
        /**
         * Fires an explicit ACTION_APPWIDGET_UPDATE to each receiver, scoped to
         * the appWidgetIds that actually belong to that receiver. We deliberately
         * avoid `GlanceAppWidget.updateAll(context)` — when multiple distinct
         * GlanceAppWidget classes coexist in one app, calling updateAll on each
         * has been observed to render one widget's layout into another widget's
         * slot (the last `updateAll` wins). Going through AppWidgetManager +
         * ComponentName-targeted broadcasts is bulletproof: the system only
         * delivers each broadcast to its own provider, which uses its own
         * `glanceAppWidget` field — no class mix-up possible.
         */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            sendUpdate(context, manager, TodayScheduleWidgetReceiver::class.java)
            sendUpdate(context, manager, TodayAndAssignmentsWidgetReceiver::class.java)
        }

        private fun sendUpdate(
            context: Context,
            manager: AppWidgetManager,
            receiver: Class<out BroadcastReceiver>,
        ) {
            val ids = manager.getAppWidgetIds(ComponentName(context, receiver))
            if (ids == null || ids.isEmpty()) return
            val intent = Intent(context, receiver).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}
