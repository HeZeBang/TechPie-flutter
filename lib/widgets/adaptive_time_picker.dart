import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'schedule_picker_sheet.dart';

/// The platform's own time picker: iOS gets the Cupertino wheel in the app's
/// picker sheet, everything else the Material dialog.
Future<TimeOfDay?> showAdaptiveTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = '选择时间',
}) {
  if (!isIos()) {
    return showTimePicker(context: context, initialTime: initialTime);
  }

  var selected = initialTime;
  return showSchedulePickerSheet<TimeOfDay>(
    context: context,
    title: title,
    selection: () => selected,
    builder: (_) => SizedBox(
      height: 216,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        use24hFormat: true,
        initialDateTime: DateTime(2000, 1, 1, initialTime.hour, initialTime.minute),
        onDateTimeChanged: (value) =>
            selected = TimeOfDay(hour: value.hour, minute: value.minute),
      ),
    ),
  );
}
