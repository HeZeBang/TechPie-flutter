import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/sync_envelope.dart';

ThirdPartyAccount _acc({
  required ThirdPartyPlatform platform,
  String token = 't',
  DateTime? updatedAt,
  String deviceId = '',
  DateTime? boundAt,
}) {
  final b = boundAt ?? DateTime.utc(2026);
  return ThirdPartyAccount(
    platform: platform,
    account: 'a',
    token: token,
    boundAt: b,
    updatedAt: updatedAt ?? b,
    deviceId: deviceId,
  );
}

void main() {
  group('SyncSchema.migrate', () {
    test('v0 bare array is wrapped into a v2 envelope', () {
      final v0 = jsonEncode([
        {'platform': 'gradescope', 'account': 'a', 'token': 't1'},
      ]);
      final env = SyncEnvelope.decode(v0);
      expect(env, isNotNull);
      expect(env!.v, SyncSchema.current);
      expect(env.accounts, hasLength(1));
      expect(env.accounts.first.platform, ThirdPartyPlatform.gradescope);
      expect(env.accounts.first.token, 't1');
      expect(env.tombstones, isEmpty);
      // v0 accounts have no updatedAt/deviceId → back-compat defaults.
      expect(env.accounts.first.deviceId, '');
    });

    test('v1 envelope (no tombstones) migrates to v2 with empty tombstones', () {
      final v1 = jsonEncode({
        'v': 1,
        'accounts': [
          {'platform': 'hydro', 'account': 'h', 'token': 'tok'},
        ],
      });
      final env = SyncEnvelope.decode(v1);
      expect(env!.v, SyncSchema.current);
      expect(env.accounts.first.platform, ThirdPartyPlatform.hydro);
      expect(env.tombstones, isEmpty);
    });

    test('v2 envelope round-trips accounts + tombstones', () {
      final original = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.cpdaily,
            token: 'tgc',
            updatedAt: DateTime.utc(2026, 1, 2),
            deviceId: 'devA',
          ),
        ],
        tombstones: [
          SyncTombstone(
            platform: ThirdPartyPlatform.gradescope,
            deletedAt: DateTime.utc(2026, 1, 3),
            deviceId: 'devB',
          ),
        ],
      );
      final decoded = SyncEnvelope.decode(original.encode());
      expect(decoded!.v, SyncSchema.current);
      expect(decoded.accounts, hasLength(1));
      expect(decoded.accounts.first.token, 'tgc');
      expect(decoded.accounts.first.deviceId, 'devA');
      expect(decoded.tombstones, hasLength(1));
      expect(decoded.tombstones.first.platform, ThirdPartyPlatform.gradescope);
      expect(decoded.tombstones.first.deviceId, 'devB');
    });

    test('garbage plaintext returns null', () {
      expect(SyncEnvelope.decode('not json'), isNull);
      expect(SyncEnvelope.decode('123'), isNull);
    });
  });

  group('SyncEnvelope.mergeWith (LWW)', () {
    test('newer local account wins over older remote', () {
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.gradescope,
            token: 'local-new',
            updatedAt: DateTime.utc(2026, 1, 5),
            deviceId: 'A',
          ),
        ],
        tombstones: const [],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.gradescope,
            token: 'remote-old',
            updatedAt: DateTime.utc(2026, 1, 1),
            deviceId: 'B',
          ),
        ],
        tombstones: const [],
      );
      final merged = local.mergeWith(remote);
      expect(merged.accounts, hasLength(1));
      expect(merged.accounts.first.token, 'local-new');
    });

    test('remote account on a platform absent locally is adopted', () {
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: const [],
        tombstones: const [],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.hydro,
            token: 'remote-only',
            updatedAt: DateTime.utc(2026, 1, 1),
            deviceId: 'B',
          ),
        ],
        tombstones: const [],
      );
      final merged = local.mergeWith(remote);
      expect(merged.accounts, hasLength(1));
      expect(merged.accounts.first.token, 'remote-only');
    });

    test('tombstone newer than account removes the account', () {
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: const [],
        tombstones: [
          SyncTombstone(
            platform: ThirdPartyPlatform.gradescope,
            deletedAt: DateTime.utc(2026, 1, 5),
            deviceId: 'A',
          ),
        ],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.gradescope,
            token: 'stale',
            updatedAt: DateTime.utc(2026, 1, 1),
            deviceId: 'B',
          ),
        ],
        tombstones: const [],
      );
      final merged = local.mergeWith(remote);
      expect(merged.accounts, isEmpty);
      expect(merged.tombstones, hasLength(1));
      expect(merged.tombstones.first.platform, ThirdPartyPlatform.gradescope);
    });

    test('account newer than tombstone resurrects the account', () {
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.hydro,
            token: 'rebind',
            updatedAt: DateTime.utc(2026, 1, 10),
            deviceId: 'A',
          ),
        ],
        tombstones: const [],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: const [],
        tombstones: [
          SyncTombstone(
            platform: ThirdPartyPlatform.hydro,
            deletedAt: DateTime.utc(2026, 1, 1),
            deviceId: 'B',
          ),
        ],
      );
      final merged = local.mergeWith(remote);
      expect(merged.accounts, hasLength(1));
      expect(merged.accounts.first.token, 'rebind');
      // Old tombstone is dropped — the account won.
      expect(merged.tombstones, isEmpty);
    });

    test('equal timestamps tie-break by deviceId (larger wins)', () {
      final ts = DateTime.utc(2026, 1, 1);
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.cpdaily,
            token: 'A',
            updatedAt: ts,
            deviceId: 'aaa',
          ),
        ],
        tombstones: const [],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.cpdaily,
            token: 'B',
            updatedAt: ts,
            deviceId: 'zzz',
          ),
        ],
        tombstones: const [],
      );
      final merged = local.mergeWith(remote);
      // 'zzz' > 'aaa' → remote wins.
      expect(merged.accounts.first.token, 'B');
    });

    test('empty deviceId always loses to a real one', () {
      final ts = DateTime.utc(2026, 1, 1);
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.cpdaily,
            token: 'legacy',
            updatedAt: ts,
            deviceId: '',
          ),
        ],
        tombstones: const [],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.cpdaily,
            token: 'real',
            updatedAt: ts,
            deviceId: 'dev',
          ),
        ],
        tombstones: const [],
      );
      final merged = local.mergeWith(remote);
      expect(merged.accounts.first.token, 'real');
    });

    test('independent platforms on both sides are both kept', () {
      final local = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.gradescope,
            token: 'gs',
            updatedAt: DateTime.utc(2026, 1, 1),
            deviceId: 'A',
          ),
        ],
        tombstones: const [],
      );
      final remote = SyncEnvelope(
        v: SyncSchema.current,
        accounts: [
          _acc(
            platform: ThirdPartyPlatform.hydro,
            token: 'hy',
            updatedAt: DateTime.utc(2026, 1, 1),
            deviceId: 'B',
          ),
        ],
        tombstones: const [],
      );
      final merged = local.mergeWith(remote);
      expect(merged.accounts, hasLength(2));
      final platforms = merged.accounts.map((a) => a.platform).toSet();
      expect(platforms, contains(ThirdPartyPlatform.gradescope));
      expect(platforms, contains(ThirdPartyPlatform.hydro));
    });
  });
}
