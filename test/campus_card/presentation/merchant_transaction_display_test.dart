import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/repositories/merchant_alias_repository.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/models/merchant_alias_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/merchant_alias_port.dart';
import 'package:techpie/features/campus_card/presentation/icons/platform_icons.dart';
import 'package:techpie/features/campus_card/presentation/screens/bill_transaction_screen.dart';
import 'package:techpie/features/campus_card/presentation/widgets/apple_wallet_components.dart';

MerchantAliasConfig _config({int version = 1, String? pos}) =>
    MerchantAliasConfig.decode(
      jsonEncode({
        'schemaVersion': 1,
        'version': version,
        'updatedAt': '2026-10-11T00:00:00Z',
        'entries': [
          {
            'merchantId': 'SYNTHETIC-A',
            if (pos != null) 'posCode': pos,
            'alias': pos == null ? 'Synthetic area' : 'Synthetic dining stall',
            'enabled': true,
            'verifiedAt': '2026-10-11',
            'evidence': 'Synthetic test',
            'category': 'dining',
          },
        ],
      }),
    );

TransactionRecord _record(
  String id,
  DateTime time, {
  bool valid = true,
  TransactionKind kind = TransactionKind.consumption,
}) =>
    TransactionRecord(
      id: id,
      occurredAt: time,
      title: kind == TransactionKind.creditReplenishment ? '补足信用额度' : '消费',
      merchantName: 'Original synthetic company',
      amount: MoneyFen(kind == TransactionKind.consumption ? -100 : 100),
      kind: kind,
      merchantId: 'SYNTHETIC-A',
      posCode: '0238',
      hasValidDate: valid,
      details: const {'merchantno': 'SYNTHETIC-A', 'poscode': '0238'},
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('shipped aliases display only for the verified merchant and POS',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source = await tester.runAsync(
      () => rootBundle.loadString(MerchantAliasRepository.bundledConfigAsset),
    );
    final directory = MerchantAliasConfig.decode(source!);
    const pairs = [
      ('243000125', '0238', '丝路二楼 · 米粉'),
      ('243000125', '0237', '丝路二楼 · 炸鸡'),
      ('243000125', '0235', '丝路二楼 · 煲仔饭'),
      ('243000481', '0302', '校内全家'),
      ('243000481', '0305', '校内全家'),
      ('243000161', '0213', '尚科二楼 · 滑蛋饭窗口'),
      ('243000161', '0209', '尚科二楼 · 铁板窗口'),
      ('243000381', '0310', '白玉兰一楼 · 麻辣香锅'),
      ('243000381', '0315', '白玉兰一楼 · 港式烧腊窗口'),
    ];
    final records = [
      for (final pair in pairs)
        TransactionRecord(
          id: 'SYNTHETIC-${pair.$2}',
          occurredAt: DateTime(2026, 10, 11, 12),
          title: '消费',
          merchantName: 'Original synthetic company',
          merchantId: pair.$1,
          posCode: pair.$2,
          amount: const MoneyFen(-100),
          kind: TransactionKind.consumption,
        ),
      _record('OTHER-MERCHANT', DateTime(2026, 10, 11, 12)),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [TransactionList(items: records, aliases: directory)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final pair in pairs.where((pair) => pair.$3 != '校内全家')) {
      expect(find.text(pair.$3), findsOneWidget);
    }
    expect(find.text('校内全家'), findsNWidgets(2));
    expect(find.text('Original synthetic company'), findsOneWidget);
    expect(find.byIcon(GpPlatformIcons.dining.android), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'groups by local calendar day with time only and an unknown-date group',
      (tester) async {
    final records = [
      _record('C', DateTime(2026, 10, 10, 23, 59, 59)),
      _record('A', DateTime(2026, 10, 11, 12, 34, 56)),
      _record('UNKNOWN', DateTime.utc(1970), valid: false),
      _record(
        'B',
        DateTime(2026, 10, 11, 0, 0, 1),
        kind: TransactionKind.creditReplenishment,
      ),
      _record(
        'CREDIT-ONLY-DAY',
        DateTime(2026, 10, 12, 0, 0, 1),
        kind: TransactionKind.creditReplenishment,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              TransactionList(items: records, aliases: _config(pos: '0238')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026-10-11'), findsOneWidget);
    expect(find.text('2026-10-10'), findsOneWidget);
    expect(find.text('12:34:56'), findsOneWidget);
    expect(find.text('00:00:01'), findsNothing);
    expect(find.text('23:59:59'), findsOneWidget);
    expect(find.text('2026-10-11 12:34:56'), findsNothing);
    expect(find.text('日期未知'), findsOneWidget);
    expect(find.text('时间未知'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
    expect(find.byIcon(GpPlatformIcons.dining.android), findsNWidgets(3));
    expect(
      find.byIcon(GpPlatformIcons.creditReplenishment.android),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('B')), findsNothing);
    expect(find.byKey(const ValueKey('CREDIT-ONLY-DAY')), findsNothing);
    expect(find.text('2026-10-12'), findsNothing);
    expect(find.text('补足信用额度'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('A'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('C'))).dy),
    );
  });

  testWidgets('credit-only history shows the empty state without date headers',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              TransactionList(
                items: [
                  _record(
                    'HIDDEN',
                    DateTime(2026, 10, 12),
                    kind: TransactionKind.creditReplenishment,
                  ),
                  _record(
                    'HIDDEN-UNKNOWN',
                    DateTime.utc(1970),
                    valid: false,
                    kind: TransactionKind.creditReplenishment,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('这个时间范围内没有交易'), findsOneWidget);
    expect(find.text('2026-10-12'), findsNothing);
    expect(find.text('日期未知'), findsNothing);
    expect(find.text('补足信用额度'), findsNothing);
    expect(find.byKey(const ValueKey('HIDDEN')), findsNothing);
  });

  testWidgets('all-record mode reveals credit and service actions',
      (tester) async {
    final credit = _record(
      'CREDIT',
      DateTime(2026, 10, 12),
      kind: TransactionKind.creditReplenishment,
    );
    final service = TransactionRecord(
      id: 'SERVICE',
      occurredAt: DateTime(2026, 10, 12),
      title: '付款码设置',
      merchantId: '900000001',
      amount: MoneyFen.zero,
      kind: TransactionKind.adjustment,
    );
    for (final showAll in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                TransactionList(
                  items: [credit, service],
                  showAllRecords: showAll,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('CREDIT')),
        showAll ? findsOneWidget : findsNothing,
      );
      expect(find.text('付款码设置'), showAll ? findsOneWidget : findsNothing);
      expect(find.text('2026-10-12'), showAll ? findsOneWidget : findsNothing);
    }
  });

  test('default filter distinguishes service merchant terminals and kinds', () {
    for (final kind in TransactionKind.values) {
      final record = _record(kind.name, DateTime(2026, 10, 12), kind: kind);
      expect(
        isTransactionVisible(record),
        kind != TransactionKind.creditReplenishment,
      );
      expect(isTransactionVisible(record, showAllRecords: true), isTrue);
    }
    for (final merchant in ['900000001', 'SYNTHETIC-OTHER']) {
      for (final pos in [null, '', '   ', '0238']) {
        final record = TransactionRecord(
          id: 'SYNTHETIC',
          occurredAt: DateTime(2026, 10, 12),
          title: '付款码设置',
          merchantId: merchant,
          posCode: pos,
          amount: MoneyFen.zero,
          kind: TransactionKind.adjustment,
        );
        expect(
          isTransactionVisible(record),
          merchant != '900000001' || (pos?.trim().isNotEmpty ?? false),
        );
        expect(isTransactionVisible(record, showAllRecords: true), isTrue);
      }
    }
  });

  testWidgets(
      'detail retains original information and full time with an alias and correction',
      (tester) async {
    final record = _record('SYNTHETIC-TX', DateTime(2026, 10, 11, 12, 34, 56));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantAliasConfigProvider.overrideWithValue(_config(pos: '0238')),
          transactionDetailProvider(record.id)
              .overrideWith((ref) async => record),
        ],
        child:
            MaterialApp(home: BillTransactionScreen(transactionId: record.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synthetic dining stall'), findsOneWidget);
    expect(find.text('Original synthetic company'), findsOneWidget);
    expect(find.text('2026-10-11 12:34:56'), findsOneWidget);
    expect(find.text('商户号'), findsOneWidget);
    expect(find.text('POS 代码'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('纠正商户资料'), 200);
    expect(find.text('补充商户资料'), findsNothing);
    expect(find.text('纠正商户资料'), findsOneWidget);
  });

  testWidgets(
      'unknown invitation appears once while manual contribution remains available',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        merchantAliasConfigProvider
            .overrideWithValue(const MerchantAliasConfig.empty()),
        transactionDetailProvider('SYNTHETIC-TX').overrideWith(
          (ref) async => _record('SYNTHETIC-TX', DateTime(2026, 10, 11)),
        ),
      ],
    );
    addTearDown(container.dispose);
    Future<void> mount(int generation) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            key: ValueKey(generation),
            home: const BillTransactionScreen(transactionId: 'SYNTHETIC-TX'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('补充商户资料'), 200);
    }

    await mount(1);
    expect(find.text('此商户尚未收录'), findsOneWidget);
    await tester.ensureVisible(find.text('跳过'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('此商户尚未收录'), findsNothing);
    await mount(2);
    expect(find.text('此商户尚未收录'), findsNothing);
    expect(find.text('补充商户资料'), findsOneWidget);
  });

  testWidgets('unknown POS on a known area offers contribution and correction',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantAliasConfigProvider.overrideWithValue(_config()),
          transactionDetailProvider('SYNTHETIC-TX').overrideWith(
            (ref) async => _record('SYNTHETIC-TX', DateTime(2026, 10, 11)),
          ),
        ],
        child: const MaterialApp(
          home: BillTransactionScreen(transactionId: 'SYNTHETIC-TX'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('纠正商户资料'), 200);
    expect(find.text('此收款终端尚未收录'), findsOneWidget);
    expect(find.text('补充商户资料'), findsOneWidget);
  });

  testWidgets('invalid date detail does not show a fabricated epoch',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantAliasConfigProvider
              .overrideWithValue(const MerchantAliasConfig.empty()),
          transactionDetailProvider('UNKNOWN').overrideWith(
            (ref) async => _record(
              'UNKNOWN',
              DateTime.utc(1970),
              valid: false,
              kind: TransactionKind.adjustment,
            ),
          ),
        ],
        child: const MaterialApp(
          home: BillTransactionScreen(transactionId: 'UNKNOWN'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('时间未知'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
    expect(find.text('补充商户资料'), findsNothing);
  });

  test(
      'provider sees late configuration changes without requesting transactions',
      () async {
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final directory = _Directory();
    addTearDown(directory.controller.close);
    // The default port stays offline in the demo runtime.
    expect(base.merchantAliases.current.version, 0);
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: base.auth,
      cards: base.cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      merchantAliases: directory,
    );
    final container = ProviderContainer(
      overrides: [
        appRuntimeProvider.overrideWithValue(runtime),
      ],
    );
    addTearDown(container.dispose);
    final subscription =
        container.listen(merchantAliasConfigProvider, (_, __) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(merchantAliasConfigProvider).version, 0);
    directory.publish(_config());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(merchantAliasConfigProvider).version, 1);
  });
}

final class _Directory implements MerchantAliasPort {
  final controller =
      StreamController<MerchantAliasConfig>.broadcast(sync: true);
  @override
  MerchantAliasConfig current = const MerchantAliasConfig.empty();
  @override
  Stream<MerchantAliasConfig> get changes => controller.stream;
  void publish(MerchantAliasConfig value) {
    current = value;
    controller.add(value);
  }
}
