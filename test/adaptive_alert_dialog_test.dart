import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/adaptive_alert_dialog.dart';

void main() {
  const channel = MethodChannel('cn_alert');
  tearDown(() {
    debugForceMacosNativeUiModals = false;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final fails in [false, true]) {
    testWidgets('native alert maps actions and handles failure=$fails', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? request;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        if (fails) throw PlatformException(code: 'unavailable');
        return {'index': 1};
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdaptiveAlertDialog<String>(
                  context: context,
                  title: 'Remove account?',
                  message: 'This cannot be undone.',
                  actions: const [
                    AdaptiveAlertAction(label: ' Cancel ', value: 'cancel', isDefault: true),
                    AdaptiveAlertAction(
                      label: 'Remove',
                      value: 'remove',
                      isDestructive: true,
                    ),
                  ],
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(result, fails ? null : 'remove');
      expect(request?.method, 'show');
      final args = request!.arguments as Map;
      expect((args['actions'] as List).first['label'], 'Cancel');
      expect((args['actions'] as List).first['preferred'], true);
      expect((args['actions'] as List).last['style'], 'destructive');
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('macOS alert dispatches to NSAlert channel and normalizes cancel', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    debugForceMacosNativeUiModals = true;
    try {
      const macChannel = MethodChannel('techpie/macos_native_ui');
      MethodCall? request;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        macChannel,
        (call) async {
          request = call;
          return <String, Object?>{'index': 1};
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          macChannel,
          null,
        ),
      );

      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdaptiveAlertDialog<String>(
                  context: context,
                  title: '移除此设备',
                  message: '此操作只删除本机离线授权。',
                  actions: const [
                    AdaptiveAlertAction(label: '取消', value: 'cancel'),
                    AdaptiveAlertAction(
                      label: '删除',
                      value: 'delete',
                      isDestructive: true,
                    ),
                  ],
                );
              },
              child: const Text('ShowMacAlert'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ShowMacAlert'));
      await tester.pumpAndSettle();

      expect(result, 'delete');
      expect(request?.method, 'showAlert');
      final args = request!.arguments as Map<Object?, Object?>;
      final actions = (args['actions'] as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(actions.first['label'], '取消');
      expect(actions.first['isCancel'], isTrue);
      expect(actions.last['isDestructive'], isTrue);
    } finally {
      debugForceMacosNativeUiModals = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS alert falls back to Flutter AlertDialog on MissingPluginException', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    debugForceMacosNativeUiModals = true;
    try {
      const macChannel = MethodChannel('techpie/macos_native_ui');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        macChannel,
        (_) async => throw MissingPluginException('missing'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          macChannel,
          null,
        ),
      );
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAdaptiveAlertDialog<String>(
                  context: context,
                  title: '提示',
                  message: '已保存修改',
                  actions: const [
                    AdaptiveAlertAction(
                      label: '确定',
                      value: 'ok',
                      isDefault: true,
                    ),
                  ],
                );
              },
              child: const Text('ShowFallbackAlert'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ShowFallbackAlert'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, 'ok');
    } finally {
      debugForceMacosNativeUiModals = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
