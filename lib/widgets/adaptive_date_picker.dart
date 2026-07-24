import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

Future<DateTime?> showAdaptiveDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
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
  return showCupertinoModalPopup<DateTime>(
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
                        child: const Text('Cancel'),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(context, selected),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: selected,
                    minimumDate: firstDate,
                    maximumDate: lastDate,
                    onDateTimeChanged: (value) => selected = value,
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
