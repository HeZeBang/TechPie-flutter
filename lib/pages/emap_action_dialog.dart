import 'package:flutter/material.dart';

Future<bool> confirmEmapAction(BuildContext context, String action, String summary) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: Text('确认$action？'),
        content: SingleChildScrollView(child: Text(summary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(action)),
        ],
      ),
    ) ??
    false;
