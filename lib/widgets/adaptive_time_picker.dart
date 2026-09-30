import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

/// The platform's own time picker: iOS gets the Cupertino wheel, everything
/// else the Material dialog.
Future<TimeOfDay?> showAdaptiveTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  if (!isIos()) {
    return showTimePicker(context: context, initialTime: initialTime);
  }

  var selected = initialTime;
  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (context) => CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: ColoredBox(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context, selected),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: DateTime(
                      2000,
                      1,
                      1,
                      initialTime.hour,
                      initialTime.minute,
                    ),
                    onDateTimeChanged: (value) => selected = TimeOfDay(
                      hour: value.hour,
                      minute: value.minute,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
