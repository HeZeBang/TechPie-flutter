package club.geekpie.techpie.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import club.geekpie.techpie.EcardPayWidgetProvider
import java.util.TimeZone
import java.util.concurrent.TimeUnit

object WidgetRefreshScheduler {
    private const val WORK_NAME = "techpie_widget_boundary_refresh"
    private const val MIN_DELAY_MILLIS = 60_000L
    private const val MAX_DELAY_MILLIS = 6L * 3_600_000L

    fun updateAllWidgets(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        EcardPayWidgetProvider.updateAll(appContext, manager)
        ScheduleWidgetProvider.updateAll(appContext, manager)
        DeadlineWidgetProvider.updateAll(appContext, manager)
        TodayOverviewWidgetProvider.updateAll(appContext, manager)
    }

    fun updateAllAndSchedule(context: Context) {
        val appContext = context.applicationContext
        updateAllWidgets(appContext)
        scheduleNextRefresh(appContext)
    }

    fun scheduleNextRefresh(context: Context) {
        val appContext = context.applicationContext
        val workManager = runCatching { WorkManager.getInstance(appContext) }.getOrNull() ?: return
        if (!hasAnyActiveWidgets(appContext)) {
            workManager.cancelUniqueWork(WORK_NAME)
            return
        }

        val nowMillis = System.currentTimeMillis()
        val tz = TimeZone.getDefault()
        val store = WidgetSnapshotStore(appContext)
        val scheduleNext = ScheduleWidgetResolver.nextRefreshMillis(
            snapshot = store.loadSchedule(),
            nowMillis = nowMillis,
            mode = store.getScheduleDayMode(nowMillis, tz),
            tz = tz,
        )
        val deadlineNext = DeadlineWidgetResolver.nextRefreshMillis(
            snapshot = store.loadDeadlines(),
            nowMillis = nowMillis,
            tz = tz,
        )
        val delayMillis = (minOf(scheduleNext, deadlineNext) - nowMillis)
            .coerceIn(MIN_DELAY_MILLIS, MAX_DELAY_MILLIS)

        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .build()
        workManager.enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    private fun hasAnyActiveWidgets(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(
            ComponentName(context, EcardPayWidgetProvider::class.java),
            ComponentName(context, ScheduleWidgetProvider::class.java),
            ComponentName(context, DeadlineWidgetProvider::class.java),
            ComponentName(context, TodayOverviewWidgetProvider::class.java),
        )
        return providers.any { manager.getAppWidgetIds(it).isNotEmpty() }
    }
}
