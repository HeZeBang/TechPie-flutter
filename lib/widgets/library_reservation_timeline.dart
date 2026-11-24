import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/library_reservation_service.dart';

typedef LibraryTimeRange = ({int start, int end});

const _mobileWindowMinutes = 8 * 60;

class LibraryReservationTimeline extends StatelessWidget {
  const LibraryReservationTimeline({
    super.key,
    required this.availability,
    required this.room,
    this.selection,
    this.scrollOffset,
  });

  final LibraryAvailability availability;
  final LibraryRoom room;
  final LibraryTimeRange? selection;

  /// Shared number of minutes past opening. Null shows the whole day.
  final ValueNotifier<double>? scrollOffset;

  @override
  Widget build(BuildContext context) {
    final a = availability;
    return Semantics(
      container: true,
      label: '可预约时间',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (width <= 0 || a.openEnd - a.openStart < a.stepMinutes) {
            return const SizedBox.shrink();
          }
          final scroll = scrollOffset;
          final dayMinutes = a.openEnd - a.openStart;
          final span = scroll == null ? dayMinutes : math.min(dayMinutes, _mobileWindowMinutes);
          if (scroll == null || span == dayMinutes) {
            return _track(context, width, span, 0, null);
          }
          return ValueListenableBuilder<double>(
            valueListenable: scroll,
            builder: (context, offset, _) => _track(
              context,
              width,
              span,
              offset.clamp(0.0, (dayMinutes - span).toDouble()),
              scroll,
            ),
          );
        },
      ),
    );
  }

  Widget _track(
    BuildContext context,
    double width,
    int span,
    double offset,
    ValueNotifier<double>? scroll,
  ) {
    final a = availability;
    final maxOffset = (a.openEnd - a.openStart - span).toDouble();
    void move(double minutes) {
      final sharedOffset = scroll!;
      final current = sharedOffset.value.clamp(0.0, maxOffset);
      sharedOffset.value = (current + minutes).clamp(0.0, maxOffset);
    }

    return Semantics(
      label: '房间时段状态',
      onScrollLeft: scroll != null && offset < maxOffset ? () => move(span.toDouble()) : null,
      onScrollRight: scroll != null && offset > 0 ? () => move(-span.toDouble()) : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragUpdate: scroll == null
              ? null
              : (details) => move(-details.delta.dx * span / width),
          child: Column(
            children: [
              _TimeLabels(start: a.openStart + offset, span: span, width: width),
              const SizedBox(height: 2),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    availability: a,
                    room: room,
                    selection: selection,
                    colors: _TimelineColors.of(context),
                    span: span,
                    offset: offset,
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

class _TimeLabels extends StatelessWidget {
  const _TimeLabels({required this.start, required this.span, required this.width});
  final double start;
  final int span;
  final double width;

  @override
  Widget build(BuildContext context) {
    final end = start + span;
    final every = math.max(1, (span / 60 * 55 / width).ceil()) * 60;
    final labels = [
      start,
      for (var minute = (start ~/ every + 1) * every;
          minute < end;
          minute += every)
        if ((minute - start) * width / span >= 55 &&
            (end - minute) * width / span >= 55)
          minute.toDouble(),
      end,
    ];
    return SizedBox(
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final minute in labels)
            Positioned(
              left: (minute - start) / span * width -
                  (minute == start ? 0 : minute == end ? 44 : 22),
              width: 44,
              child: Text(
                '${(minute.round() ~/ 60).toString().padLeft(2, '0')}:${(minute.round() % 60).toString().padLeft(2, '0')}',
                textAlign: minute == start
                    ? TextAlign.left
                    : minute == end
                        ? TextAlign.right
                        : TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                textScaler: TextScaler.noScaling,
              ),
            ),
        ],
      ),
    );
  }
}

class LibraryReservationLegend extends StatelessWidget {
  const LibraryReservationLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = _TimelineColors.of(context);
    return Semantics(
      label: '时间状态图例',
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _LegendItem(label: '可预约', color: colors.available),
          _LegendItem(label: '已占用', color: colors.occupied),
          _LegendItem(label: '不可预约', color: colors.closed),
          _LegendItem(label: '已选择', color: colors.selected),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _TimelineColors {
  const _TimelineColors({
    required this.available,
    required this.occupied,
    required this.closed,
    required this.selected,
    required this.divider,
  });

  factory _TimelineColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _TimelineColors(
      available: dark ? const Color(0xff3f755d) : const Color(0xffb9ddc6),
      occupied: dark ? const Color(0xff61666d) : const Color(0xffc7cbd0),
      closed: dark ? scheme.surfaceContainerHighest : const Color(0xffe8e9eb),
      selected: dark ? const Color(0xffffa24a) : const Color(0xffe87518),
      divider: scheme.surface.withValues(alpha: .72),
    );
  }

  final Color available;
  final Color occupied;
  final Color closed;
  final Color selected;
  final Color divider;
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.availability,
    required this.room,
    required this.selection,
    required this.colors,
    required this.span,
    required this.offset,
  });

  final LibraryAvailability availability;
  final LibraryRoom room;
  final LibraryTimeRange? selection;
  final _TimelineColors colors;
  final int span;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (availability.openEnd - availability.openStart) ~/
        availability.stepMinutes;
    final slotWidth = size.width * availability.stepMinutes / span;
    final startIndex = (offset / availability.stepMinutes).floor();
    final endIndex = math.min(count, ((offset + span) / availability.stepMinutes).ceil());
    final leftShift = offset * size.width / span;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 12, size.width, 24),
      const Radius.circular(7),
    );
    canvas.save();
    canvas.clipRRect(track);
    final fill = Paint();
    final stripe = Paint()..color = colors.divider.withValues(alpha: .42);
    final separator = Paint()..color = colors.divider;
    canvas.drawRRect(track, fill..color = colors.closed);
    for (var i = startIndex; i < endIndex; i++) {
      final start = availability.openStart + i * availability.stepMinutes;
      final selected = selection != null &&
          start >= selection!.start &&
          start < selection!.end;
      final status = availability.statusAt(room, start);
      final color = selected
          ? colors.selected
          : switch (status) {
              LibrarySlotStatus.available => colors.available,
              LibrarySlotStatus.occupied => colors.occupied,
              LibrarySlotStatus.closed => colors.closed,
            };
      final rect = Rect.fromLTWH(i * slotWidth - leftShift, 12, slotWidth, 24);
      canvas.drawRect(rect, fill..color = color);
      if (!selected && status == LibrarySlotStatus.occupied) {
        canvas.save();
        canvas.clipRect(rect);
        for (var x = rect.left - 20; x < rect.right; x += 7) {
          canvas.drawLine(Offset(x, rect.bottom), Offset(x + 20, rect.top), stripe);
        }
        canvas.restore();
      }
      if (i > 0) {
        canvas.drawLine(
          Offset(rect.left, 15),
          Offset(rect.left, 33),
          separator,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.availability != availability ||
      oldDelegate.room != room ||
      oldDelegate.selection != selection ||
      oldDelegate.span != span ||
      oldDelegate.offset != offset ||
      oldDelegate.colors.available != colors.available ||
      oldDelegate.colors.occupied != colors.occupied ||
      oldDelegate.colors.closed != colors.closed ||
      oldDelegate.colors.selected != colors.selected ||
      oldDelegate.colors.divider != colors.divider;
}
