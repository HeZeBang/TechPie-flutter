import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/application/offline_payment_service.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/crypto/sm2_offline_crypto.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/secure_offline_credential_repository.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';
import 'package:techpie/features/campus_card/domain/ports/offline_ports.dart';

void main() {
  final now = DateTime.utc(2026, 8, 31, 12);

  test('watch export preserves shared credentials without consuming a use', () async {
    final fixture = await _fixture(now: now, totalUses: null);
    addTearDown(fixture.service.dispose);
    final exported = await fixture.service.exportForWatch('DEMO-CARD');
    expect(exported, isNotNull);
    final originalKey = await fixture.credentials.readPrivateKey('DEMO-CARD', deviceCode: 'DEMO-DEVICE-0001');
    expect(exported!.privateKey, originalKey);
    expect(exported.toMessage().containsKey('deviceCode'), isFalse);
    expect(exported.toMessage()['deviceChecksum'], Sm2OfflineCrypto.deviceChecksum('DEMO-DEVICE-0001'));
    expect(exported.toMessage()['expiresAt'], DateTime.utc(2026, 10, 1).millisecondsSinceEpoch / 1000);
    expect((await fixture.credentials.read('DEMO-CARD', deviceCode: 'DEMO-DEVICE-0001'))!.used, 0);
    expect(fixture.remote.activateCalls, 0);
    expect(fixture.remote.renewCalls, 0);
  });

  test('watch export rejects missing expiry, expired, bounded and removed grants', () async {
    for (final fixture in [
      await _fixture(now: now, expiresOn: null, totalUses: null),
      await _fixture(now: now, expiresOn: DateTime.utc(2026, 8, 30), totalUses: null),
      await _fixture(now: now, totalUses: 20),
    ]) {
      expect(await fixture.service.exportForWatch('DEMO-CARD'), isNull);
      await fixture.service.dispose();
    }
    final fixture = await _fixture(now: now, totalUses: null);
    await fixture.service.removeAllFromThisDevice();
    expect(await fixture.service.exportForWatch('DEMO-CARD'), isNull);
    await fixture.service.dispose();
  });

  test('generating reserves the use before calculating the QR', () async {
    final fixture = await _fixture(now: now, authorInfo: 'NOT-HEX');

    await expectLater(
      fixture.service.generate('DEMO-CARD'),
      throwsFormatException,
    );
    expect(
      (await fixture.credentials.read(
        'DEMO-CARD',
        deviceCode: 'DEMO-DEVICE-0001',
      ))!
          .used,
      1,
    );
  });

  test(
    'an authorization without expiry remains usable but is renewal due',
    () async {
      final fixture = await _fixture(now: now, expiresOn: null);
      fixture.connectivity.setOnline(false);

      final view = await fixture.service.status('DEMO-CARD');
      expect(view.state, OfflineAuthorizationState.renewalDue);
      final code = await fixture.service.generate('DEMO-CARD');
      expect(code.reservedUse, 1);
    },
  );

  test('blocks an expired authorization without burning a use', () async {
    final fixture = await _fixture(
      now: now,
      expiresOn: DateTime.utc(2026, 8, 30),
    );

    try {
      await fixture.service.generate('DEMO-CARD');
      fail('Expected expiration failure');
    } on AppFailure catch (failure) {
      expect(failure.kind, FailureKind.offlineAuthorizationExpired);
    }
    expect(
      (await fixture.credentials.read(
        'DEMO-CARD',
        deviceCode: 'DEMO-DEVICE-0001',
      ))!
          .used,
      0,
    );
  });

  test(
    'unlimited authorization never exhausts or increments a counter',
    () async {
      final fixture = await _fixture(now: now, totalUses: null);

      final first = await fixture.service.generate('DEMO-CARD');
      final second = await fixture.service.generate('DEMO-CARD');
      final stored = await fixture.credentials.read(
        'DEMO-CARD',
        deviceCode: 'DEMO-DEVICE-0001',
      );

      expect(first.reservedUse, 0);
      expect(second.reservedUse, 0);
      expect(stored!.totalUses, isNull);
      expect(stored.used, 0);
      expect(
        (await fixture.service.status('DEMO-CARD')).state,
        isNot(OfflineAuthorizationState.exhausted),
      );
    },
  );

  test('renews at the inclusive four-day threshold when online', () async {
    final remote = _Remote(
      renewal: OfflineActivationResponse(
        authorInfo: '5638FFEEDDCCBBAA',
        totalUses: 20,
        expiresOn: DateTime.utc(2026, 10, 1),
      ),
    );
    final fixture = await _fixture(
      now: now,
      expiresOn: DateTime.utc(2026, 9, 4),
      remote: remote,
    );
    await fixture.credentials.reserveUse(
      'DEMO-CARD',
      deviceCode: 'DEMO-DEVICE-0001',
    );

    final renewed = await fixture.service.renew('DEMO-CARD');

    expect(remote.renewCalls, 1);
    expect(renewed.authorInfo, '5638FFEEDDCCBBAA');
    expect(renewed.expiresOn, DateTime.utc(2026, 10, 1));
    expect(renewed.used, 0);
  });

  test('forced startup renewal runs before the renewal window', () async {
    final remote = _Remote(
      renewal: OfflineActivationResponse(
        authorInfo: '5638FFEEDDCCBBAA',
        totalUses: 20,
        expiresOn: DateTime.utc(2026, 10, 31),
      ),
    );
    final fixture = await _fixture(
      now: now,
      expiresOn: DateTime.utc(2026, 9, 30),
      remote: remote,
    );

    final renewed = await fixture.service.renew('DEMO-CARD', force: true);

    expect(remote.renewCalls, 1);
    expect(renewed.expiresOn, DateTime.utc(2026, 10, 31));
  });

  test('concurrent renewals share one upstream request', () async {
    final completer = Completer<OfflineActivationResponse?>();
    final remote = _Remote(renewalCompleter: completer);
    final fixture = await _fixture(
      now: now,
      expiresOn: DateTime.utc(2026, 9, 4),
      remote: remote,
    );

    final first = fixture.service.renew('DEMO-CARD');
    final second = fixture.service.renew('DEMO-CARD');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(remote.renewCalls, 1);
    completer.complete(
      OfflineActivationResponse(
        authorInfo: '5638FFEEDDCCBBAA',
        totalUses: 20,
        expiresOn: DateTime.utc(2026, 10, 1),
      ),
    );
    final values = await Future.wait([first, second]);
    expect(values[0].authorInfo, values[1].authorInfo);
  });

  test(
    'activation retries one transient failure with the same generated keys',
    () async {
      final remote = _Remote(
        activationFailures: const [
          AppFailure(
            FailureKind.network,
            'temporary',
            code: 'NETWORK_UNREACHABLE',
            retryable: true,
          ),
        ],
      );
      final fixture = await _fixture(
        now: now,
        remote: remote,
        transientRetryDelay: Duration.zero,
      );
      await fixture.credentials.remove('DEMO-CARD');

      final authorization = await fixture.service.activate(cardId: 'DEMO-CARD');

      expect(authorization.cardId, 'DEMO-CARD');
      expect(remote.activateCalls, 2);
      expect(remote.activationRequests, hasLength(2));
      expect(
        remote.activationRequests[0].publicKeyCompressed,
        remote.activationRequests[1].publicKeyCompressed,
      );
      expect(
        remote.activationRequests[0].privateKeyHex,
        remote.activationRequests[1].privateKeyHex,
      );
    },
  );

  test('activation does not retry a business or protocol failure', () async {
    final remote = _Remote(
      activationFailures: const [
        AppFailure(
          FailureKind.server,
          'rejected',
          code: 'OFFLINE_ACTIVATION_REJECTED',
        ),
      ],
    );
    final fixture = await _fixture(
      now: now,
      remote: remote,
      transientRetryDelay: Duration.zero,
    );
    await fixture.credentials.remove('DEMO-CARD');

    await expectLater(
      fixture.service.activate(cardId: 'DEMO-CARD'),
      throwsA(isA<AppFailure>()),
    );
    expect(remote.activateCalls, 1);
  });

  test(
    'offline renewal check preserves a still usable authorization',
    () async {
      final fixture = await _fixture(
        now: now,
        expiresOn: DateTime.utc(2026, 9, 2),
      );
      fixture.connectivity.setOnline(false);

      final value = await fixture.service.renew('DEMO-CARD');

      expect(value.authorInfo, '5638A1B2C3D4');
      expect(fixture.remote.renewCalls, 0);
    },
  );
}

Future<_Fixture> _fixture({
  required DateTime now,
  Object? expiresOn = const _DefaultExpiry(),
  String authorInfo = '5638A1B2C3D4',
  int? totalUses = 20,
  _Remote? remote,
  Duration transientRetryDelay = Duration.zero,
}) async {
  final store = InMemorySecureCredentialStore();
  final credentials = SecureOfflineCredentialRepository(store);
  final crypto = Sm2OfflineCrypto(random: Random(99));
  final keyPair = crypto.generateKeyPair();
  final DateTime? resolvedExpiry = expiresOn is _DefaultExpiry
      ? DateTime.utc(2026, 9, 30)
      : expiresOn as DateTime?;
  await credentials.install(
    authorization: OfflineAuthorization(
      cardId: 'DEMO-CARD',
      deviceCode: 'DEMO-DEVICE-0001',
      publicKeyCompressed: keyPair.publicKeyCompressed,
      authorInfo: authorInfo,
      totalUses: totalUses,
      used: 0,
      updatedAt: now,
      expiresOn: resolvedExpiry,
    ),
    privateKeyHex: keyPair.privateKeyHex,
  );
  final connectivity = InMemoryConnectivityPort();
  final resolvedRemote = remote ?? _Remote();
  return _Fixture(
    credentials: credentials,
    connectivity: connectivity,
    remote: resolvedRemote,
    service: OfflinePaymentService(
      credentials: credentials,
      remote: resolvedRemote,
      connectivity: connectivity,
      crypto: crypto,
      deviceCodeReader: () async => 'DEMO-DEVICE-0001',
      clock: Clock.fixed(now),
      transientRetryDelay: transientRetryDelay,
    ),
  );
}

final class _DefaultExpiry {
  const _DefaultExpiry();
}

final class _Fixture {
  const _Fixture({
    required this.service,
    required this.credentials,
    required this.connectivity,
    required this.remote,
  });
  final OfflinePaymentService service;
  final SecureOfflineCredentialRepository credentials;
  final InMemoryConnectivityPort connectivity;
  final _Remote remote;
}

final class _Remote implements OfflineAuthorizationRemotePort {
  _Remote({
    this.renewal,
    this.renewalCompleter,
    this.activationFailures = const [],
  });
  final OfflineActivationResponse? renewal;
  final Completer<OfflineActivationResponse?>? renewalCompleter;
  final List<AppFailure> activationFailures;
  final List<OfflineActivationRequest> activationRequests = [];
  int activateCalls = 0;
  int renewCalls = 0;

  @override
  Future<OfflineActivationResponse> activate(
    OfflineActivationRequest request,
  ) async {
    activationRequests.add(request);
    final failureIndex = activateCalls;
    activateCalls += 1;
    if (failureIndex < activationFailures.length) {
      throw activationFailures[failureIndex];
    }
    return const OfflineActivationResponse(
      authorInfo: '5638AABB',
      totalUses: 20,
    );
  }

  @override
  Future<OfflineActivationResponse?> renew(
    OfflineAuthorization authorization,
  ) async {
    renewCalls += 1;
    final pending = renewalCompleter;
    if (pending != null) return pending.future;
    return renewal;
  }
}
