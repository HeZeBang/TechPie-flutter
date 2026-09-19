import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/presentation/app/app.dart';
import 'package:techpie/features/campus_card/presentation/screens/card_manage_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/login_screen.dart';
import 'package:techpie/features/campus_card/presentation/screens/payment_code_page.dart';
import 'package:techpie/features/campus_card/presentation/screens/settings_screen.dart';
import 'package:techpie/pages/campus_card_page.dart';

void main() {
  testWidgets('CampusCardPage mounts eCard without a TechPie loading gate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
    });
    final runtime = await buildDemoRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CampusCardPage(runtime: runtime)),
    );
    await tester.pump();

    expect(find.byType(CampusCardFeature), findsOneWidget);
    expect(find.text('eCard 初始化失败'), findsNothing);
  });

  testWidgets('TechPie opens and exits the integrated campus-card feature', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
    });
    final runtime = await buildDemoRuntime();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => CampusCardPage(
                      runtime: runtime,
                    ),
                  ),
                ),
                child: const Text('校园卡'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('校园卡'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.text('eCard 初始化失败'), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('打开 Account 设置'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.byType(CampusCardPage), findsNothing);
    expect(find.text('校园卡'), findsOneWidget);
  });
  testWidgets('system back returns from eCard settings to card management',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final runtime = await buildDemoRuntime();
    addTearDown(runtime.dispose);
    await runtime.auth.signIn(const DemoAuthCredential());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => CampusCardPage(
                      runtime: runtime,
                    ),
                  ),
                ),
              ),
              child: const Text('HOST ENTRY'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('HOST ENTRY'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byType(PaymentCodePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment-header-info')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byType(CardManageScreen), findsOneWidget);
    // The feature's pages live on the host navigator now, so "can pop" is the
    // host's answer, not a router's.
    final navigator = Navigator.of(tester.element(find.byType(CardManageScreen)));
    await tester.ensureVisible(find.text('设置'));
    await tester.pump();
    await tester.tap(find.text('设置'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(navigator.canPop(), isTrue);

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(
      // Offstage, because its own page covers it now that the feature's pages are
      // routes of the host navigator rather than a navigator of its own.
      find.byType(CampusCardPage, skipOffstage: false),
      findsOneWidget,
      reason:
          'System back must leave the eCard feature mounted while an internal route can pop.',
    );
    expect(find.byType(CardManageScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byType(PaymentCodePage), findsOneWidget);
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byType(CampusCardPage), findsNothing);
    expect(find.text('HOST ENTRY'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('embedded iOS navigator preserves interactive edge back',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final runtime = await buildDemoRuntime();
    addTearDown(runtime.dispose);
    await runtime.auth.signIn(const DemoAuthCredential());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              Navigator.of(context).push<void>(
                CupertinoPageRoute<void>(
                  builder: (_) => CampusCardPage(runtime: runtime),
                ),
              ),
            ),
            child: const Text('HOST ENTRY'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('HOST ENTRY'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.tap(find.byKey(const Key('payment-header-info')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final details = find.byType(CardManageScreen);
    expect(details, findsOneWidget);
    final gesture = await tester.startGesture(const Offset(1, 400));
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    expect(tester.getTopLeft(details).dx, greaterThan(0));
    await gesture.moveBy(const Offset(350, 0));
    await gesture.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(details, findsNothing);
    expect(find.byType(PaymentCodePage), findsOneWidget);
    expect(find.byType(CampusCardPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
