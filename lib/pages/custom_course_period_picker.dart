import 'package:flutter/material.dart';

import '../models/course.dart';
import '../widgets/schedule_picker_sheet.dart';

Future<(int, int)?> showCustomCoursePeriodPicker({
  required BuildContext context,
  required List<Period> periods,
  required int start,
  required int end,
}) {
  if (periods.isEmpty) return Future.value();
  var first = periods.indexWhere((period) => period.number == start);
  var last = periods.indexWhere((period) => period.number == end);
  first = first < 0 ? 0 : first;
  last = last < first ? first : last;
  var pending = (periods[first].number, periods[last].number);
  return showSchedulePickerSheet<(int, int)>(
    context: context,
    title: '选择节次',
    selection: () => pending,
    builder: (_) => _PeriodWheels(
      periods: periods,
      startIndex: first,
      endIndex: last,
      onChanged: (start, end) => pending = (start, end),
    ),
  );
}

class _PeriodWheels extends StatefulWidget {
  const _PeriodWheels({
    required this.periods,
    required this.startIndex,
    required this.endIndex,
    required this.onChanged,
  });

  final List<Period> periods;
  final int startIndex;
  final int endIndex;
  final void Function(int, int) onChanged;

  @override
  State<_PeriodWheels> createState() => _PeriodWheelsState();
}

class _PeriodWheelsState extends State<_PeriodWheels> {
  late int _start = widget.startIndex;
  late int _end = widget.endIndex;
  late final _startController = FixedExtentScrollController(initialItem: _start);
  late final _endController = FixedExtentScrollController(initialItem: _end);

  void _select(int index, bool start) {
    if (start) {
      _start = index;
      if (_end < _start) {
        _end = _start;
        _endController.jumpToItem(_end);
      }
    } else {
      _end = index;
      if (_start > _end) {
        _start = _end;
        _startController.jumpToItem(_start);
      }
    }
    widget.onChanged(widget.periods[_start].number, widget.periods[_end].number);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 228,
        child: Row(
          children: [
            for (final start in [true, false])
              Expanded(
                child: Column(
                  children: [
                    Text(start ? '开始' : '结束', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SchedulePickerWheel(
                        controller: start ? _startController : _endController,
                        itemCount: widget.periods.length,
                        labelBuilder: (i) {
                          final period = widget.periods[i];
                          return '第 ${period.number} 节  ${start ? period.startTime : period.endTime}';
                        },
                        onChanged: (i) => _select(i, start),
                        // One selection band across both wheels.
                        capStartEdge: start,
                        capEndEdge: !start,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
