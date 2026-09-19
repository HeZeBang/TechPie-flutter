import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/application/offline_payment_service.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/crypto/sm2_offline_crypto.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/secure_offline_credential_repository.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';
import 'package:techpie/features/campus_card/domain/ports/offline_ports.dart';

final _now = DateTime.utc(2026, 9, 13);

void main() {
  for (final all in [false, true]) {
    test('removal cancels pending activation (all=$all)', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.service.dispose);
      final activation = fixture.service.activate(cardId: 'card');
      final checked = expectLater(
        activation,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            'OFFLINE_ACTIVATION_CANCELLED',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      if (all) {
        await fixture.service.removeAllFromThisDevice();
      } else {
        await fixture.service.removeFromThisDevice('card');
      }
      fixture.remote.activation.complete(const OfflineActivationResponse(
          authorInfo: '5638BB', totalUses: null,),);
      await checked;
      expect(
          await fixture.credentials.read('card', deviceCode: 'device'), isNull,);
    });
  }

  test('generation rejects a key replaced between credential reads', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.service.dispose);
    fixture.credentials.afterKeyRead = fixture.rotateKey;
    await expectLater(
      fixture.service.generate('card'),
      throwsA(
        isA<AppFailure>()
            .having((e) => e.code, 'code', 'OFFLINE_CREDENTIAL_CHANGED'),
      ),
    );
  });

  test('late renewal cannot overwrite a newly activated key pair', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.service.dispose);
    fixture.remote.pending = Completer<OfflineActivationResponse?>();
    final renewal = fixture.service.renew('card', force: true);
    final checked = expectLater(
      renewal,
      throwsA(
        isA<AppFailure>()
            .having((e) => e.code, 'code', 'OFFLINE_CREDENTIAL_CHANGED'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await fixture.rotateKey();
    final installed =
        await fixture.credentials.read('card', deviceCode: 'device');
    fixture.remote.pending!.complete(
      OfflineActivationResponse(
        authorInfo: '5638BB',
        totalUses: null,
        expiresOn: _now.add(const Duration(days: 40)),
      ),
    );
    await checked;
    final current =
        await fixture.credentials.read('card', deviceCode: 'device');
    expect(current!.publicKeyCompressed, installed!.publicKeyCompressed);
    expect(current.authorInfo, installed.authorInfo);
  });

  testWidgets('disposed offline provider does not recreate renewal timers',
      (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.service.dispose);
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final runtime = fixture.runtime(base);
    final container = ProviderContainer(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],);
    fixture.credentials.pendingRead = Completer<void>();
    container.read(offlineAuthorizationProvider('card'));
    await tester.pump();
    container.dispose();
    fixture.credentials.pendingRead!.complete();
    await tester.pump();
    await tester.pump(const Duration(minutes: 16));
    expect(fixture.remote.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late maintenance finishes safely after provider disposal',
      (tester) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.service.dispose);
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final container = ProviderContainer(overrides: [
      appRuntimeProvider.overrideWithValue(fixture.runtime(base)),
    ],);
    container.read(offlineAuthorizationProvider('card'));
    await tester.pump();
    fixture.remote.pending = Completer<OfflineActivationResponse?>();
    final maintenance = container
        .read(offlineAuthorizationProvider('card').notifier)
        .maintain();
    await tester.pump();
    expect(fixture.remote.calls, 1);
    container.dispose();
    fixture.remote.pending!.complete(null);
    await tester.pump();
    await maintenance;
    await tester.pump(const Duration(minutes: 16));
    expect(fixture.remote.calls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  _Fixture(this.credentials, this.remote, this.service);
  final _Credentials credentials;
  final _Remote remote;
  final OfflinePaymentService service;
  static Future<_Fixture> create() async {
    final credentials = _Credentials(
        SecureOfflineCredentialRepository(InMemorySecureCredentialStore()),);
    final remote = _Remote();
    final service = OfflinePaymentService(
      credentials: credentials,
      remote: remote,
      connectivity: InMemoryConnectivityPort(),
      crypto: Sm2OfflineCrypto(random: Random(3)),
      deviceCodeReader: () async => 'device',
      clock: Clock.fixed(_now),
    );
    final fixture = _Fixture(credentials, remote, service);
    await fixture.rotateKey();
    return fixture;
  }

  Future<void> rotateKey() async {
    final key = Sm2OfflineCrypto().generateKeyPair();
    await credentials.install(
      authorization: OfflineAuthorization(
        cardId: 'card',
        deviceCode: 'device',
        publicKeyCompressed: key.publicKeyCompressed,
        authorInfo: '5638AA',
        totalUses: null,
        used: 0,
        updatedAt: _now,
        expiresOn: _now.add(const Duration(days: 30)),
      ),
      privateKeyHex: key.privateKeyHex,
    );
  }

  AppRuntime runtime(AppRuntime base) => AppRuntime(
        environment: base.environment,
        capabilities: base.capabilities,
        auth: base.auth,
        cards: base.cards,
        paymentCodes: base.paymentCodes,
        scanPayments: base.scanPayments,
        transactions: base.transactions,
        securitySettings: base.securitySettings,
        offlinePayments: service,
        brightness: base.brightness,
        connectivity: base.connectivity,
        lifecycle: base.lifecycle,
        feedback: base.feedback,
      );
}

class _Remote implements OfflineAuthorizationRemotePort {
  Completer<OfflineActivationResponse?>? pending;
  int calls = 0;
  final activation = Completer<OfflineActivationResponse>();
  @override
  Future<OfflineActivationResponse?> renew(OfflineAuthorization grant) async {
    calls++;
    return pending?.future;
  }

  @override
  Future<OfflineActivationResponse> activate(
          OfflineActivationRequest request,) =>
      activation.future;
}

class _Credentials implements OfflineCredentialRepository {
  _Credentials(this.delegate);
  final OfflineCredentialRepository delegate;
  Future<void> Function()? afterKeyRead;
  Completer<void>? pendingRead;
  int keyReads = 0;
  @override
  Future<OfflineAuthorization?> read(String cardId,
      {required String deviceCode,}) async {
    await pendingRead?.future;
    return delegate.read(cardId, deviceCode: deviceCode);
  }

  @override
  Future<String?> readPrivateKey(String cardId,
      {required String deviceCode,}) async {
    final key = await delegate.readPrivateKey(cardId, deviceCode: deviceCode);
    // Generation reads the key twice — once to sign, once to confirm it did not
    // change while the use was reserved — so the rotation belongs after the
    // signing read, where the code under test must notice it.
    final callback = ++keyReads == 1 ? afterKeyRead : null;
    if (callback != null) afterKeyRead = null;
    await callback?.call();
    return key;
  }

  @override
  Future<OfflineAuthorization?> readMostRecent({required String deviceCode}) =>
      delegate.readMostRecent(deviceCode: deviceCode);
  @override
  Future<void> install(
          {required OfflineAuthorization authorization,
          required String privateKeyHex,}) =>
      delegate.install(
          authorization: authorization, privateKeyHex: privateKeyHex,);
  @override
  Future<OfflineAuthorization> reserveUse(String cardId,
          {required String deviceCode,}) =>
      delegate.reserveUse(cardId, deviceCode: deviceCode);
  @override
  Future<void> updateAuthorization(OfflineAuthorization authorization,
          {bool resetUsage = false,}) =>
      delegate.updateAuthorization(authorization, resetUsage: resetUsage);
  @override
  Future<void> remove(String cardId) => delegate.remove(cardId);
  @override
  Future<void> removeAll() => delegate.removeAll();
}
