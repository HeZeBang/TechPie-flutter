package club.geekpie.techpie.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import club.geekpie.techpie.R
import java.util.TimeZone

class TodayOverviewWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == WidgetUiHelper.ACTION_REFRESH_WIDGETS) {
            updateAll(context, AppWidgetManager.getInstance(context))
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateIds(context, manager, ids)
        WidgetRefreshScheduler.scheduleNextRefresh(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
        updateIds(context, manager, intArrayOf(appWidgetId))
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        WidgetRefreshScheduler.scheduleNextRefresh(context)
    }

    companion object {
        private const val REQUEST_CODE_SCHEDULE = 4100
        private const val REQUEST_CODE_DEADLINES = 4500

        fun updateAll(context: Context, manager: AppWidgetManager) {
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayOverviewWidgetProvider::class.java))
            if (ids.isNotEmpty()) updateIds(context, manager, ids)
        }

        private fun updateIds(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val store = WidgetSnapshotStore(context)
            val nowMillis = System.currentTimeMillis()
            val tz = TimeZone.getDefault()
            val night = WidgetUiHelper.isNightMode(context)

            val scheduleSnapshot = store.loadSchedule()
            val scheduleResolution = ScheduleWidgetResolver.resolve(
                snapshot = scheduleSnapshot,
                nowMillis = nowMillis,
                mode = ScheduleDayMode.AUTO,
                tz = tz,
            )
            val deadlineSnapshot = store.loadDeadlines()
            val upcomingDeadlines = DeadlineWidgetResolver.activeItems(deadlineSnapshot, nowMillis)

            val fallbackAccent = ContextCompat.getColor(context, R.color.widget_brand_ink)
            val urgentBar = ContextCompat.getColor(context, R.color.widget_urgency_urgent)
            val soonBar = ContextCompat.getColor(context, R.color.widget_urgency_soon)
            val normalBar = ContextCompat.getColor(context, R.color.widget_urgency_normal)
            val urgentFg = ContextCompat.getColor(context, R.color.widget_brand_ink)
            val soonFg = ContextCompat.getColor(context, R.color.widget_amber_ink)
            val normalFg = ContextCompat.getColor(context, R.color.widget_text_secondary)

            for (id in ids) {
                val (_, minHeight) = WidgetUiHelper.minDimensionsDp(manager, id)
                val isLarge = minHeight >= 200
                val views = RemoteViews(
                    context.packageName,
                    if (isLarge) {
                        R.layout.today_overview_widget_large
                    } else {
                        R.layout.today_overview_widget_medium
                    },
                )

                views.setOnClickPendingIntent(
                    R.id.overview_schedule_zone,
                    WidgetUiHelper.openUriPendingIntent(
                        context = context,
                        requestCode = REQUEST_CODE_SCHEDULE + id,
                        uriString = "techpie://schedule",
                    ),
                )
                views.setOnClickPendingIntent(
                    R.id.overview_deadline_zone,
                    WidgetUiHelper.openUriPendingIntent(
                        context = context,
                        requestCode = REQUEST_CODE_DEADLINES + id,
                        uriString = "techpie://deadlines",
                    ),
                )

                val scheduleTitle = context.getString(
                    if (scheduleResolution.isRolledOver) {
                        R.string.widget_schedule_next_day
                    } else {
                        R.string.widget_schedule_today
                    },
                )
                views.setTextViewText(R.id.overview_schedule_title, scheduleTitle)
                views.setTextViewText(R.id.overview_deadline_badge, upcomingDeadlines.size.toString())

                val courses = scheduleResolution.allDisplayCourses
                val courseRows = listOfNotNull(
                    CourseRowIds(R.id.overview_course_1, R.id.overview_course_1_accent, R.id.overview_course_1_title, R.id.overview_course_1_meta),
                    CourseRowIds(R.id.overview_course_2, R.id.overview_course_2_accent, R.id.overview_course_2_title, R.id.overview_course_2_meta),
                    if (isLarge) {
                        CourseRowIds(R.id.overview_course_3, R.id.overview_course_3_accent, R.id.overview_course_3_title, R.id.overview_course_3_meta)
                    } else {
                        null
                    },
                )
                if (courses.isEmpty()) {
                    views.setViewVisibility(R.id.overview_schedule_empty, View.VISIBLE)
                    views.setTextViewText(
                        R.id.overview_schedule_empty,
                        context.getString(
                            if (scheduleResolution.hasSnapshot) {
                                R.string.widget_schedule_no_more_classes
                            } else {
                                R.string.widget_schedule_sync_hint
                            },
                        ),
                    )
                    courseRows.forEach { views.setViewVisibility(it.container, View.GONE) }
                } else {
                    views.setViewVisibility(R.id.overview_schedule_empty, View.GONE)
                    for (i in courseRows.indices) {
                        val row = courseRows[i]
                        if (i >= courses.size) {
                            views.setViewVisibility(row.container, View.GONE)
                            continue
                        }
                        val course = courses[i]
                        val accentHex = if (night) course.colorDarkHex else course.colorLightHex
                        val accentColor = WidgetUiHelper.parseColorOrFallback(accentHex, fallbackAccent)
                        views.setViewVisibility(row.container, View.VISIBLE)
                        views.setInt(row.accent, "setBackgroundColor", accentColor)
                        views.setTextViewText(row.title, course.title)
                        val time = WidgetIso8601.formatLocalTimeHHmm(course.startAtMillis, tz)
                        val meta = listOfNotNull(time, course.location.takeIf { it.isNotEmpty() }).joinToString(" · ")
                        views.setTextViewText(row.meta, meta)
                    }
                }

                val deadlineRows = listOfNotNull(
                    DeadlineRowIds(R.id.overview_ddl_1, R.id.overview_ddl_1_bar, R.id.overview_ddl_1_title, R.id.overview_ddl_1_countdown),
                    DeadlineRowIds(R.id.overview_ddl_2, R.id.overview_ddl_2_bar, R.id.overview_ddl_2_title, R.id.overview_ddl_2_countdown),
                    if (isLarge) {
                        DeadlineRowIds(R.id.overview_ddl_3, R.id.overview_ddl_3_bar, R.id.overview_ddl_3_title, R.id.overview_ddl_3_countdown)
                    } else {
                        null
                    },
                )
                if (upcomingDeadlines.isEmpty()) {
                    views.setViewVisibility(R.id.overview_deadline_empty, View.VISIBLE)
                    views.setTextViewText(
                        R.id.overview_deadline_empty,
                        context.getString(
                            if (deadlineSnapshot == null) {
                                R.string.widget_deadlines_sync_hint
                            } else {
                                R.string.widget_deadlines_empty
                            },
                        ),
                    )
                    deadlineRows.forEach { views.setViewVisibility(it.container, View.GONE) }
                } else {
                    views.setViewVisibility(R.id.overview_deadline_empty, View.GONE)
                    for (i in deadlineRows.indices) {
                        val row = deadlineRows[i]
                        if (i >= upcomingDeadlines.size) {
                            views.setViewVisibility(row.container, View.GONE)
                            continue
                        }
                        val item = upcomingDeadlines[i]
                        val tier = DeadlineWidgetResolver.urgency(item.dueAtMillis, nowMillis)
                        val countdown = WidgetUiHelper.formatCountdownText(
                            context,
                            DeadlineWidgetResolver.countdownToken(item.dueAtMillis, nowMillis),
                        )
                        views.setViewVisibility(row.container, View.VISIBLE)
                        views.setInt(
                            row.bar,
                            "setBackgroundColor",
                            when (tier) {
                                DeadlineUrgency.URGENT -> urgentBar
                                DeadlineUrgency.SOON -> soonBar
                                DeadlineUrgency.NORMAL -> normalBar
                            },
                        )
                        views.setTextViewText(row.title, item.title)
                        views.setTextViewText(row.countdown, countdown)
                        views.setInt(
                            row.countdown,
                            "setBackgroundResource",
                            when (tier) {
                                DeadlineUrgency.URGENT -> R.drawable.widget_pill_brand
                                DeadlineUrgency.SOON -> R.drawable.widget_pill_amber
                                DeadlineUrgency.NORMAL -> R.drawable.widget_pill_muted
                            },
                        )
                        views.setTextColor(
                            row.countdown,
                            when (tier) {
                                DeadlineUrgency.URGENT -> urgentFg
                                DeadlineUrgency.SOON -> soonFg
                                DeadlineUrgency.NORMAL -> normalFg
                            },
                        )
                    }
                }

                manager.updateAppWidget(id, views)
            }
        }

        private data class CourseRowIds(
            val container: Int,
            val accent: Int,
            val title: Int,
            val meta: Int,
        )

        private data class DeadlineRowIds(
            val container: Int,
            val bar: Int,
            val title: Int,
            val countdown: Int,
        )
    }
}
