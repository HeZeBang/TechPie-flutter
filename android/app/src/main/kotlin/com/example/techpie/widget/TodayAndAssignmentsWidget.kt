package com.example.techpie.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.example.techpie.widget.data.Assignment
import com.example.techpie.widget.data.AssignmentsRepo
import com.example.techpie.widget.data.DisplayCourse
import com.example.techpie.widget.data.ScheduleRepo
import com.example.techpie.widget.data.TodaySchedule
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

class TodayAndAssignmentsWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val schedule = ScheduleRepo.loadToday(context)
        val pending = AssignmentsRepo.loadPending(context)
        provideContent {
            GlanceTheme(colors = WidgetTheme.providers()) {
                CombinedContent(schedule, pending)
            }
        }
    }
}

class TodayAndAssignmentsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayAndAssignmentsWidget()
}

@Composable
private fun CombinedContent(
    schedule: TodaySchedule,
    pending: List<Assignment>,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(20.dp)
            .padding(12.dp),
    ) {
        Header(schedule)
        Spacer(GlanceModifier.height(10.dp))
        Row(modifier = GlanceModifier.fillMaxSize()) {
            Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
                SectionHeader("今日课程", count = schedule.courses.size)
                Spacer(GlanceModifier.height(4.dp))
                if (schedule.courses.isEmpty()) EmptyTiny("今日无课")
                else LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                    items(schedule.courses) { c -> SimpleCourseRow(c) }
                }
            }
            Spacer(GlanceModifier.width(10.dp))
            Box(
                modifier = GlanceModifier
                    .width(1.dp)
                    .fillMaxHeight()
                    .background(GlanceTheme.colors.outline),
            ) {}
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
                SectionHeader("未完成作业", count = pending.size)
                Spacer(GlanceModifier.height(4.dp))
                if (pending.isEmpty()) EmptyTiny("暂无作业")
                else LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                    items(pending) { a -> AssignmentRow(a) }
                }
            }
        }
    }
}

@Composable
private fun Header(data: TodaySchedule) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = data.dateLabel,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            val sub = buildString {
                data.semesterLabel?.let { append(it) }
                if (data.currentWeek > 0) {
                    if (isNotEmpty()) append(" · ")
                    append("第 ").append(data.currentWeek).append(" 周")
                }
            }
            if (sub.isNotEmpty()) {
                Text(
                    text = sub,
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 12.sp,
                    ),
                )
            }
        }
        Text(
            text = "打开 App",
            modifier = GlanceModifier
                .background(GlanceTheme.colors.primary)
                .cornerRadius(14.dp)
                .padding(horizontal = 14.dp, vertical = 8.dp)
                .clickable(actionStartActivity(openAppIntent())),
            style = TextStyle(
                color = GlanceTheme.colors.onPrimary,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

@Composable
private fun SectionHeader(title: String, count: Int) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = title,
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
        Spacer(GlanceModifier.width(4.dp))
        Text(
            text = "($count)",
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 11.sp,
            ),
        )
    }
}

@Composable
private fun SimpleCourseRow(c: DisplayCourse) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = GlanceModifier
                .width(3.dp)
                .height(28.dp)
                .background(CoursePalette.accent(c.colorIndex))
                .cornerRadius(2.dp),
        ) {}
        Spacer(GlanceModifier.width(6.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = c.name,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            val meta = listOfNotNull(
                periodRange(c),
                c.classroom.takeIf { it.isNotBlank() },
            ).joinToString(" · ")
            if (meta.isNotEmpty()) {
                Text(
                    text = meta,
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 10.sp,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun AssignmentRow(a: Assignment) {
    val (relative, overdue) = relativeDue(a.dueEpochSeconds)
    val due = if (a.dueEpochSeconds > 0)
        Instant.ofEpochSecond(a.dueEpochSeconds).atZone(ZoneId.systemDefault()) else null
    val dueDateLabel = due?.let {
        "%04d-%02d-%02d %02d:%02d".format(
            it.year, it.monthValue, it.dayOfMonth, it.hour, it.minute,
        )
    }.orEmpty()
    val titleColor: ColorProvider =
        if (overdue) ColorProvider(Color(0xFFD32F2F)) else GlanceTheme.colors.onSurface
    val subColor: ColorProvider =
        if (overdue) ColorProvider(Color(0xFFD32F2F)) else GlanceTheme.colors.onSurfaceVariant

    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .clickable(actionStartActivity(rowIntent(a))),
    ) {
        Text(
            text = a.title,
            style = TextStyle(
                color = titleColor,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 2,
        )
        if (a.course.isNotBlank()) {
            Text(
                text = a.course,
                style = TextStyle(color = subColor, fontSize = 10.sp),
                maxLines = 1,
            )
        }
        if (dueDateLabel.isNotEmpty()) {
            Text(
                text = if (relative.isNotEmpty()) "$dueDateLabel · $relative" else dueDateLabel,
                style = TextStyle(color = subColor, fontSize = 10.sp),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun EmptyTiny(text: String) {
    Box(
        modifier = GlanceModifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 11.sp,
            ),
        )
    }
}

/** Open the assignment URL in a browser; fall back to opening the app. */
private fun rowIntent(a: Assignment): Intent {
    val url = a.url
    return if (!url.isNullOrBlank()) {
        Intent(Intent.ACTION_VIEW, Uri.parse(url))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    } else openAppIntent()
}

/**
 * Returns ("3天后" / "明天 18:00" / "今天 10:00" / "已过期", overdue?). Compares
 * by calendar day in the device's timezone.
 */
private fun relativeDue(epochSeconds: Long): Pair<String, Boolean> {
    if (epochSeconds <= 0) return "" to false
    val zone = ZoneId.systemDefault()
    val due = Instant.ofEpochSecond(epochSeconds).atZone(zone)
    val now = java.time.ZonedDateTime.now(zone)
    val today = LocalDate.now(zone)
    val dueDate = due.toLocalDate()
    val days = ChronoUnit.DAYS.between(today, dueDate).toInt()
    val overdue = due.isBefore(now)
    val text = when {
        overdue -> "已过期"
        days == 0 -> "今天"
        days == 1 -> "明天"
        days in 2..6 -> "${days}天后"
        else -> "${days}天后"
    }
    return text to overdue
}
