import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/services/spending_alert_service.dart';
import 'package:techpie/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('techpie/spending_alerts');
  const identityA = SpendingIdentity(owner: 'owner-a', subjectId: 'subject-a');
  const identityB = SpendingIdentity(owner: 'owner-b', subjectId: 'subject-b');
  late StorageService storage;
  late SpendingAlertService service;
  SpendingIdentity? identity;
  final calls = <MethodCall>[];
  var generation = 1;
  String? nativeOwner;

  TransactionRecord record({String id = 'private-transaction-id', int fen = -1250}) =>
      TransactionRecord(
        id: id,
        occurredAt: DateTime.utc(2026, 11, 16, 12),
        title: '消费',
        amount: MoneyFen(fen),
        kind: TransactionKind.consumption,
        merchantName: '第一食堂',
        balance: const MoneyFen(8800),
      );

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    storage = StorageService(await SharedPreferences.getInstance());
    calls.clear();
    generation = 1;
    identity = identityA;
    nativeOwner = 'owner-a';
    service = SpendingAlertService(storage, channel: channel, identityReader: () async => identity);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'status') return {'owner': nativeOwner, 'generation': generation};
      return true;
    });
  });

  tearDown(() {
    service.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('fresh installs opt out of alerts and background work', () async {
    expect(service.enabled, isFalse);
    await service.synchronize();
    expect((calls.single.arguments as Map)['owner'], isNull);
    calls.clear();
    await service.observeTransactions([record()], subjectId: 'subject-a');
    expect(calls, isEmpty);
  });

  test('enabling configures an opaque account scope and requests permission', () async {
    await service.setEnabled(true);
    expect(storage.spendingAlertsEnabled, isTrue);
    expect(calls.map((c) => c.method), ['configure', 'requestPermission']);
    expect((calls.first.arguments as Map)['owner'], 'owner-a');
  });

  test('missing privacy consent or signed-out identity never activates', () async {
    await storage.setSpendingAlertsEnabled(true);
    await storage.setPrivacyAccepted(false);
    await service.synchronize();
    expect((calls.single.arguments as Map)['owner'], isNull);
    calls.clear();
    await storage.setPrivacyAccepted(true);
    identity = null;
    await service.synchronize();
    expect((calls.single.arguments as Map)['owner'], isNull);
  });

  test('Android only: iOS keeps its own payment and notification behavior', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await service.setEnabled(true);
    await service.synchronize();
    expect(calls, isEmpty);
    expect(storage.spendingAlertsEnabled, isFalse);
  });

  test('snapshot carries formatted amount and a hashed transaction key', () async {
    await storage.setSpendingAlertsEnabled(true);
    await service.observeTransactions([record(fen: 1250)], subjectId: 'subject-a');
    final args = calls.last.arguments as Map;
    expect(calls.last.method, 'observe');
    expect(args['owner'], 'owner-a');
    expect(args['generation'], 1);
    final row = (args['records'] as List).single as Map;
    expect(row['body'], '-12.50 · 第一食堂 · 余额 88.00');
    expect(row['key'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(args.toString(), isNot(contains('private-transaction-id')));
  });

  test('foreground snapshots from a previous card identity are ignored', () async {
    await storage.setSpendingAlertsEnabled(true);
    identity = identityB;
    await service.observeTransactions([record()], subjectId: 'subject-a');
    expect(calls, isEmpty);
  });

  test('snapshots cannot reconfigure a different native owner', () async {
    await storage.setSpendingAlertsEnabled(true);
    nativeOwner = 'owner-b';
    await service.observeTransactions([record()], subjectId: 'subject-a');
    expect(calls.map((c) => c.method), ['status']);
  });

  test('rapid disable invalidates an outstanding enable configuration', () async {
    service.dispose();
    final pending = Completer<SpendingIdentity?>();
    service = SpendingAlertService(storage, identityReader: () => pending.future);
    final enabling = service.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    await service.setEnabled(false);
    pending.complete(identityA);
    await enabling;
    expect(calls.where((c) => c.method == 'configure'), hasLength(1));
    expect((calls.single.arguments as Map)['owner'], isNull);
  });

  test('disabled background refresh never calls the network loader', () async {
    var loaded = false;
    expect(
        await service.refreshInBackground(() async {
          loaded = true;
          return [];
        }),
        isTrue,);
    expect(loaded, isFalse);
    expect(calls, isEmpty);
  });

  test('background captures native generation before the network read', () async {
    await storage.setSpendingAlertsEnabled(true);
    await service.refreshInBackground(() async {
      generation = 2;
      return [record()];
    });
    expect((calls.last.arguments as Map)['generation'], 1);
  });

  test('disable during network read discards the returned page', () async {
    await storage.setSpendingAlertsEnabled(true);
    await service.refreshInBackground(() async {
      await storage.setSpendingAlertsEnabled(false);
      return [record()];
    });
    expect(calls.map((c) => c.method), ['status']);
  });

  test('account switch during network read discards the returned page', () async {
    await storage.setSpendingAlertsEnabled(true);
    await service.refreshInBackground(() async {
      identity = identityB;
      return [record()];
    });
    expect(calls.map((c) => c.method), ['status']);
  });

  test('network failure asks WorkManager to retry without publishing', () async {
    await storage.setSpendingAlertsEnabled(true);
    expect(await service.refreshInBackground(() async => throw StateError('offline')), isFalse);
    expect(calls.map((c) => c.method), ['status']);
  });

  test('notification channel failure does not fail payment/history', () async {
    await storage.setSpendingAlertsEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'denied');
    });
    await service.observeTransactions([record()], subjectId: 'subject-a');
  });
}
