import 'package:flutter/material.dart';

import '../services/desktop_home_preferences.dart';

Future<void> showDesktopHomeSettings(
  BuildContext context,
  DesktopHomePreferences preferences,
) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('首页模块'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final module in DesktopHomeModule.values) ...[
                  SwitchListTile(
                    title: Text(module.label),
                    value: preferences.isVisible(module),
                    onChanged: (value) => preferences.setVisible(module, value),
                  ),
                  if (module == DesktopHomeModule.campusCard)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('完整卡片')),
                          ButtonSegment(value: true, label: Text('精简余额')),
                        ],
                        selected: {preferences.balanceOnly},
                        onSelectionChanged: preferences.isVisible(module)
                            ? (choice) => preferences.setBalanceOnly(choice.single)
                            : null,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
