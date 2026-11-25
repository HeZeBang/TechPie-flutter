import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/course.dart';
import '../theme/theme.dart';
import '../utils/haptics.dart';
import '../utils/platform.dart';
import 'adaptive_feedback.dart';
import 'design_system/design_system.dart';

class CourseDetailContent extends StatelessWidget {
  final Course course;
  final EdgeInsetsGeometry padding;
  final bool compact;
  final Color? accentColor;

  /// Shown only for a session the user entered by hand — a fetched course has
  /// nothing here to edit.
  final VoidCallback? onEdit;

  const CourseDetailContent({
    super.key,
    required this.course,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 24),
    this.compact = false,
    this.accentColor,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.tpColors;
    final ios = isIos();
    final resolvedAccent = accentColor ??
        (course.source is ExamCourseSource
            ? colors.dangerRed
            : course.color.accentColor(theme.brightness));
    final (kindLabel, kindTone) = switch (course.source) {
      ExamCourseSource() => ('考试', TpBadgeTone.danger),
      CustomCourseSource() => ('自定义', TpBadgeTone.info),
      EamsCourseSource() => ('课程', TpBadgeTone.brand),
    };

    final titleStyle = TpTypography.cardTitle(colors).copyWith(
      fontSize: compact ? 18 : 20,
      height: 1.25,
      fontWeight: FontWeight.w700,
    );
    IconData glyph(IconData material, IconData cupertino) =>
        ios ? cupertino : material;

    Future<void> copyText(String text, String label) async {
      await Clipboard.setData(ClipboardData(text: text));
      unawaited(AppHaptics.play(AppHaptics.selection));
      if (!context.mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '已复制$label',
        style: AdaptiveFeedbackStyle.success,
        duration: const Duration(seconds: 2),
      );
    }

    final metadataRows = <_MetadataEntry>[
      if (course.location.isNotEmpty)
        _MetadataEntry(
          key: const ValueKey('course-detail.location'),
          icon: glyph(TpIcons.location, CupertinoIcons.placemark),
          text: course.location,
          onTap: () => unawaited(copyText(course.location, '地点')),
          trailingIcon: TpIcons.copy,
          tooltip: '复制地点',
        ),
      _MetadataEntry(
        icon: glyph(TpIcons.clock, CupertinoIcons.clock),
        text: _timeRange(),
      ),
      _MetadataEntry(
        icon: glyph(TpIcons.schedule, CupertinoIcons.calendar),
        text: _dayName(),
      ),
      if (course.teachers != null && course.teachers!.isNotEmpty)
        _MetadataEntry(
          icon: glyph(TpIcons.profile, CupertinoIcons.person),
          text: course.teachers!,
        ),
      if (course.weeksText != null && course.weeksText!.isNotEmpty)
        _MetadataEntry(
          icon: glyph(TpIcons.repeat, CupertinoIcons.repeat),
          text: course.weeksText!,
        ),
    ];

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const ValueKey('course-detail.accent-bar'),
                  width: TpTokens.accentBarWidth,
                  decoration: BoxDecoration(
                    color: resolvedAccent,
                    borderRadius: BorderRadius.circular(TpTokens.radiusBar),
                  ),
                ),
                const SizedBox(width: TpTokens.space3),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TpBadge(label: kindLabel, tone: kindTone),
                      const SizedBox(height: TpTokens.space2),
                      Tooltip(
                        message: '点击复制课程名',
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(TpTokens.radiusS),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const ValueKey('course-detail.title'),
                            onTap: () => unawaited(copyText(course.name, '课程名')),
                            hoverColor: colors.textPrimary.withValues(
                              alpha: colors.isDark ? 0.06 : 0.04,
                            ),
                            splashColor: colors.brandSoft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(course.name, style: titleStyle),
                                  ),
                                  const SizedBox(width: TpTokens.space2),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(
                                      TpIcons.copy,
                                      size: 14,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TpTokens.space4),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceSubtle.withValues(
                alpha: colors.isDark ? 0.65 : 0.72,
              ),
              borderRadius: BorderRadius.circular(TpTokens.radiusM),
              border: Border.all(
                color: colors.divider,
                width: 0.75,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < metadataRows.length; i++)
                  CourseDetailRow(
                    key: metadataRows[i].key,
                    icon: metadataRows[i].icon,
                    text: metadataRows[i].text,
                    color: colors.textSecondary,
                    onTap: metadataRows[i].onTap,
                    trailingIcon: metadataRows[i].trailingIcon,
                    tooltip: metadataRows[i].tooltip,
                    showDivider: i < metadataRows.length - 1,
                  ),
              ],
            ),
          ),
          if (onEdit != null) ...[
            const SizedBox(height: TpTokens.space3),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(TpIcons.edit, size: TpTokens.iconS),
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

class _MetadataEntry {
  const _MetadataEntry({
    this.key,
    required this.icon,
    required this.text,
    this.onTap,
    this.trailingIcon,
    this.tooltip,
  });

  final Key? key;
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final String? tooltip;
}

class CourseDetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final String? tooltip;
  final bool showDivider;

  const CourseDetailRow({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.onTap,
    this.trailingIcon,
    this.tooltip,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TpTokens.space3,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: TpTokens.iconS, color: colors.textMuted),
          ),
          const SizedBox(width: TpTokens.space3),
          Expanded(
            child: Text(
              text,
              style: TpTypography.itemTitle(colors).copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: color,
                height: 1.35,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: TpTokens.space2),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(trailingIcon, size: 14, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );

    Widget interactive = onTap == null
        ? rowContent
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              hoverColor: colors.textPrimary.withValues(
                alpha: colors.isDark ? 0.06 : 0.04,
              ),
              splashColor: colors.brandSoft,
              child: rowContent,
            ),
          );

    if (tooltip != null && onTap != null) {
      interactive = Tooltip(message: tooltip!, child: interactive);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        interactive,
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(
              left: TpTokens.space3 + TpTokens.iconS + TpTokens.space3,
              right: TpTokens.space3,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
      ],
    );
  }
}
