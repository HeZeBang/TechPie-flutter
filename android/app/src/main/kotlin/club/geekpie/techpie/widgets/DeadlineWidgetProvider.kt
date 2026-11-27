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

class DeadlineWidgetProvider : AppWidgetProvider() {
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
        private const val REQUEST_CODE_OPEN = 3100

        fun updateAll(context: Context, manager: AppWidgetManager) {
            val ids = manager.getAppWidgetIds(ComponentName(context, DeadlineWidgetProvider::class.java))
            if (ids.isNotEmpty()) updateIds(context, manager, ids)
        }

        private fun updateIds(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val store = WidgetSnapshotStore(context)
            val snapshot = store.loadDeadlines()
            val nowMillis = System.currentTimeMillis()
            val tz = TimeZone.getDefault()
            val locale = WidgetUiHelper.currentLocale(context)
            val upcoming = DeadlineWidgetResolver.activeItems(snapshot, nowMillis)

            val urgentBar = ContextCompat.getColor(context, R.color.widget_urgency_urgent)
            val soonBar = ContextCompat.getColor(context, R.color.widget_urgency_soon)
            val normalBar = ContextCompat.getColor(context, R.color.widget_urgency_normal)
            val urgentFg = ContextCompat.getColor(context, R.color.widget_brand_ink)
            val soonFg = ContextCompat.getColor(context, R.color.widget_amber_ink)
            val normalFg = ContextCompat.getColor(context, R.color.widget_text_secondary)

            for (id in ids) {
                val (minWidth, minHeight) = WidgetUiHelper.minDimensionsDp(manager, id)
                val layoutRes = when {
                    minWidth < 220 && minHeight < 200 -> R.layout.deadline_widget_small
                    minHeight >= 200 -> R.layout.deadline_widget_large
                    else -> R.layout.deadline_widget_medium
                }
                val views = RemoteViews(context.packageName, layoutRes)
                views.setOnClickPendingIntent(
                    R.id.deadline_widget_root,
                    WidgetUiHelper.openUriPendingIntent(
                        context = context,
                        requestCode = REQUEST_CODE_OPEN + id,
                        uriString = "techpie://deadlines",
                    ),
                )
                views.setTextViewText(R.id.deadline_count_badge, upcoming.size.toString())

                if (upcoming.isEmpty()) {
                    views.setViewVisibility(R.id.deadline_empty_state, View.VISIBLE)
                    views.setTextViewText(
                        R.id.deadline_empty_state,
                        context.getString(
                            if (snapshot == null) {
                                R.string.widget_deadlines_sync_hint
                            } else {
                                R.string.widget_deadlines_empty
                            },
                        ),
                    )
                    if (layoutRes == R.layout.deadline_widget_small) {
                        views.setViewVisibility(R.id.deadline_featured_card, View.GONE)
                    } else {
                        hideRows(views, rowIdsFor(layoutRes))
                        views.setViewVisibility(R.id.deadline_overflow_text, View.GONE)
                    }
                    manager.updateAppWidget(id, views)
                    continue
                }

                views.setViewVisibility(R.id.deadline_empty_state, View.GONE)

                if (layoutRes == R.layout.deadline_widget_small) {
                    val item = upcoming.first()
                    val tier = DeadlineWidgetResolver.urgency(item.dueAtMillis, nowMillis)
                    val countdown = WidgetUiHelper.formatCountdownText(
                        context,
                        DeadlineWidgetResolver.countdownToken(item.dueAtMillis, nowMillis),
                    )
                    val dueDate = DeadlineWidgetResolver.formatAbsoluteDate(item.dueAtMillis, nowMillis, tz, locale)
                    views.setViewVisibility(R.id.deadline_featured_card, View.VISIBLE)
                    views.setInt(
                        R.id.deadline_featured_bar,
                        "setBackgroundColor",
                        barColor(tier, urgentBar, soonBar, normalBar),
                    )
                    views.setTextViewText(R.id.deadline_featured_title, item.title)
                    views.setTextViewText(
                        R.id.deadline_featured_subtitle,
                        item.subtitle.ifEmpty { kindLabel(context, item.kind) },
                    )
                    views.setTextViewText(R.id.deadline_featured_countdown, countdown)
                    views.setInt(
                        R.id.deadline_featured_countdown,
                        "setBackgroundResource",
                        pillBg(tier),
                    )
                    views.setTextColor(
                        R.id.deadline_featured_countdown,
                        pillFg(tier, urgentFg, soonFg, normalFg),
                    )
                    views.setTextViewText(R.id.deadline_featured_date, dueDate)
                } else {
                    val rowIds = rowIdsFor(layoutRes)
                    val visibleCount = minOf(upcoming.size, rowIds.size)
                    for (i in rowIds.indices) {
                        val r = rowIds[i]
                        if (i >= visibleCount) {
                            views.setViewVisibility(r.container, View.GONE)
                            continue
                        }
                        val item = upcoming[i]
                        val tier = DeadlineWidgetResolver.urgency(item.dueAtMillis, nowMillis)
                        val countdown = WidgetUiHelper.formatCountdownText(
                            context,
                            DeadlineWidgetResolver.countdownToken(item.dueAtMillis, nowMillis),
                        )
                        val dueDate = DeadlineWidgetResolver.formatAbsoluteDate(
                            item.dueAtMillis,
                            nowMillis,
                            tz,
                            locale,
                        )
                        val meta = listOfNotNull(
                            item.subtitle.takeIf { it.isNotEmpty() },
                            dueDate,
                        ).joinToString(" · ")

                        views.setViewVisibility(r.container, View.VISIBLE)
                        views.setInt(r.bar, "setBackgroundColor", barColor(tier, urgentBar, soonBar, normalBar))
                        views.setTextViewText(r.title, item.title)
                        views.setTextViewText(r.subtitle, meta)
                        views.setTextViewText(r.countdown, countdown)
                        views.setInt(r.countdown, "setBackgroundResource", pillBg(tier))
                        views.setTextColor(r.countdown, pillFg(tier, urgentFg, soonFg, normalFg))
                    }
                    val overflow = upcoming.size - visibleCount
                    if (overflow > 0) {
                        views.setViewVisibility(R.id.deadline_overflow_text, View.VISIBLE)
                        views.setTextViewText(
                            R.id.deadline_overflow_text,
                            context.getString(R.string.widget_more_count, overflow),
                        )
                    } else {
                        views.setViewVisibility(R.id.deadline_overflow_text, View.GONE)
                    }
                }

                manager.updateAppWidget(id, views)
            }
        }

        private fun hideRows(views: RemoteViews, rowIds: List<DeadlineRowIds>) {
            for (r in rowIds) {
                views.setViewVisibility(r.container, View.GONE)
            }
        }

        private fun rowIdsFor(layoutRes: Int): List<DeadlineRowIds> {
            val base = mutableListOf(
                DeadlineRowIds(
                    container = R.id.deadline_row_1,
                    bar = R.id.deadline_row_1_bar,
                    title = R.id.deadline_row_1_title,
                    subtitle = R.id.deadline_row_1_subtitle,
                    countdown = R.id.deadline_row_1_countdown,
                ),
                DeadlineRowIds(
                    container = R.id.deadline_row_2,
                    bar = R.id.deadline_row_2_bar,
                    title = R.id.deadline_row_2_title,
                    subtitle = R.id.deadline_row_2_subtitle,
                    countdown = R.id.deadline_row_2_countdown,
                ),
                DeadlineRowIds(
                    container = R.id.deadline_row_3,
                    bar = R.id.deadline_row_3_bar,
                    title = R.id.deadline_row_3_title,
                    subtitle = R.id.deadline_row_3_subtitle,
                    countdown = R.id.deadline_row_3_countdown,
                ),
            )
            if (layoutRes == R.layout.deadline_widget_large) {
                base.addAll(
                    listOf(
                        DeadlineRowIds(
                            container = R.id.deadline_row_4,
                            bar = R.id.deadline_row_4_bar,
                            title = R.id.deadline_row_4_title,
                            subtitle = R.id.deadline_row_4_subtitle,
                            countdown = R.id.deadline_row_4_countdown,
                        ),
                        DeadlineRowIds(
                            container = R.id.deadline_row_5,
                            bar = R.id.deadline_row_5_bar,
                            title = R.id.deadline_row_5_title,
                            subtitle = R.id.deadline_row_5_subtitle,
                            countdown = R.id.deadline_row_5_countdown,
                        ),
                        DeadlineRowIds(
                            container = R.id.deadline_row_6,
                            bar = R.id.deadline_row_6_bar,
                            title = R.id.deadline_row_6_title,
                            subtitle = R.id.deadline_row_6_subtitle,
                            countdown = R.id.deadline_row_6_countdown,
                        ),
                    ),
                )
            }
            return base
        }

        private fun barColor(tier: DeadlineUrgency, urgent: Int, soon: Int, normal: Int): Int =
            when (tier) {
                DeadlineUrgency.URGENT -> urgent
                DeadlineUrgency.SOON -> soon
                DeadlineUrgency.NORMAL -> normal
            }

        private fun pillBg(tier: DeadlineUrgency): Int = when (tier) {
            DeadlineUrgency.URGENT -> R.drawable.widget_pill_brand
            DeadlineUrgency.SOON -> R.drawable.widget_pill_amber
            DeadlineUrgency.NORMAL -> R.drawable.widget_pill_muted
        }

        private fun pillFg(tier: DeadlineUrgency, urgent: Int, soon: Int, normal: Int): Int =
            when (tier) {
                DeadlineUrgency.URGENT -> urgent
                DeadlineUrgency.SOON -> soon
                DeadlineUrgency.NORMAL -> normal
            }

        private fun kindLabel(context: Context, kind: DeadlineKind): String =
            context.getString(
                if (kind == DeadlineKind.EXAM) {
                    R.string.widget_deadline_kind_exam
                } else {
                    R.string.widget_deadline_kind_assignment
                },
            )

        private data class DeadlineRowIds(
            val container: Int,
            val bar: Int,
            val title: Int,
            val subtitle: Int,
            val countdown: Int,
        )
    }
}
