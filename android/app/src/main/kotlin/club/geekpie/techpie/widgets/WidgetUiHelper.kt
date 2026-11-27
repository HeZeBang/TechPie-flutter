package club.geekpie.techpie.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.LocaleList
import club.geekpie.techpie.MainActivity
import club.geekpie.techpie.R
import java.util.Locale

object WidgetUiHelper {
    const val ACTION_REFRESH_WIDGETS = "club.geekpie.techpie.widgets.ACTION_REFRESH_WIDGETS"
    const val ACTION_TOGGLE_ECARD_MASK = "club.geekpie.techpie.widgets.ACTION_TOGGLE_ECARD_MASK"
    const val ACTION_TOGGLE_SCHEDULE_DAY = "club.geekpie.techpie.widgets.ACTION_TOGGLE_SCHEDULE_DAY"

    fun isNightMode(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    fun currentLocale(context: Context): Locale {
        val config = context.resources.configuration
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val list: LocaleList = config.locales
            if (!list.isEmpty) list[0] else Locale.getDefault()
        } else {
            @Suppress("DEPRECATION")
            config.locale ?: Locale.getDefault()
        }
    }

    fun parseColorOrFallback(hex: String?, fallbackColor: Int): Int {
        val normalized = hex?.trim().orEmpty()
        if (normalized.isEmpty()) return fallbackColor
        return try {
            Color.parseColor(normalized)
        } catch (_: IllegalArgumentException) {
            fallbackColor
        }
    }

    fun minDimensionsDp(manager: AppWidgetManager, widgetId: Int): Pair<Int, Int> {
        val opts = manager.getAppWidgetOptions(widgetId)
        val width = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 160)
        val height = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        return width to height
    }

    fun openUriPendingIntent(
        context: Context,
        requestCode: Int,
        uriString: String,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(uriString)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
    }

    fun broadcastPendingIntent(
        context: Context,
        requestCode: Int,
        receiverClass: Class<*>,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, receiverClass).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
    }

    fun formatCountdownText(
        context: Context,
        token: DeadlineWidgetResolver.CountdownToken,
    ): String = when (token) {
        is DeadlineWidgetResolver.CountdownToken.DueSoon ->
            context.getString(R.string.widget_due_soon)
        is DeadlineWidgetResolver.CountdownToken.Hours ->
            context.getString(R.string.widget_countdown_hours, token.hours)
        is DeadlineWidgetResolver.CountdownToken.DaysHours ->
            context.getString(R.string.widget_countdown_days_hours, token.days, token.hours)
        is DeadlineWidgetResolver.CountdownToken.Days ->
            context.getString(R.string.widget_countdown_days, token.days)
    }

    fun coursePeriodText(context: Context, course: ScheduleCourse): String? {
        val label = course.periodLabel?.trim()
        if (!label.isNullOrEmpty()) {
            return context.getString(R.string.widget_schedule_period_fmt, label)
        }
        val start = course.startPeriod
        val end = course.endPeriod
        if (start != null && end != null) {
            val range = if (start == end) "$start" else "$start-$end"
            return context.getString(R.string.widget_schedule_period_fmt, range)
        }
        return null
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
}
