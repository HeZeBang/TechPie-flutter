import 'package:flutter/material.dart';

import '../../../models/course.dart';
import '../domain/glance_snapshot.dart';
import 'glance_formatters.dart';
import 'glance_widgets.dart';

/// Cover pages are designed for the MIX Flip panel: 506 x 439 dp, wider than
/// it is tall. Each page splits into a leading card and a vertical queue so the
/// extra width carries information instead of stretching a single column.
class CoverCoursesPage extends StatelessWidget {
  const CoverCoursesPage({
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
      compact: false,
      onRetry: onRetry,
    );
    if (unavailable != null) return unavailable;

    final lead = snapshot.leadCourse;
    if (lead == null) {
      return GlanceMessage(
        icon: Icons.nights_stay_outlined,
        title: '今天的课已结束',
        subtitle: '今天共 ${snapshot.courses.length} 节课',
      );
    }

    final rest = <GlanceCourse>[];
    var skippedLead = false;
    for (final course in snapshot.activeCourses) {
      if (!skippedLead && identical(course, lead)) {
        skippedLead = true;
        continue;
      }
      rest.add(course);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _LeadCourseCard(
              course: lead,
              totalCourses: snapshot.courses.length,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _CourseQueue(courses: rest),
          ),
        ],
      ),
    );
  }
}

class _LeadCourseCard extends StatelessWidget {
  const _LeadCourseCard({
    required this.course,
    required this.totalCourses,
  });

  final GlanceCourse course;
  final int totalCourses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = course.course.color.containerColor(scheme);
    final foreground = course.course.color.onContainerColor(scheme);
    final location =
        course.course.location.isEmpty ? '地点待定' : course.course.location;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatePill(label: _stateLabel(course.state), color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatGlanceCourseTime(course.course),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.course.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 25,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: foreground.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: foreground.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 17,
            thickness: 1,
            color: foreground.withValues(alpha: 0.12),
          ),
          Text(
            '今天共 $totalCourses 节课',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: foreground.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CourseQueue extends StatelessWidget {
  const _CourseQueue({required this.courses});

  final List<GlanceCourse> courses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = courses.take(4).toList();
    final hidden = courses.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '之后',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${courses.length} 节',
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    '之后没有课了',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) =>
                      _CourseQueueRow(course: shown[index]),
                ),
        ),
        if (hidden > 0) ...[
          const SizedBox(height: 4),
          Text(
            '还有 $hidden 节课',
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CourseQueueRow extends StatelessWidget {
  const _CourseQueueRow({required this.course});

  final GlanceCourse course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 10, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: course.course.color.containerColor(scheme),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    course.course.startTime,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    course.course.endTime,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.course.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                if (course.course.location.isNotEmpty)
                  Text(
                    course.course.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CoverAssignmentsPage extends StatelessWidget {
  const CoverAssignmentsPage({
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
      compact: false,
      onRetry: onRetry,
    );
    if (unavailable != null) return unavailable;

    final items = snapshot.pendingAssignments;
    final lead = items.first;
    final rest = items.skip(1).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: _LeadAssignmentCard(
              item: lead,
              now: snapshot.now,
              total: items.length,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _AssignmentQueue(
              items: rest,
              now: snapshot.now,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadAssignmentCard extends StatelessWidget {
  const _LeadAssignmentCard({
    required this.item,
    required this.now,
    required this.total,
  });

  final GlanceAssignment item;
  final DateTime now;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgency = _urgencyColor(item.assignment.due, now, scheme);
    final course = item.assignment.course;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 4, child: ColoredBox(color: urgency)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: urgency.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '最紧急',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: urgency,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '共 $total 项',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.assignment.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              course.isEmpty
                                  ? item.assignment.kind.label
                                  : '$course · ${item.assignment.kind.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(
                      height: 17,
                      thickness: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    Row(
                      children: [
                        Text(
                          '截止',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.dueLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: urgency,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentQueue extends StatelessWidget {
  const _AssignmentQueue({required this.items, required this.now});

  final List<GlanceAssignment> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = items.take(3).toList();
    final hidden = items.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '后续',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              '${items.length} 项',
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    '没有更多待办',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) => _AssignmentQueueRow(
                    item: shown[index],
                    now: now,
                  ),
                ),
        ),
        if (hidden > 0) ...[
          const SizedBox(height: 4),
          Text(
            '还有 $hidden 项',
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _AssignmentQueueRow extends StatelessWidget {
  const _AssignmentQueueRow({
    required this.item,
    required this.now,
  });

  final GlanceAssignment item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgency = _urgencyColor(item.assignment.due, now, scheme);
    final course = item.assignment.course;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: urgency,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.assignment.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
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
                const SizedBox(height: 2),
                Text(
                  item.dueLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: urgency,
                  ),
                ),
              ],
            ),
          ),
        ],
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
