import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/presentation/screens/bill_transaction_screen.dart';
import 'package:techpie/features/campus_card/presentation/widgets/gp_state.dart';

void main() {
  group('BillTransactionScreen', () {
    testWidgets('demo: renders the recorded amount, title and identifier', (
      tester,
    ) async {
      final runtime = await buildDemoRuntime();
      addTearDown(runtime.dispose);

      final page = await runtime.transactions.timeline(month: '2025-09');
      // The September fixture is what this test renders: if it stops carrying
      // records the test has to fail, not quietly assert nothing.
      expect(page.items, isNotEmpty);
      final record = page.items.first;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: MaterialApp(
            home: BillTransactionScreen(transactionId: record.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('演示数据 · 非真实账户'), findsNothing);
      expect(find.textContaining('¥'), findsWidgets);
      // The detail view prints the record it was given and never invents a
      // field the record does not carry.
      expect(find.text(record.title), findsWidgets);
      expect(find.text(record.id), findsOneWidget);
      if (record.location == null) {
        expect(find.text('所属单位'), findsNothing);
      } else {
        expect(find.text('所属单位'), findsOneWidget);
      }
    });

    testWidgets('uses friendly labels without repeating canonical raw fields', (
      tester,
    ) async {
      final record = TransactionRecord(
        id: 'DETAIL-001',
        occurredAt: DateTime(2026, 9, 2, 22, 32, 54),
        title: '持卡人修改消费限额',
        merchantName: '持卡人修改消费限额',
        amount: MoneyFen.zero,
        kind: TransactionKind.adjustment,
        details: const {
          'id': 'DETAIL-001',
          'txdate': '2026-09-02 22:32:54',
          'txname': '持卡人修改消费限额',
          'mername': '持卡人修改消费限额',
          'txamt': '0',
          'merchantno': '8888',
          'poscode': '-',
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionDetailProvider(
              'DETAIL-001',
            ).overrideWith((ref) async => record),
          ],
          child: const MaterialApp(
            home: BillTransactionScreen(transactionId: 'DETAIL-001'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('交易类型'), findsOneWidget);
      expect(find.text('交易流水号'), findsOneWidget);
      expect(find.text('商户号'), findsOneWidget);
      expect(find.text('POS 代码'), findsOneWidget);
      expect(find.text('merchantno'), findsNothing);
      expect(find.text('txdate'), findsNothing);
      expect(find.text('txamt'), findsNothing);
    });

    testWidgets(
      'non-demo: uncached record shows normal title, safe error, no fabricated detail',
      (tester) async {
        const uncachedId = 'sha256-fallback-marker-0001';
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              transactionDetailProvider(uncachedId).overrideWith(
                (ref) => Future<TransactionRecord>.error(
                  const AppFailure(
                    FailureKind.invalidInput,
                    '当前会话中没有这笔交易详情，请从账单列表重新进入。',
                    code: 'TRANSACTION_DETAIL_NOT_CACHED',
                  ),
                ),
              ),
            ],
            child: const MaterialApp(
              home: BillTransactionScreen(transactionId: uncachedId),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // An uncached record resolves to a safe error, never a fabricated
        // amount or internal identifier.
        expect(find.text('交易详情暂未开放'), findsNothing);
        expect(find.byType(GpStateView), findsOneWidget);
        expect(find.text('演示记录标识'), findsNothing);
        expect(find.textContaining(uncachedId), findsNothing);
      },
    );
  });
}
