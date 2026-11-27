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

class ScheduleWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetUiHelper.ACTION_TOGGLE_SCHEDULE_DAY -> {
                WidgetSnapshotStore(context).toggleScheduleDayMode()
                updateAll(context, AppWidgetManager.getInstance(context))
                WidgetRefreshScheduler.scheduleNextRefresh(context)
            }
            WidgetUiHelper.ACTION_REFRESH_WIDGETS -> {
                updateAll(context, AppWidgetManager.getInstance(context))
            }
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
        private const val REQUEST_CODE_OPEN = 2100
        private const val REQUEST_CODE_TOGGLE_DAY = 2201

        fun updateAll(context: Context, manager: AppWidgetManager) {
            val ids = manager.getAppWidgetIds(ComponentName(context, ScheduleWidgetProvider::class.java))
            if (ids.isNotEmpty()) updateIds(context, manager, ids)
        }

        private fun updateIds(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val store = WidgetSnapshotStore(context)
            val nowMillis = System.currentTimeMillis()
            val tz = TimeZone.getDefault()
            val night = WidgetUiHelper.isNightMode(context)
            val fallbackAccent = ContextCompat.getColor(context, R.color.widget_brand_ink)
            val snapshot = store.loadSchedule()
            val dayMode = store.getScheduleDayMode(nowMillis, tz)
            val resolution = ScheduleWidgetResolver.resolve(snapshot, nowMillis, dayMode, tz)

            for (id in ids) {
                val (minWidth, minHeight) = WidgetUiHelper.minDimensionsDp(manager, id)
                val layoutRes = when {
                    minWidth < 220 && minHeight < 200 -> R.layout.schedule_widget_small
                    minHeight >= 200 -> R.layout.schedule_widget_large
                    else -> R.layout.schedule_widget_medium
                }
                val views = RemoteViews(context.packageName, layoutRes)
                views.setOnClickPendingIntent(
                    R.id.schedule_widget_root,
                    WidgetUiHelper.openUriPendingIntent(
                        context = context,
                        requestCode = REQUEST_CODE_OPEN + id,
                        uriString = "techpie://schedule",
                    ),
                )

                val dayLabel = context.getString(
                    when {
                        resolution.isRolledOver -> R.string.widget_schedule_next_day
                        resolution.effectiveMode == ScheduleDayMode.TOMORROW -> R.string.widget_schedule_tomorrow
                        else -> R.string.widget_schedule_today
                    },
                )
                views.setTextViewText(R.id.schedule_header_title, dayLabel)

                val weekNum = resolution.weekNumber
                if (weekNum != null && weekNum > 0) {
                    views.setViewVisibility(R.id.schedule_week_badge, View.VISIBLE)
                    views.setTextViewText(
                        R.id.schedule_week_badge,
                        context.getString(R.string.widget_schedule_week_fmt, weekNum),
                    )
                } else {
                    views.setViewVisibility(R.id.schedule_week_badge, View.GONE)
                }

                when (layoutRes) {
                    R.layout.schedule_widget_small -> bindSmall(
                        context = context,
                        views = views,
                        resolution = resolution,
                        nowMillis = nowMillis,
                        tz = tz,
                        night = night,
                        fallbackAccent = fallbackAccent,
                    )
                    R.layout.schedule_widget_medium -> bindMedium(
                        context = context,
                        views = views,
                        resolution = resolution,
                        nowMillis = nowMillis,
                        tz = tz,
                        night = night,
                        fallbackAccent = fallbackAccent,
                    )
                    R.layout.schedule_widget_large -> bindLarge(
                        context = context,
                        views = views,
                        resolution = resolution,
                        nowMillis = nowMillis,
                        tz = tz,
                        night = night,
                        fallbackAccent = fallbackAccent,
                    )
                }

                manager.updateAppWidget(id, views)
            }
        }

        private fun bindSmall(
            context: Context,
            views: RemoteViews,
            resolution: ScheduleResolution,
            nowMillis: Long,
            tz: TimeZone,
            night: Boolean,
            fallbackAccent: Int,
        ) {
            val active = resolution.inProgressCourse
            val featured = active?.course ?: resolution.allDisplayCourses.firstOrNull()
            if (featured == null) {
                views.setViewVisibility(R.id.schedule_featured_card, View.GONE)
                views.setViewVisibility(R.id.schedule_empty_state, View.VISIBLE)
                views.setTextViewText(
                    R.id.schedule_empty_state,
                    context.getString(
                        if (resolution.hasSnapshot) {
                            R.string.widget_schedule_no_more_classes
                        } else {
                            R.string.widget_schedule_sync_hint
                        },
                    ),
                )
                return
            }

            views.setViewVisibility(R.id.schedule_empty_state, View.GONE)
            views.setViewVisibility(R.id.schedule_featured_card, View.VISIBLE)

            val accentHex = if (night) featured.colorDarkHex else featured.colorLightHex
            val accentColor = WidgetUiHelper.parseColorOrFallback(accentHex, fallbackAccent)
            views.setInt(R.id.schedule_featured_accent, "setBackgroundColor", accentColor)

            views.setTextViewText(
                R.id.schedule_featured_badge,
                context.getString(
                    when {
                        active != null -> R.string.widget_schedule_in_progress
                        resolution.isRolledOver || resolution.effectiveMode == ScheduleDayMode.TOMORROW ->
                            R.string.widget_schedule_tomorrow
                        else -> R.string.widget_schedule_next_class
                    },
                ),
            )
            views.setTextViewText(R.id.schedule_featured_title, featured.title)
            val startText = WidgetIso8601.formatLocalTimeHHmm(featured.startAtMillis, tz)
            val endText = WidgetIso8601.formatLocalTimeHHmm(featured.endAtMillis, tz)
            views.setTextViewText(R.id.schedule_featured_time, "$startText-$endText")
            val location = featured.location.ifEmpty {
                WidgetUiHelper.coursePeriodText(context, featured) ?: ""
            }
            if (location.isNotEmpty()) {
                views.setViewVisibility(R.id.schedule_featured_location, View.VISIBLE)
                views.setTextViewText(R.id.schedule_featured_location, location)
            } else {
                views.setViewVisibility(R.id.schedule_featured_location, View.GONE)
            }

            if (active != null && active.course.endAtMillis > nowMillis) {
                views.setViewVisibility(R.id.schedule_featured_progress, View.VISIBLE)
                views.setProgressBar(R.id.schedule_featured_progress, 100, active.progressPercent, false)
            } else {
                views.setViewVisibility(R.id.schedule_featured_progress, View.GONE)
            }
        }

        private fun bindMedium(
            context: Context,
            views: RemoteViews,
            resolution: ScheduleResolution,
            nowMillis: Long,
            tz: TimeZone,
            night: Boolean,
            fallbackAccent: Int,
        ) {
            bindDayTogglePill(context, views, resolution)
            val rowIds = listOf(
                CourseRowIds(
                    container = R.id.schedule_row_1,
                    accent = R.id.schedule_row_1_accent,
                    title = R.id.schedule_row_1_title,
                    meta = R.id.schedule_row_1_meta,
                    time = R.id.schedule_row_1_time,
                    liveBadge = R.id.schedule_row_1_live,
                ),
                CourseRowIds(
                    container = R.id.schedule_row_2,
                    accent = R.id.schedule_row_2_accent,
                    title = R.id.schedule_row_2_title,
                    meta = R.id.schedule_row_2_meta,
                    time = R.id.schedule_row_2_time,
                    liveBadge = R.id.schedule_row_2_live,
                ),
                CourseRowIds(
                    container = R.id.schedule_row_3,
                    accent = R.id.schedule_row_3_accent,
                    title = R.id.schedule_row_3_title,
                    meta = R.id.schedule_row_3_meta,
                    time = R.id.schedule_row_3_time,
                    liveBadge = R.id.schedule_row_3_live,
                ),
            )
            bindCourseList(
                context = context,
                views = views,
                resolution = resolution,
                courses = resolution.allDisplayCourses,
                rowIds = rowIds,
                nowMillis = nowMillis,
                tz = tz,
                night = night,
                fallbackAccent = fallbackAccent,
            )
        }

        private fun bindLarge(
            context: Context,
            views: RemoteViews,
            resolution: ScheduleResolution,
            nowMillis: Long,
            tz: TimeZone,
            night: Boolean,
            fallbackAccent: Int,
        ) {
            bindDayTogglePill(context, views, resolution)
            val active = resolution.inProgressCourse
            val remaining = if (active != null) {
                resolution.upcomingCourses
            } else {
                resolution.allDisplayCourses
            }

            if (active != null && active.course.endAtMillis > nowMillis) {
                views.setViewVisibility(R.id.schedule_live_card, View.VISIBLE)
                val accentHex = if (night) active.course.colorDarkHex else active.course.colorLightHex
                val accentColor = WidgetUiHelper.parseColorOrFallback(accentHex, fallbackAccent)
                views.setInt(R.id.schedule_live_accent, "setBackgroundColor", accentColor)
                views.setTextViewText(R.id.schedule_live_title, active.course.title)
                val timeSpan = "${WidgetIso8601.formatLocalTimeHHmm(active.course.startAtMillis, tz)}-" +
                    WidgetIso8601.formatLocalTimeHHmm(active.course.endAtMillis, tz)
                val meta = listOfNotNull(
                    timeSpan,
                    active.course.location.takeIf { it.isNotEmpty() },
                    WidgetUiHelper.coursePeriodText(context, active.course),
                ).joinToString(" · ")
                views.setTextViewText(R.id.schedule_live_meta, meta)
                views.setProgressBar(R.id.schedule_live_progress, 100, active.progressPercent, false)
            } else {
                views.setViewVisibility(R.id.schedule_live_card, View.GONE)
            }

            val rowIds = listOf(
                CourseRowIds(
                    container = R.id.schedule_row_1,
                    accent = R.id.schedule_row_1_accent,
                    title = R.id.schedule_row_1_title,
                    meta = R.id.schedule_row_1_meta,
                    time = R.id.schedule_row_1_time,
                    liveBadge = R.id.schedule_row_1_live,
                ),
                CourseRowIds(
                    container = R.id.schedule_row_2,
                    accent = R.id.schedule_row_2_accent,
                    title = R.id.schedule_row_2_title,
                    meta = R.id.schedule_row_2_meta,
                    time = R.id.schedule_row_2_time,
                    liveBadge = R.id.schedule_row_2_live,
                ),
                CourseRowIds(
                    container = R.id.schedule_row_3,
                    accent = R.id.schedule_row_3_accent,
                    title = R.id.schedule_row_3_title,
                    meta = R.id.schedule_row_3_meta,
                    time = R.id.schedule_row_3_time,
                    liveBadge = R.id.schedule_row_3_live,
                ),
                CourseRowIds(
                    container = R.id.schedule_row_4,
                    accent = R.id.schedule_row_4_accent,
                    title = R.id.schedule_row_4_title,
                    meta = R.id.schedule_row_4_meta,
                    time = R.id.schedule_row_4_time,
                    liveBadge = R.id.schedule_row_4_live,
                ),
                CourseRowIds(
                    container = R.id.schedule_row_5,
                    accent = R.id.schedule_row_5_accent,
                    title = R.id.schedule_row_5_title,
                    meta = R.id.schedule_row_5_meta,
                    time = R.id.schedule_row_5_time,
                    liveBadge = R.id.schedule_row_5_live,
                ),
            )
            bindCourseList(
                context = context,
                views = views,
                resolution = resolution,
                courses = remaining,
                rowIds = rowIds,
                nowMillis = nowMillis,
                tz = tz,
                night = night,
                fallbackAccent = fallbackAccent,
                hasLiveHeader = active != null,
            )
        }

        private fun bindDayTogglePill(
            context: Context,
            views: RemoteViews,
            resolution: ScheduleResolution,
        ) {
            val pillLabel = context.getString(
                if (resolution.effectiveMode == ScheduleDayMode.TOMORROW) {
                    R.string.widget_schedule_switch_today
                } else {
                    R.string.widget_schedule_switch_tomorrow
                },
            )
            views.setTextViewText(R.id.schedule_day_toggle, pillLabel)
            views.setOnClickPendingIntent(
                R.id.schedule_day_toggle,
                WidgetUiHelper.broadcastPendingIntent(
                    context = context,
                    requestCode = REQUEST_CODE_TOGGLE_DAY,
                    receiverClass = ScheduleWidgetProvider::class.java,
                    action = WidgetUiHelper.ACTION_TOGGLE_SCHEDULE_DAY,
                ),
            )
        }

        private fun bindCourseList(
            context: Context,
            views: RemoteViews,
            resolution: ScheduleResolution,
            courses: List<ScheduleCourse>,
            rowIds: List<CourseRowIds>,
            nowMillis: Long,
            tz: TimeZone,
            night: Boolean,
            fallbackAccent: Int,
            hasLiveHeader: Boolean = false,
        ) {
            if (courses.isEmpty() && !hasLiveHeader) {
                views.setViewVisibility(R.id.schedule_empty_state, View.VISIBLE)
                views.setTextViewText(
                    R.id.schedule_empty_state,
                    context.getString(
                        if (!resolution.hasSnapshot) {
                            R.string.widget_schedule_sync_hint
                        } else if (resolution.effectiveMode == ScheduleDayMode.TOMORROW) {
                            R.string.widget_schedule_tomorrow_empty
                        } else {
                            R.string.widget_schedule_no_more_classes
                        },
                    ),
                )
            } else {
                views.setViewVisibility(R.id.schedule_empty_state, View.GONE)
            }

            val visibleCount = minOf(courses.size, rowIds.size)
            for (i in rowIds.indices) {
                val ids = rowIds[i]
                if (i >= visibleCount) {
                    views.setViewVisibility(ids.container, View.GONE)
                    continue
                }
                val course = courses[i]
                val isLive = course.startAtMillis <= nowMillis && course.endAtMillis > nowMillis
                val accentHex = if (night) course.colorDarkHex else course.colorLightHex
                val accentColor = WidgetUiHelper.parseColorOrFallback(accentHex, fallbackAccent)

                views.setViewVisibility(ids.container, View.VISIBLE)
                views.setInt(ids.accent, "setBackgroundColor", accentColor)
                views.setTextViewText(ids.title, course.title)
                val meta = listOfNotNull(
                    course.location.takeIf { it.isNotEmpty() },
                    WidgetUiHelper.coursePeriodText(context, course),
                ).joinToString(" · ")
                if (meta.isNotEmpty()) {
                    views.setViewVisibility(ids.meta, View.VISIBLE)
                    views.setTextViewText(ids.meta, meta)
                } else {
                    views.setViewVisibility(ids.meta, View.GONE)
                }
                val timeSpan = "${WidgetIso8601.formatLocalTimeHHmm(course.startAtMillis, tz)}-" +
                    WidgetIso8601.formatLocalTimeHHmm(course.endAtMillis, tz)
                views.setTextViewText(ids.time, timeSpan)
                views.setViewVisibility(ids.liveBadge, if (isLive) View.VISIBLE else View.GONE)
            }

            val overflow = courses.size - visibleCount
            if (overflow > 0) {
                views.setViewVisibility(R.id.schedule_overflow_text, View.VISIBLE)
                views.setTextViewText(
                    R.id.schedule_overflow_text,
                    context.getString(R.string.widget_more_count, overflow),
                )
            } else {
                views.setViewVisibility(R.id.schedule_overflow_text, View.GONE)
            }
        }

        private data class CourseRowIds(
            val container: Int,
            val accent: Int,
            val title: Int,
            val meta: Int,
            val time: Int,
            val liveBadge: Int,
        )
    }
}
