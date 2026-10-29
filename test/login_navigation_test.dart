import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/login_page.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform opens the shared login page and returns to its caller', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await presentLoginPage(context);
                returned = true;
              },
              child: const Text('Open login'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.byType(LoginPage)));
      expect(
        route,
        platform == TargetPlatform.iOS
            ? isA<CupertinoPageRoute<void>>()
            : isA<MaterialPageRoute<void>>(),
      );
      expect(
        find.byType(platform == TargetPlatform.iOS ? IosNativeNavigationBar : AppBar),
        findsOneWidget,
      );
      expect(find.text('TechPie'), findsOneWidget);
      expect(find.text('登录以访问校园服务'), findsOneWidget);
      if (platform == TargetPlatform.iOS) {
        final login = tester.widgetList<CNButton>(find.byType(CNButton)).singleWhere(
              (button) => button.semanticLabel == '通过 GeekPie Uni-Auth 登录',
            );
        expect(login.config.style, CNButtonStyle.prominentGlass);
        expect(login.enabled, isTrue);
        expect(login.onPressed, isNotNull);
      } else {
        expect(find.widgetWithText(FilledButton, '通过 GeekPie Uni-Auth 登录'), findsOneWidget);
      }
      expect(returned, isFalse);
      expect(tester.takeException(), isNull);
      if (platform == TargetPlatform.iOS) {
        // Native platform-view taps are delivered through this callback.
        final back = tester.widgetList<CNButton>(find.byType(CNButton)).singleWhere(
              (button) => button.semanticLabel == '返回',
            );
        back.onPressed!();
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(find.text('Open login'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
