import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/bill_ports.dart';
import 'package:techpie/features/campus_card/presentation/app/app.dart';

void main() {
  testWidgets('activity keeps long histories lazy and opens the selected row',
      (tester) async {
    final rig = await _mount(tester, CampusCardEntry.cardManagement);
    await tester.tap(find.text('使用明细'));
    await tester.pumpAndSettle();
    debugPrint('ACTIVITY_INITIAL_ROWS=${_merchantLabels.evaluate().length}');
    expect(_merchantLabels.evaluate().length, lessThan(30));
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(_merchantLabels.evaluate().length, lessThan(30));
    final last = rig.records.last;
    expect(find.text(last.merchantName!), findsOneWidget);
    await tester.tap(find.text(last.merchantName!));
    await tester.pumpAndSettle();
    expect(find.text(last.id), findsOneWidget);
    await rig.dispose();
  });

  testWidgets('recent activity only builds rows near the payment viewport',
      (tester) async {
    final rig = await _mount(tester, CampusCardEntry.paymentCode);
    debugPrint('PAYMENT_INITIAL_ROWS=${_merchantLabels.evaluate().length}');
    expect(_merchantLabels.evaluate().length, lessThan(25));
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic merchant 24'), findsOneWidget);
    expect(find.text('Synthetic merchant 25'), findsNothing);
    await rig.dispose();
  });
}

final _merchantLabels = find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.data?.startsWith('Synthetic merchant ') ?? false),
);

Future<({List<TransactionRecord> records, Future<void> Function() dispose})>
    _mount(
  WidgetTester tester,
  CampusCardEntry entry,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final base = await buildDemoRuntime();
  await base.auth.signIn(const DemoAuthCredential());
  final history = _History();
  final runtime = AppRuntime(
    environment: base.environment,
    capabilities: base.capabilities,
    auth: base.auth,
    cards: base.cards,
    paymentCodes: base.paymentCodes,
    scanPayments: base.scanPayments,
    transactions: history,
    securitySettings: base.securitySettings,
    offlinePayments: base.offlinePayments,
    brightness: base.brightness,
    connectivity: base.connectivity,
    lifecycle: base.lifecycle,
    feedback: base.feedback,
    scanner: base.scanner,
  );
  final container = ProviderContainer(
    overrides: [
      appRuntimeProvider.overrideWithValue(runtime),
      campusCardEntryProvider.overrideWithValue(entry),
    ],
  );
  var disposed = false;
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
    await base.dispose();
  }

  addTearDown(dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CampusCardFeature()),
    ),
  );
  await tester.pumpAndSettle();
  return (records: history.records, dispose: dispose);
}

class _History
    implements TransactionHistoryPort, DateRangeTransactionHistoryPort {
  final records = List.generate(
    350,
    (index) => TransactionRecord(
      id: 'SCROLL-RECORD-$index',
      occurredAt:
          DateTime.utc(2026, 9, 1, 12).subtract(Duration(minutes: index)),
      title: 'Consumption',
      merchantName: 'Synthetic merchant $index',
      amount: const MoneyFen(-100),
      kind: TransactionKind.consumption,
    ),
  );

  @override
  Future<TransactionRecord> detail(String id) async =>
      records.firstWhere((record) => record.id == id);

  @override
  Future<TransactionPage> timeline({
    required String month,
    String? cursor,
    int pageSize = 20,
  }) =>
      timelineRange();

  @override
  Future<TransactionPage> timelineRange({
    DateTime? begin,
    DateTime? end,
    String? cursor,
    int pageSize = 20,
  }) async =>
      TransactionPage(items: records, hasMore: false);
}
