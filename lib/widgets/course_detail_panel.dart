import 'package:flutter/material.dart';

import '../models/course.dart';

class CourseDetailContent extends StatelessWidget {
  final Course course;
  final EdgeInsetsGeometry padding;
  final bool compact;

  /// Shown only for a session the user entered by hand — a fetched course has
  /// nothing here to edit.
  final VoidCallback? onEdit;

  const CourseDetailContent({
    super.key,
    required this.course,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
    this.compact = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleStyle = compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall;
    final detailColor = colorScheme.onSurfaceVariant;

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course.name,
            style: titleStyle?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          if (course.location.isNotEmpty)
            CourseDetailRow(
              icon: Icons.location_on_outlined,
              text: course.location,
              color: detailColor,
            ),
          CourseDetailRow(
            icon: Icons.schedule_outlined,
            text: _timeRange(),
            color: detailColor,
          ),
          CourseDetailRow(
            icon: Icons.calendar_today_outlined,
            text: _dayName(),
            color: detailColor,
          ),
          if (course.teachers != null && course.teachers!.isNotEmpty)
            CourseDetailRow(
              icon: Icons.person_outlined,
              text: course.teachers!,
              color: detailColor,
            ),
          if (course.weeksText != null && course.weeksText!.isNotEmpty)
            CourseDetailRow(
              icon: Icons.date_range_outlined,
              text: course.weeksText!,
              color: detailColor,
            ),
          if (onEdit != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _timeRange() {
    return course.timeLabel;
  }

  String _dayName() {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (course.dayOfWeek >= 1 && course.dayOfWeek <= 7) {
      return days[course.dayOfWeek - 1];
    }
    return '';
  }
}

class CourseDetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const CourseDetailRow({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
