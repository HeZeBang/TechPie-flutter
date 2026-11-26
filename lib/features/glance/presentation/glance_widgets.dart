import 'package:flutter/material.dart';

import '../domain/glance_snapshot.dart';

class GlanceMessage extends StatelessWidget {
  const GlanceMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.compact = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool compact;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 24,
          vertical: compact ? 6 : 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 20 : 30,
              color: colors.onSurfaceVariant,
            ),
            SizedBox(height: compact ? 4 : 10),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: compact ? 2 : 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10 : 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 2 : 8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class GlanceLoading extends StatelessWidget {
  const GlanceLoading({super.key, required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: compact ? 18 : 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared empty/loading/error decision for the course and deadline pages.
Widget? glanceUnavailableState(
  GlanceSnapshot snapshot, {
  required bool courses,
  required bool compact,
  VoidCallback? onRetry,
}) {
  final hasData = courses ? snapshot.hasCourses : snapshot.hasPending;
  final loading = courses ? snapshot.scheduleLoading : snapshot.assignmentsLoading;
  final error = courses ? snapshot.scheduleError : snapshot.assignmentsError;
  if (hasData) return null;

  Widget action() => TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(
          minimumSize: Size(compact ? 32 : 44, compact ? 24 : 32),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          '重试',
          style: TextStyle(fontSize: compact ? 10 : 12),
        ),
      );

  if (!snapshot.loggedIn) {
    return GlanceMessage(
      icon: Icons.login,
      title: '请先在完整 App 登录',
      subtitle: '登录后这里会显示${courses ? '今日课程' : '待办作业'}',
      compact: compact,
    );
  }
  if (loading) {
    return GlanceLoading(
      label: courses ? '正在加载课程…' : '正在加载待办…',
      compact: compact,
    );
  }
  if (error != null) {
    return GlanceMessage(
      icon: Icons.cloud_off_outlined,
      title: courses ? '课程加载失败' : '待办加载失败',
      subtitle: error,
      compact: compact,
      action: onRetry == null ? null : action(),
    );
  }
  return GlanceMessage(
    icon: courses ? Icons.free_breakfast_outlined : Icons.task_alt,
    title: courses ? '今天没有课程' : '没有待办事项',
    compact: compact,
  );
}
