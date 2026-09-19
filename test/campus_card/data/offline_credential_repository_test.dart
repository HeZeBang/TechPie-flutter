import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/crypto/sm2_offline_crypto.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/secure_offline_credential_repository.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';

void main() {
  group('SecureOfflineCredentialRepository', () {
    late InMemorySecureCredentialStore store;
    late SecureOfflineCredentialRepository repository;
    late String privateKey;

    setUp(() {
      store = InMemorySecureCredentialStore();
      repository = SecureOfflineCredentialRepository(store);
      privateKey = Sm2OfflineCrypto(
        random: Random(1),
      ).generateKeyPair().privateKeyHex;
    });

    test('atomically reserves unique uses before returning', () async {
      await repository.install(
        authorization: _authorization(total: 10),
        privateKeyHex: privateKey,
      );

      final reserved = await Future.wait([
        for (var index = 0; index < 6; index++)
          repository.reserveUse('DEMO-CARD', deviceCode: 'DEMO-DEVICE'),
      ]);

      expect(reserved.map((value) => value.used).toSet(), {1, 2, 3, 4, 5, 6});
      expect(
        (await repository.read('DEMO-CARD', deviceCode: 'DEMO-DEVICE'))!.used,
        6,
      );
    });

    test('failed durable write does not expose a reservation', () async {
      await repository.install(
        authorization: _authorization(total: 2),
        privateKeyHex: privateKey,
      );
      store.failNextWrite = true;

      await expectLater(
        repository.reserveUse('DEMO-CARD', deviceCode: 'DEMO-DEVICE'),
        throwsStateError,
      );
      expect(
        (await repository.read('DEMO-CARD', deviceCode: 'DEMO-DEVICE'))!.used,
        0,
      );
    });

    test(
      'a newly constructed repository observes the committed count',
      () async {
        await repository.install(
          authorization: _authorization(total: 2),
          privateKeyHex: privateKey,
        );
        await repository.reserveUse('DEMO-CARD', deviceCode: 'DEMO-DEVICE');

        final afterRestart = SecureOfflineCredentialRepository(store);
        expect(
          (await afterRestart.read(
            'DEMO-CARD',
            deviceCode: 'DEMO-DEVICE',
          ))!
              .used,
          1,
        );
        expect(
          await afterRestart.readPrivateKey(
            'DEMO-CARD',
            deviceCode: 'DEMO-DEVICE',
          ),
          privateKey,
        );
      },
    );

    test('never permits counter rollback during renewal', () async {
      await repository.install(
        authorization: _authorization(total: 3),
        privateKeyHex: privateKey,
      );
      await repository.reserveUse('DEMO-CARD', deviceCode: 'DEMO-DEVICE');

      await expectLater(
        repository.updateAuthorization(_authorization(total: 3, used: 0)),
        throwsA(isA<Exception>()),
      );
    });

    test('removes the private key and authorization together', () async {
      await repository.install(
        authorization: _authorization(total: 2),
        privateKeyHex: privateKey,
      );
      await repository.remove('DEMO-CARD');

      expect(
        await repository.read('DEMO-CARD', deviceCode: 'DEMO-DEVICE'),
        isNull,
      );
      expect(
        await repository.readPrivateKey(
          'DEMO-CARD',
          deviceCode: 'DEMO-DEVICE',
        ),
        isNull,
      );
    });

    test('concurrent renewal cannot restore an authorization after logout',
        () async {
      await repository.install(
        authorization: _authorization(total: 2),
        privateKeyHex: privateKey,
      );

      await Future.wait([
        repository.updateAuthorization(
          _authorization(total: 3),
          resetUsage: true,
        ),
        repository.removeAll(),
      ]);

      expect(
        await repository.read('DEMO-CARD', deviceCode: 'DEMO-DEVICE'),
        isNull,
      );
      expect(
        await repository.readPrivateKey('DEMO-CARD', deviceCode: 'DEMO-DEVICE'),
        isNull,
      );
      expect(
        await repository.readMostRecent(deviceCode: 'DEMO-DEVICE'),
        isNull,
      );
    });

    test('never exposes an offline grant to another OPENID', () async {
      await repository.install(
        authorization: _authorization(total: 2),
        privateKeyHex: privateKey,
      );

      expect(
        (await repository.readMostRecent(deviceCode: 'DEMO-DEVICE'))!.cardId,
        'DEMO-CARD',
      );
      expect(
        await repository.readMostRecent(deviceCode: 'OTHER-OPENID'),
        isNull,
      );
      await expectLater(
        repository.read('DEMO-CARD', deviceCode: 'OTHER-OPENID'),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'OFFLINE_IDENTITY_MISMATCH',
          ),
        ),
      );
    });
  });
}

OfflineAuthorization _authorization({required int total, int used = 0}) =>
    OfflineAuthorization(
      cardId: 'DEMO-CARD',
      deviceCode: 'DEMO-DEVICE',
      publicKeyCompressed: '02${List.filled(64, 'A').join()}',
      authorInfo: '5638A1B2C3D4',
      totalUses: total,
      used: used,
      updatedAt: DateTime.utc(2026, 8, 31),
      expiresOn: DateTime.utc(2026, 9, 30),
    );
