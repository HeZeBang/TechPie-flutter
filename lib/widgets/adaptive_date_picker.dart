import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'adaptive_segmented_control.dart';
import 'schedule_picker_sheet.dart';

DateTime _clampDay(DateTime value, DateTime firstDay, DateTime lastDay) {
  final day = DateUtils.dateOnly(value);
  if (day.isBefore(firstDay)) return firstDay;
  if (day.isAfter(lastDay)) return lastDay;
  return day;
}

String _formatIsoDay(DateTime day) {
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '${day.year}-$m-$d';
}

Future<DateTime?> showAdaptiveDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
}) {
  final firstDay = DateUtils.dateOnly(firstDate);
  final rawLastDay = DateUtils.dateOnly(lastDate);
  final lastDay = rawLastDay.isBefore(firstDay) ? firstDay : rawLastDay;
  final initialDay = _clampDay(initialDate, firstDay, lastDay);

  if (usesMacOsNativeControls()) {
    var selected = initialDay;
    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = context.tpColors;
          return Dialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TpTokens.radiusL),
              side: BorderSide(color: colors.divider),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.space5,
                      TpTokens.space4,
                      TpTokens.space5,
                      TpTokens.space3,
                    ),
                    child: Text(title, style: TpTypography.cardTitle(colors)),
                  ),
                  Divider(height: 1, color: colors.divider),
                  CalendarDatePicker(
                    initialDate: selected,
                    firstDate: firstDay,
                    lastDate: lastDay,
                    onDateChanged: (value) =>
                        setDialogState(() => selected = value),
                  ),
                  Divider(height: 1, color: colors.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.space4,
                      vertical: TpTokens.space3,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: TpTokens.space2),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, selected),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  if (!isIos()) {
    return showDatePicker(
      context: context,
      initialDate: initialDay,
      firstDate: firstDay,
      lastDate: lastDay,
      helpText: title,
    );
  }

  var selected = initialDay;
  // The same sheet as the app's other pickers, rather than a bare popup with
  // its own (English) buttons.
  return showSchedulePickerSheet<DateTime>(
    context: context,
    title: title,
    selection: () => selected,
    builder: (_) => SizedBox(
      height: 216,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: selected,
        minimumDate: firstDay,
        maximumDate: lastDay,
        onDateTimeChanged: (value) => selected = value,
      ),
    ),
  );
}

Future<DateTimeRange?> showAdaptiveDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String title = '选择日期范围',
  bool useRootNavigator = true,
  String? saveText,
}) {
  final firstDay = DateUtils.dateOnly(firstDate);
  final rawLastDay = DateUtils.dateOnly(lastDate);
  final lastDay = rawLastDay.isBefore(firstDay) ? firstDay : rawLastDay;
  final fallbackDay = _clampDay(DateTime.now(), firstDay, lastDay);
  var start = _clampDay(
    initialDateRange?.start ?? fallbackDay,
    firstDay,
    lastDay,
  );
  var end = _clampDay(
    initialDateRange?.end ?? start,
    firstDay,
    lastDay,
  );
  if (end.isBefore(start)) end = start;

  if (isIos()) {
    var editingStart = true;
    return showSchedulePickerSheet<DateTimeRange>(
      context: context,
      title: title,
      isScrollControlled: true,
      selection: () => DateTimeRange(start: start, end: end),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  AdaptiveSegmentedControl(
                    value: editingStart ? 0 : 1,
                    segments: const ['开始日期', '结束日期'],
                    onChanged: (index) =>
                        setSheetState(() => editingStart = index == 0),
                  ),
                  const SizedBox(height: TpTokens.space2),
                  Text(
                    '${_formatIsoDay(start)} 至 ${_formatIsoDay(end)}',
                    style: TpTypography.itemMeta(context.tpColors),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 216,
              child: CupertinoDatePicker(
                key: ValueKey(editingStart),
                mode: CupertinoDatePickerMode.date,
                initialDateTime: editingStart ? start : end,
                minimumDate: firstDay,
                maximumDate: lastDay,
                onDateTimeChanged: (value) {
                  setSheetState(() {
                    if (editingStart) {
                      start = value;
                      if (end.isBefore(start)) end = start;
                    } else {
                      end = value;
                      if (start.isAfter(end)) start = end;
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (usesMacOsNativeControls()) {
    var editingStart = true;
    return showDialog<DateTimeRange>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = context.tpColors;
          return Dialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TpTokens.radiusL),
              side: BorderSide(color: colors.divider),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.space5,
                      TpTokens.space4,
                      TpTokens.space5,
                      TpTokens.space3,
                    ),
                    child: Text(title, style: TpTypography.cardTitle(colors)),
                  ),
                  Divider(height: 1, color: colors.divider),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.space4,
                      TpTokens.space3,
                      TpTokens.space4,
                      TpTokens.space2,
                    ),
                    child: Column(
                      children: [
                        AdaptiveSegmentedControl(
                          value: editingStart ? 0 : 1,
                          segments: const ['开始日期', '结束日期'],
                          onChanged: (index) =>
                              setDialogState(() => editingStart = index == 0),
                        ),
                        const SizedBox(height: TpTokens.space2),
                        Text(
                          '${_formatIsoDay(start)} 至 ${_formatIsoDay(end)}',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ],
                    ),
                  ),
                  CalendarDatePicker(
                    key: ValueKey(editingStart),
                    initialDate: editingStart ? start : end,
                    firstDate: firstDay,
                    lastDate: lastDay,
                    onDateChanged: (value) {
                      setDialogState(() {
                        if (editingStart) {
                          start = value;
                          if (end.isBefore(start)) end = start;
                        } else {
                          end = value;
                          if (start.isAfter(end)) start = end;
                        }
                      });
                    },
                  ),
                  Divider(height: 1, color: colors.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.space4,
                      vertical: TpTokens.space3,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: TpTokens.space2),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            DateTimeRange(start: start, end: end),
                          ),
                          child: Text(saveText ?? '确定'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  return showDateRangePicker(
    context: context,
    firstDate: firstDay,
    lastDate: lastDay,
    initialDateRange: initialDateRange,
    helpText: title,
    saveText: saveText,
    useRootNavigator: useRootNavigator,
  );
}
