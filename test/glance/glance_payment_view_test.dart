import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/glance/presentation/glance_payment_view.dart';

Future<void> _pumpView(WidgetTester tester, AppRuntime runtime) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 294,
            height: 420,
            child: GlancePaymentView(runtime: runtime),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late AppRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtime = await buildDemoRuntime();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  testWidgets('signed-in glance shows an online QR', (tester) async {
    await runtime.auth.signIn(const DemoAuthCredential());
    await _pumpView(tester, runtime);

    expect(find.byKey(const Key('glance-payment-qr')), findsOneWidget);
    expect(find.text('在线付款码'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('signed-out glance asks the user to open the full app', (
    tester,
  ) async {
    await _pumpView(tester, runtime);

    expect(find.text('校园卡未登录'), findsOneWidget);
    expect(find.byKey(const Key('glance-payment-qr')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('rear-sized landscape card renders the QR without overflow', (
    tester,
  ) async {
    await runtime.auth.signIn(const DemoAuthCredential());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 150,
              child: GlancePaymentView(runtime: runtime),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('glance-payment-qr')), findsOneWidget);
    expect(find.text('在线付款码'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
