import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/application/offline_payment_service.dart';
import 'package:techpie/features/campus_card/data/crypto/sm2_offline_crypto.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/data/storage/secure_offline_credential_repository.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';
import 'package:techpie/features/campus_card/domain/models/profile_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/offline_ports.dart';
import 'package:techpie/services/watch_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('techpie/watch-test');
  late _Cards cards;
  late SecureSessionCredentialStore session;
  late InMemorySecureCredentialStore secure;
  late _EventsAuth eventsAuth;
  late WatchSyncService sync;
  late AppRuntime base;
  late List<MethodCall> calls;
  late bool enabled;
  late bool ready;
  String? boundSubject;

  setUp(() async {
    calls = [];
    enabled = false;
    ready = true;
    boundSubject = null;
    secure = InMemorySecureCredentialStore();
    session = SecureSessionCredentialStore(secure);
    eventsAuth = _EventsAuth();
    await session.writeSession(
      sessionCookie: 'synthetic',
      openId: 'SYNTHETIC_OPENID_0123456789',
      orgId: '2',
      verifiedIdSerial: 'DEMO-CARD-0001',
      verifiedCardId: 'TEST-CARD',
    );
    base = await buildDemoRuntime();
    cards = _Cards();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: eventsAuth,
      cards: cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'publish') {
        enabled = true;
        boundSubject = (call.arguments as Map)['subject'] as String;
      }
      if (call.method == 'disable') enabled = false;
      return {
        'ready': ready,
        'enabled': enabled,
        'revision': 1,
        'acknowledged': 0,
        'subject': boundSubject,
      };
    });
    sync = WatchSyncService(runtime, session, channel: channel);
  });
  tearDown(() async {
    sync.dispose();
    await eventsAuth.events.close();
    await base.offlinePayments.dispose();
    await base.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('cache miss and slow refresh preserve enrollment then synchronize', () async {
    enabled = true;
    cards.cachePresent = false;
    cards.pending = Completer<CampusCard?>();
    final pending = sync.synchronize();
    await pumpEventQueue();
    expect(sync.enabled, isTrue);
    expect(calls.where((c) => c.method == 'disable'), isEmpty);
    cards.pending!.complete(cards.card);
    await pending;
    expect(calls.where((c) => c.method == 'publish'), hasLength(1));
  });

  test('missing verification pin preserves enrollment', () async {
    enabled = true;
    await secure.delete('geekpay.auth.verified_idserial');
    await sync.synchronize();
    expect(calls.where((c) => c.method == 'disable'), isEmpty);
    expect(sync.enabled, isTrue);
  });

  test('transient expiration preserves authorization but explicit logout revokes it', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    enabled = true;
    sync.initialize();
    await pumpEventQueue();
    calls.clear();
    eventsAuth.events.add(const AuthSnapshot(state: AuthState.expired));
    await pumpEventQueue();
    expect(calls.where((c) => c.method == 'disable'), isEmpty);
    expect(sync.enabled, isTrue);
    eventsAuth.events.add(const AuthSnapshot(state: AuthState.signedOut, reason: AuthChangeReason.userSignedOut));
    await pumpEventQueue();
    expect(calls.where((c) => c.method == 'disable'), hasLength(1));
    expect(sync.enabled, isFalse);
    expect(sync.events.any((event) => event.text.contains('userSignedOut')), isTrue);
  });

  test('nothing is exported before explicit enrollment', () async {
    await sync.synchronize();
    expect(calls.where((c) => c.method == 'publish'), isEmpty);
    ready = false;
    await sync.enable();
    expect(calls.where((c) => c.method == 'publish'), isEmpty);
  });

  test('an existing grant exports even when the API opening flag is false',
      () async {
    final credentials =
        SecureOfflineCredentialRepository(InMemorySecureCredentialStore());
    final crypto = Sm2OfflineCrypto();
    final pair = crypto.generateKeyPair();
    await credentials.install(
      authorization: OfflineAuthorization(
          cardId: cards.card.id,
          deviceCode: 'SYNTHETIC_OPENID_0123456789',
          publicKeyCompressed: pair.publicKeyCompressed,
          authorInfo: '5638A1B2',
          totalUses: null,
          used: 0,
          updatedAt: DateTime.now().toUtc(),
          expiresOn: DateTime.utc(2099, 1, 1),),
      privateKeyHex: pair.privateKeyHex,
    );
    final offline = OfflinePaymentService(
        credentials: credentials,
        remote: _NoRenewal(),
        connectivity: InMemoryConnectivityPort(),
        crypto: crypto,
        deviceCodeReader: session.readOpenId,);
    addTearDown(offline.dispose);
    sync.dispose();
    sync = WatchSyncService(
        AppRuntime(
            environment: base.environment,
            capabilities: base.capabilities,
            auth: eventsAuth,
            cards: cards,
            paymentCodes: base.paymentCodes,
            scanPayments: base.scanPayments,
            transactions: base.transactions,
            securitySettings: base.securitySettings,
            offlinePayments: offline,
            brightness: base.brightness,
            connectivity: base.connectivity,
            lifecycle: base.lifecycle,
            feedback: base.feedback,),
        session,
        channel: channel,);
    expect(cards.card.offlineCodeAllowed, isFalse);
    await sync.enable();
    final body =
        calls.singleWhere((c) => c.method == 'publish').arguments as Map;
    expect((body['card'] as Map)['permitsPayment'], isTrue);
    expect((body['credential'] as Map)['privateKey'], pair.privateKeyHex);
    expect((body['credential'] as Map)['authorInfo'], '5638A1B2');
  });

  test(
      'exports verified card and original data timestamp, not the transmission time',
      () async {
    await sync.enable();
    final body =
        calls.singleWhere((c) => c.method == 'publish').arguments as Map;
    final card = body['card'] as Map;
    expect(card['name'], '示例');
    expect(card['studentID'], 'DEMO-CARD-0001');
    expect(card['balanceFen'], 12860);
    expect(
      card['updatedAt'],
      DateTime.utc(2026, 9, 1).millisecondsSinceEpoch / 1000,
    );
    expect(body.containsKey('openId'), isFalse);
    expect(body['enroll'], isTrue);
    expect(body['credential'], isNull); // The demo has a bounded authorization.
  });

  test('account switch during refresh prevents exporting the old account',
      () async {
    final pending = Completer<CampusCard?>();
    cards.pending = pending;
    final enable = sync.enable();
    await pumpEventQueue();
    await session.writeSession(
      sessionCookie: 'synthetic-other',
      openId: 'SYNTHETIC_OTHER_OPENID_0123456',
      orgId: '2',
      verifiedIdSerial: 'OTHER-STUDENT',
      verifiedCardId: 'OTHER-CARD',
    );
    pending.complete(cards.card);
    await enable;
    expect(calls.where((c) => c.method == 'publish'), isEmpty);
  });

  test('disable wins over an in-flight enrollment', () async {
    final pending = Completer<CampusCard?>();
    cards.pending = pending;
    final enable = sync.enable();
    await pumpEventQueue();
    await sync.disable();
    pending.complete(cards.card);
    await enable;
    expect(calls.where((c) => c.method == 'publish'), isEmpty);
    expect(sync.enabled, isFalse);
  });

  test('missing identity pauses synchronization without revoking enrollment', () async {
    enabled = true;
    await session.clear();
    await sync.synchronize();
    expect(calls.where((c) => c.method == 'disable'), isEmpty);
    expect(sync.enabled, isTrue);
    expect(calls.where((c) => c.method == 'publish'), isEmpty);
  });

  test(
      'changing the enrolled account clears instead of automatically authorizing the new one',
      () async {
    await sync.enable();
    calls.clear();
    await session.writeSession(
      sessionCookie: 'synthetic-other',
      openId: 'SYNTHETIC_OTHER_OPENID_0123456',
      orgId: '2',
      verifiedIdSerial: 'DEMO-CARD-0001',
      verifiedCardId: 'OTHER-CARD',
    );
    await sync.synchronize();
    expect(calls.where((c) => c.method == 'disable'), hasLength(1));
    expect(calls.where((c) => c.method == 'publish'), isEmpty);
  });
}

final class _Cards implements CacheFirstCardRepository {
  bool cachePresent = true;
  Completer<CampusCard?>? pending;
  final card = CampusCard(
    id: 'DEMO-CARD-0001',
    maskedNumber: '****0001',
    ownerName: '示例',
    balance: const MoneyFen(12860),
    status: CampusCardStatus.normal,
    positionName: '学生',
    offlineCodeAllowed: false,
    updatedAt: DateTime.utc(2026, 9, 1),
  );
  @override
  Future<CampusCard?> readCachedCard() async => cachePresent ? card : null;
  @override
  Future<CampusCard?> refreshCard() => pending?.future ?? Future.value(card);
  @override
  Future<CampusCard?> currentCard() async => card;
  @override
  Future<UserProfile> profile() => throw UnimplementedError();
  @override
  Future<BindCardResult> bind(BindCardCommand command) =>
      throw UnimplementedError();
  @override
  Future<void> unbind({required String cardPassword}) =>
      throw UnimplementedError();
}

final class _NoRenewal implements OfflineAuthorizationRemotePort {
  @override
  Future<OfflineActivationResponse> activate(
          OfflineActivationRequest request,) =>
      throw StateError('Must not create another key');
  @override
  Future<OfflineActivationResponse?> renew(
          OfflineAuthorization authorization,) =>
      throw StateError('Grant is still current');
}

class _EventsAuth implements AuthPort {
  final events = StreamController<AuthSnapshot>.broadcast(sync: true);
  @override
  Stream<AuthSnapshot> get changes => events.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
