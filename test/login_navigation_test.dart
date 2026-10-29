import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/login_page.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('login sheet uses a centered title and a working close action', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const LoginPage(presentedAsSheet: true)),
            ),
            child: const Text('Open login'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('登录')).dx, closeTo(195, 0.1));
    final buttons = tester.widgetList<CNButton>(find.byType(CNButton));
    expect(buttons.any((button) => button.icon?.name == 'chevron.left'), isFalse);
    final close = buttons.singleWhere((button) => button.semanticLabel == '关闭登录');
    expect(close.icon!.name, 'xmark');
    close.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Open login'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
