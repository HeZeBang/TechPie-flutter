import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scan_result_content.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';
import 'package:techpie/features/campus_card/presentation/theme/tokens.dart';

Widget _host(Widget child) => MaterialApp(
      theme: GeekPayTheme.inherit(ThemeData.dark())
          .copyWith(platform: TargetPlatform.android),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('receipt displays amount, campus time, authorization and transaction fields', (tester) async {
    final result = ScanSucceeded(kind: ScanSuccessKind.payment, amount: const MoneyFen(617),
      paidAt: DateTime(2026, 9, 13, 22, 40, 31), authorizationCode: 'A1B2',
      transactionId: '0305_20260913224014_A1B2', terminalCode: '0305', transactionCode: '1829',);
    await tester.pumpWidget(_host(SingleChildScrollView(child: ScanResultContent(success: result, onDone: () {}))));
    await tester.pump();
    expect(find.text('¥6.17'), findsOneWidget);
    expect(find.text('支付时间 2026-09-13 22:40:31'), findsOneWidget);
    expect(find.text('授权码 A1B2'), findsOneWidget);
    expect(find.text('交易流水号 0305_20260913224014_A1B2'), findsOneWidget);
    expect(find.text('CORE10008'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('ScanResultContent', () {
    testWidgets('payment success renders amount, fee, and balance only', (
      tester,
    ) async {
      const result = ScanSucceeded(
        kind: ScanSuccessKind.payment,
        amount: MoneyFen(4250),
        fee: MoneyFen(50),
        balance: MoneyFen(123456),
        message: null,
      );
      await tester.pumpWidget(
        _host(ScanResultContent(success: result, onDone: () {})),
      );
      await tester.pump();

      expect(find.text('支付成功'), findsOneWidget);
      expect(find.text('¥42.50'), findsOneWidget);
      expect(tester.widget<Text>(find.text('支付成功')).style!.color, GpTokens.campusRed);
      expect(tester.widget<Text>(find.text('¥42.50')).style!.color, GpTokens.campusRed);
      expect(find.text('含管理费 ¥0.50'), findsOneWidget);
      expect(find.text('交易后余额 ¥1,234.56'), findsOneWidget);
      // Merchant/location must not be rendered (they are not provided).
      expect(find.textContaining('商户'), findsNothing);
      expect(find.textContaining('门店'), findsNothing);
    });

    testWidgets('attendance renders attendance confirm text only', (
      tester,
    ) async {
      const result = ScanSucceeded(kind: ScanSuccessKind.attendance);
      await tester.pumpWidget(
        _host(ScanResultContent(success: result, onDone: () {})),
      );
      await tester.pump();

      expect(find.text('签到成功'), findsOneWidget);
      expect(find.text('¥'), findsNothing);
    });

    testWidgets('openDevice renders open-device confirm text only', (
      tester,
    ) async {
      const result = ScanSucceeded(kind: ScanSuccessKind.openDevice);
      await tester.pumpWidget(
        _host(ScanResultContent(success: result, onDone: () {})),
      );
      await tester.pump();

      expect(find.text('开阀成功'), findsOneWidget);
    });

    testWidgets('bindTray renders bind-tray confirm text only', (tester) async {
      const result = ScanSucceeded(kind: ScanSuccessKind.bindTray);
      await tester.pumpWidget(
        _host(ScanResultContent(success: result, onDone: () {})),
      );
      await tester.pump();

      expect(find.text('绑盘成功'), findsOneWidget);
    });

    testWidgets('unknown kind renders neutral completion text', (tester) async {
      const result = ScanSucceeded(kind: ScanSuccessKind.unknown);
      await tester.pumpWidget(
        _host(ScanResultContent(success: result, onDone: () {})),
      );
      await tester.pump();

      expect(find.text('处理完成'), findsOneWidget);
      expect(find.text('支付成功'), findsNothing);
    });
  });
}
