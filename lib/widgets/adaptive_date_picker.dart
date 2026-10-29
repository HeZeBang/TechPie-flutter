import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'schedule_picker_sheet.dart';

Future<DateTime?> showAdaptiveDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
}) {
  if (!isIos()) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  var selected = initialDate.isBefore(firstDate)
      ? firstDate
      : initialDate.isAfter(lastDate)
          ? lastDate
          : initialDate;
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
        minimumDate: firstDate,
        maximumDate: lastDate,
        onDateTimeChanged: (value) => selected = value,
      ),
    ),
  );
}
