import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/utils/product_version.dart';
import 'package:techpie/widgets/update_dialogs.dart';

void main() {
  // The two paths differ on purpose: the check that runs by itself says nothing
  // when it fails, and the one the user asked for has to report it and point
  // somewhere useful — GitHub in a browser, which does not depend on this app
  // reaching GitHub at all.
  testWidgets('a failed manual check reports it and offers GitHub', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showUpdateFailureDialog(
                  context,
                  message: '无法连接 GitHub：SocketException: connection refused',
                  source: UpdateSource.github,
                ),
                child: const Text('check'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.text('检查更新失败'), findsOneWidget);
    expect(find.textContaining('无法连接 GitHub'), findsOneWidget);
    expect(
      find.textContaining('前往 GitHub 的 releases 页面'),
      findsOneWidget,
      reason: 'the dialog has to say what the button is for',
    );
    expect(find.text('前往 GitHub'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // Taking the way out closes the dialog. The launch itself has no browser to
    // go to in a test, which the helper tolerates.
    await tester.tap(find.text('前往 GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新失败'), findsNothing);
  });

  testWidgets('both App Store update actions open the same store listing', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final openings = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'launch');
      openings.add(call.arguments['url'] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  onPressed: () => showUpdateAvailableDialog(
                    context,
                    const ReleaseInfo(
                      version: ProductVersion(1, 0, 2),
                      name: '1.0.2',
                      notes: '更新说明',
                      source: UpdateSource.appStore,
                    ),
                  ),
                  child: const Text('available'),
                ),
                ElevatedButton(
                  onPressed: () => showUpdateFailureDialog(
                    context,
                    message: '连接 App Store 超时，请检查网络后重试。',
                    source: UpdateSource.appStore,
                  ),
                  child: const Text('failed'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('available'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('可以前往 App Store 查看更新'), findsOneWidget);
    await tester.tap(find.text('前往 App Store'));
    await tester.pumpAndSettle();
    expect(openings, List.filled(2, 'itms-apps://apps.apple.com/app/id6771316576'));
  });

  testWidgets('an available update is offered by both paths alike', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showUpdateAvailableDialog(
                  context,
                  const ReleaseInfo(
                    version: ProductVersion(1, 0, 2),
                    name: 'v1.0.2',
                    notes: '## 变更\n\n- 修好了某件事',
                  ),
                ),
                child: const Text('offer'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v1.0.2'), findsOneWidget);
    expect(find.textContaining('修好了某件事'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);
    expect(find.text('前往更新'), findsOneWidget);
  });
}
