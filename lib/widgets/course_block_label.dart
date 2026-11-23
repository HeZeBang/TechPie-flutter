import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The text inside a timetable course block: name, optional custom time,
/// teachers, and the location pinned to the bottom.
///
/// The block's height is fixed by the periods it spans, so the lines are
/// budgeted against that height rather than given fixed shares. The old
/// layout handed the name 70% of the block, the location 20%, and the
/// teachers two lines on top — more than 100% whenever all three were long
/// enough to use their share (a long English name, a teacher, a location
/// that wraps in a narrow column), and it counted lines at a fixed 14.4px
/// that a larger system text size outgrows. Each part's line count here
/// comes from its measured line height at the current text scale, so the
/// parts add up to no more than the block.
class CourseBlockLabel extends StatelessWidget {
  const CourseBlockLabel({
    super.key,
    required this.name,
    required this.color,
    this.time,
    this.teachers,
    this.location,
  });

  final String name;
  final Color color;

  /// Shown under the name for a course with its own time (`08:15–09:55`).
  final String? time;
  final String? teachers;
  final String? location;

  static const double _padding = 4;
  static const double _teacherGap = 4;
  static const double _timeGap = 2;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    final nameStyle = base.merge(
      textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: 12,
        height: 1.2,
      ),
    );
    final teacherStyle = base.merge(
      textTheme.labelSmall?.copyWith(color: color, fontSize: 12, height: 1.2),
    );
    final timeStyle = base.merge(
      textTheme.labelSmall?.copyWith(color: color, fontSize: 9, height: 1.1),
    );
    final locationStyle = base.merge(
      textTheme.labelSmall?.copyWith(color: color, fontSize: 10, height: 1.2),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(0.0, constraints.maxWidth - _padding * 2);
        final height = math.max(0.0, constraints.maxHeight - _padding * 2);

        _Measured measure(String text, TextStyle style, int maxLines) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: width);
          final lineHeight = painter.preferredLineHeight;
          final lines = painter.computeLineMetrics().length;
          painter.dispose();
          return _Measured(lineHeight, math.max(1, lines));
        }

        final teachersText = teachers?.trim() ?? '';
        final locationText = location?.trim() ?? '';
        final timeText = time?.trim() ?? '';

        final nameM = measure(name, nameStyle, 20);
        var remaining = height;

        // The custom time comes right after the first line of the name: it is
        // what tells two custom courses in one slot apart. Dropped only when
        // the block cannot hold both.
        final timeCandidate = timeText.isEmpty ? null : measure(timeText, timeStyle, 1);
        final timeM = timeCandidate != null &&
                height >= nameM.lineHeight + _timeGap + timeCandidate.lineHeight
            ? timeCandidate
            : null;
        if (timeM != null) remaining -= _timeGap + timeM.lineHeight;

        // One line of name always; it clips itself if even that is too much.
        remaining -= nameM.lineHeight;

        // Then one line each of location and teachers, as the old thresholds
        // allowed (location from 42px, teachers from 48px), when they fit.
        final locM =
            locationText.isEmpty || height < 42 ? null : measure(locationText, locationStyle, 5);
        var locLines = 0;
        if (locM != null && remaining >= locM.lineHeight) {
          locLines = 1;
          remaining -= locM.lineHeight;
        }

        final teacherM =
            teachersText.isEmpty || height < 48 ? null : measure(teachersText, teacherStyle, 2);
        var teacherLines = 0;
        if (teacherM != null && remaining >= _teacherGap + teacherM.lineHeight) {
          teacherLines = 1;
          remaining -= _teacherGap + teacherM.lineHeight;
        }

        // What is left goes to the name first, then a second teacher line,
        // then more of the location.
        final int nameExtra = math.min(
          nameM.lines - 1,
          (remaining / nameM.lineHeight).floor(),
        );
        final int nameLines = 1 + math.max(0, nameExtra);
        remaining -= (nameLines - 1) * nameM.lineHeight;

        if (teacherLines == 1 && teacherM!.lines > 1 && remaining >= teacherM.lineHeight) {
          teacherLines = 2;
          remaining -= teacherM.lineHeight;
        }

        if (locLines == 1 && locM!.lines > 1) {
          final int extra = math.min(
            locM.lines - 1,
            (remaining / locM.lineHeight).floor(),
          );
          locLines += math.max(0, extra);
        }

        final nameMaxHeight = math.max(
          0.0,
          height - (timeM == null ? 0 : _timeGap + timeM.lineHeight),
        );

        return Padding(
          padding: const EdgeInsets.all(_padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: nameMaxHeight),
                child: Text(
                  name,
                  style: nameStyle,
                  maxLines: nameLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timeM != null) ...[
                const SizedBox(height: _timeGap),
                Text(
                  timeText,
                  style: timeStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (teacherLines > 0) ...[
                const SizedBox(height: _teacherGap),
                Text(
                  teachersText,
                  style: teacherStyle,
                  maxLines: teacherLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (locLines > 0) ...[
                const Spacer(),
                Text(
                  locationText,
                  style: locationStyle,
                  maxLines: locLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Measured {
  const _Measured(this.lineHeight, this.lines);

  final double lineHeight;
  final int lines;
}
