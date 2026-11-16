import 'package:flutter/material.dart';

import '../../../models/course.dart';
import '../domain/glance_snapshot.dart';
import 'glance_formatters.dart';
import 'glance_widgets.dart';

class RearCoursesPage extends StatelessWidget {
  const RearCoursesPage({
    super.key,
    required this.snapshot,
    this.onRetry,
  });

  final GlanceSnapshot snapshot;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final unavailable = glanceUnavailableState(
      snapshot,
      courses: true,
      compact: true,
      onRetry: onRetry,
    );
    if (unavailable != null) return unavailable;

    final lead = snapshot.leadCourse;
    if (lead == null) {
      return GlanceMessage(
        icon: Icons.nights_stay_outlined,
        title: '今天的课已结束',
        subtitle: '今天共 ${snapshot.courses.length} 节课',
        compact: true,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final background = lead.course.color.containerColor(scheme);
    final foreground = lead.course.color.onContainerColor(scheme);
    final rest = snapshot.activeCourses.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 7, 10, 7),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _stateLabel(lead.state),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: foreground.withValues(alpha: 0.78),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            formatGlanceCourseTime(lead.course),
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: foreground.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Flexible(
                      child: Text(
                        lead.course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lead.course.location.isEmpty
                          ? '地点待定'
                          : lead.course.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: foreground.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rest > 0 ? '之后 $rest 节' : '最后一节',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RearAssignmentsPage extends StatelessWidget {
  const RearAssignmentsPage({
    super.key,
    required this.snapshot,
    this.onRetry,
  });

  final GlanceSnapshot snapshot;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final unavailable = glanceUnavailableState(
      snapshot,
      courses: false,
      compact: true,
      onRetry: onRetry,
    );
    if (unavailable != null) return unavailable;

    final item = snapshot.pendingAssignments.first;
    final rest = snapshot.pendingAssignments.length - 1;
    final scheme = Theme.of(context).colorScheme;
    final urgency = _urgencyColor(item.assignment.due, snapshot.now, scheme);
    final course = item.assignment.course;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 7, 10, 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '待办',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: urgency,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${snapshot.pendingAssignments.length} 项',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  item.assignment.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      course.isEmpty
                          ? item.assignment.kind.label
                          : '$course · ${item.assignment.kind.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.dueLabel,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: urgency,
                    ),
                  ),
                ],
              ),
              if (rest > 0)
                Text(
                  '还有 $rest 项待办',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _stateLabel(GlanceCourseState state) => switch (state) {
      GlanceCourseState.ongoing => '正在上课',
      GlanceCourseState.soon => '即将开始',
      GlanceCourseState.upcoming => '下一节',
      GlanceCourseState.past => '已结束',
    };

Color _urgencyColor(DateTime due, DateTime now, ColorScheme scheme) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(due.year, due.month, due.day);
  final days = target.difference(today).inDays;
  if (days <= 0) return scheme.error;
  if (days == 1) return scheme.tertiary;
  return scheme.onSurfaceVariant;
}
