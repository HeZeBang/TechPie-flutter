import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/app_environment.dart';
import 'package:techpie/features/campus_card/core/config/debug_mode_controller.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/bill_ports.dart';

class _History implements TransactionHistoryPort, DateRangeTransactionHistoryPort {
  Completer<TransactionPage>? pending;
  final records = [TransactionRecord(
    id: 'receipt', occurredAt: DateTime.utc(2026, 11, 17), title: 'Meal',
    amount: const MoneyFen(-1200), kind: TransactionKind.consumption,
  ),];
  @override
  Future<TransactionPage> timelineRange({DateTime? begin, DateTime? end, String? cursor, int pageSize = 20}) async =>
      pending?.future ?? TransactionPage(items: records, hasMore: false);
  @override
  Future<TransactionPage> timeline({required String month, String? cursor, int pageSize = 20}) => timelineRange();
  @override
  Future<TransactionRecord> detail(String id) async => records.single;
}

class _Alerts implements SpendingAlertPort {
  final snapshots = <List<TransactionRecord>>[];
  final subjects = <String>[];
  @override
  Future<void> observeTransactions(List<TransactionRecord> records, {required String subjectId}) async {
    snapshots.add(records);
    subjects.add(subjectId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppRuntime base;
  late ProviderContainer container;
  late _History history;
  late _Alerts alerts;

  Future<void> setup({AppEnvironment environment = AppEnvironment.production}) async {
    SharedPreferences.setMockInitialValues({});
    base = await buildDemoRuntime();
    await base.auth.signIn(const DemoAuthCredential());
    history = _History();
    alerts = _Alerts();
    final runtime = AppRuntime(
      environment: environment, capabilities: base.capabilities, auth: base.auth,
      cards: base.cards, paymentCodes: base.paymentCodes, scanPayments: base.scanPayments,
      transactions: history, securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments, brightness: base.brightness,
      connectivity: base.connectivity, lifecycle: base.lifecycle, feedback: base.feedback,
    );
    container = ProviderContainer(overrides: [
      appRuntimeProvider.overrideWithValue(runtime), spendingAlertPortProvider.overrideWithValue(alerts),
    ],);
    await container.read(authControllerProvider.future);
    await Future<void>.delayed(Duration.zero);
    addTearDown(() async { container.dispose(); await base.dispose(); });
  }

  test('history refresh sends the complete first page so native code can seed its baseline', () async {
    await setup();
    await container.read(accountHistoryRefreshProvider).refresh();
    expect(alerts.snapshots.single.single.id, 'receipt');
    expect(alerts.subjects.single, 'demo-student-001');
  });

  test('demo runtime cannot produce real consumption notifications', () async {
    await setup(environment: AppEnvironment.demo);
    await container.read(accountHistoryRefreshProvider).refresh();
    expect(alerts.snapshots, isEmpty);
  });

  test('debug ledger entries cannot produce notifications', () async {
    await setup();
    await container.read(debugModeProvider.notifier).setEnabled(true);
    await container.read(accountHistoryRefreshProvider).refresh();
    expect(alerts.snapshots, isEmpty);
  });

  test('signed-out ledger refreshes cannot be forwarded to notifications', () async {
    await setup();
    await base.auth.signOut();
    await container.read(accountHistoryRefreshProvider).refresh();
    expect(alerts.snapshots, isEmpty);
  });
}
