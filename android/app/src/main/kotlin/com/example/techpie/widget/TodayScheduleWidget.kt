package com.example.techpie.widget

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.compose.runtime.Composable
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.example.techpie.MainActivity
import com.example.techpie.widget.data.DisplayCourse
import com.example.techpie.widget.data.ScheduleRepo
import com.example.techpie.widget.data.TodaySchedule

class TodayScheduleWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val data = ScheduleRepo.loadToday(context)
        provideContent {
            GlanceTheme(colors = WidgetTheme.providers()) {
                ScheduleContent(data)
            }
        }
    }
}

class TodayScheduleWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayScheduleWidget()
}

@Composable
private fun ScheduleContent(data: TodaySchedule) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(20.dp)
            .padding(12.dp)
            .clickable(actionStartActivity(openAppIntent())),
    ) {
        TopBar(data)
        Spacer(GlanceModifier.height(8.dp))
        if (data.courses.isEmpty()) {
            EmptyState(text = "今日无课")
        } else {
            LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                items(data.courses) { course ->
                    CourseTile(course)
                }
            }
        }
    }
}

@Composable
private fun TopBar(data: TodaySchedule) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = data.dateLabel,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
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
                        fontSize = 11.sp,
                    ),
                )
            }
        }
        Text(
            text = "打开",
            modifier = GlanceModifier
                .background(GlanceTheme.colors.primary)
                .cornerRadius(12.dp)
                .padding(horizontal = 12.dp, vertical = 6.dp)
                .clickable(actionStartActivity(openAppIntent())),
            style = TextStyle(
                color = GlanceTheme.colors.onPrimary,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

@Composable
private fun CourseTile(c: DisplayCourse) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Left accent bar — colored by course palette index.
        Box(
            modifier = GlanceModifier
                .width(4.dp)
                .height(48.dp)
                .background(CoursePalette.accent(c.colorIndex))
                .cornerRadius(2.dp),
        ) {}
        Spacer(GlanceModifier.width(10.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = c.name,
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(2.dp))
            val meta = listOfNotNull(
                periodRange(c),
                timeRange(c),
                c.classroom.takeIf { it.isNotBlank() },
            ).joinToString(" · ")
            if (meta.isNotEmpty()) {
                Text(
                    text = meta,
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 11.sp,
                    ),
                    maxLines = 1,
                )
            }
            if (c.teachers.isNotBlank()) {
                Text(
                    text = c.teachers,
                    style = TextStyle(
                        color = GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 11.sp,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun EmptyState(text: String) {
    Box(
        modifier = GlanceModifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 14.sp,
            ),
        )
    }
}

internal fun openAppIntent(): Intent =
    Intent(Intent.ACTION_VIEW).apply {
        component = ComponentName("com.example.techpie", "com.example.techpie.MainActivity")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }

internal fun periodRange(c: DisplayCourse): String =
    if (c.startPeriod == c.endPeriod) "第${c.startPeriod}节"
    else "${c.startPeriod}-${c.endPeriod}节"

internal fun timeRange(c: DisplayCourse): String? {
    if (c.startTime.isBlank() || c.endTime.isBlank()) return null
    return "${c.startTime}-${c.endTime}"
}
