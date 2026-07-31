import 'dart:convert';

import '../models/third_party_account.dart';

/// Schema version of the cloud-sync blob's plaintext envelope.
///
/// History:
///   v0 — legacy: a bare JSON array of [ThirdPartyAccount.toJson] objects,
///        no envelope. Auto-migrated to v1 on first read.
///   v1 — introduced the `{v, accounts}` envelope. No tombstones; deletions
///        were represented by absence (the "deleted binding resurrects on
///        next pull" bug). Auto-migrated to v2 on first read.
///   v2 — current: `{v, accounts, tombstones}`. Deletions carry a tombstone
///        so per-platform LWW merge can distinguish "deleted on device A"
///        from "never had it on device A". Per-account `updatedAt` +
///        `deviceId` drive the merge.
class SyncSchema {
  /// Current schema version produced by this build.
  static const int current = 2;

  SyncSchema._();

  /// Migrate a decoded plaintext JSON value to [current] and return the
  /// normalized envelope. Accepts any historical shape:
  ///   - a [List] (v0 bare array) → wrapped as v1 then migrated
  ///   - a [Map] with `v` → run the migration ladder up to [current]
  /// Returns `null` only if the input is structurally unrecognizable.
  static SyncEnvelope? migrate(dynamic decoded) {
    // v0: bare array of account objects.
    if (decoded is List) {
      final accounts = decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => ThirdPartyAccount.fromJson(e.cast<String, dynamic>()))
          .toList();
      return SyncEnvelope(
        v: current,
        accounts: accounts,
        tombstones: const [],
      );
    }
    if (decoded is! Map) return null;
    final m = decoded.cast<String, dynamic>();
    var v = (m['v'] as num?)?.toInt() ?? 1;
    // v1 → v2: add empty tombstones list. Accounts already carry
    // updatedAt/deviceId with back-compat defaults from fromJson.
    if (v < 2) {
      // Nothing to transform in the account objects themselves; the v2
      // shape only adds the tombstones field.
      v = 2;
    }
    final rawAccounts =
        m['accounts'] is List ? m['accounts'] as List : const <dynamic>[];
    final accounts = rawAccounts
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => ThirdPartyAccount.fromJson(e.cast<String, dynamic>()))
        .toList();
    final rawTombs =
        m['tombstones'] is List ? m['tombstones'] as List : const <dynamic>[];
    final tombstones = rawTombs
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => SyncTombstone.fromJson(e.cast<String, dynamic>()))
        .toList();
    return SyncEnvelope(v: current, accounts: accounts, tombstones: tombstones);
  }
}

/// A record that a platform was deliberately unbound on some device at
/// [deletedAt]. Used by the LWW merge so a deletion on device A is not
/// silently undone when device B (which never had the binding) pushes its
/// older state.
class SyncTombstone {
  final ThirdPartyPlatform platform;
  final DateTime deletedAt;
  final String deviceId;

  const SyncTombstone({
    required this.platform,
    required this.deletedAt,
    required this.deviceId,
  });

  /// Compare two tombstones by recency (newer wins); tie-break by deviceId
  /// identically to [ThirdPartyAccount.compareVersionTo].
  int compareVersionTo(SyncTombstone other) {
    final c = deletedAt.compareTo(other.deletedAt);
    if (c != 0) return c;
    if (deviceId.isEmpty && other.deviceId.isNotEmpty) return -1;
    if (deviceId.isNotEmpty && other.deviceId.isEmpty) return 1;
    return deviceId.compareTo(other.deviceId);
  }

  Map<String, dynamic> toJson() => {
        'platform': platform.id,
        'deletedAt': deletedAt.toIso8601String(),
        'deviceId': deviceId,
      };

  factory SyncTombstone.fromJson(Map<String, dynamic> json) {
    return SyncTombstone(
      platform:
          ThirdPartyPlatform.fromId(json['platform'] as String? ?? '') ??
              ThirdPartyPlatform.gradescope,
      deletedAt:
          DateTime.tryParse(json['deletedAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      deviceId: json['deviceId'] as String? ?? '',
    );
  }
}

/// The normalized cloud-sync plaintext: a versioned envelope of accounts +
/// deletion tombstones. Always at [SyncSchema.current] after [SyncSchema.migrate].
class SyncEnvelope {
  final int v;
  final List<ThirdPartyAccount> accounts;
  final List<SyncTombstone> tombstones;

  const SyncEnvelope({
    required this.v,
    required this.accounts,
    required this.tombstones,
  });

  String encode() => jsonEncode({
        'v': v,
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'tombstones': tombstones.map((t) => t.toJson()).toList(),
      });

  static SyncEnvelope? decode(String plaintext) {
    dynamic decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (_) {
      return null;
    }
    return SyncSchema.migrate(decoded);
  }

  /// Build an envelope from the local account list, preserving tombstones
  /// the caller already tracks. Accounts with no deviceId/updatedAt are
  /// left as-is — the caller is expected to have touched them.
  factory SyncEnvelope.fromLocal({
    required Iterable<ThirdPartyAccount> accounts,
    required Iterable<SyncTombstone> tombstones,
  }) {
    return SyncEnvelope(
      v: SyncSchema.current,
      accounts: accounts.toList(),
      tombstones: tombstones.toList(),
    );
  }

  /// Per-platform LWW merge of this (local) envelope with [remote] (cloud).
  ///
  /// For each platform in [ThirdPartyPlatform.values]:
  ///   - gather the local account (or its absence), the remote account (or
  ///     its absence), the local tombstone (if any), and the remote tombstone
  ///     (if any);
  ///   - pick the newest event across {account.updatedAt, tombstone.deletedAt}
  ///     using [ThirdPartyAccount.compareVersionTo] /
  ///     [SyncTombstone.compareVersionTo] with deviceId tie-break;
  ///   - if a tombstone wins, the platform is absent in the result and the
  ///     tombstone is carried forward;
  ///   - if an account wins, that account is in the result and any older
  ///     tombstone for the platform is dropped.
  ///
  /// Returns a new envelope at [SyncSchema.current]. The caller is responsible
  /// for applying the account side-effects locally and for pushing the merged
  /// envelope to the cloud.
  SyncEnvelope mergeWith(SyncEnvelope remote) {
    final localByPlatform = {
      for (final a in accounts) a.platform: a,
    };
    final remoteByPlatform = {
      for (final a in remote.accounts) a.platform: a,
    };
    final localTombByPlatform = {
      for (final t in tombstones) t.platform: t,
    };
    final remoteTombByPlatform = {
      for (final t in remote.tombstones) t.platform: t,
    };

    final mergedAccounts = <ThirdPartyAccount>[];
    final mergedTombstones = <SyncTombstone>[];

    for (final p in ThirdPartyPlatform.values) {
      final localAcc = localByPlatform[p];
      final remoteAcc = remoteByPlatform[p];
      final localTomb = localTombByPlatform[p];
      final remoteTomb = remoteTombByPlatform[p];

      // Collect candidate events: (kind, version-key, payload).
      // kind 0 = tombstone, kind 1 = account.
      final candidates = <_MergeCandidate>[];
      if (localAcc != null) {
        candidates.add(_MergeCandidate(1, localAcc.deviceId, localAcc.updatedAt, localAcc));
      }
      if (remoteAcc != null) {
        candidates.add(_MergeCandidate(1, remoteAcc.deviceId, remoteAcc.updatedAt, remoteAcc));
      }
      if (localTomb != null) {
        candidates.add(_MergeCandidate(0, localTomb.deviceId, localTomb.deletedAt, localTomb));
      }
      if (remoteTomb != null) {
        candidates.add(_MergeCandidate(0, remoteTomb.deviceId, remoteTomb.deletedAt, remoteTomb));
      }
      if (candidates.isEmpty) continue;

      candidates.sort((a, b) {
        final c = a.ts.compareTo(b.ts);
        if (c != 0) return c;
        // Empty deviceId loses; else lexicographic.
        final ad = a.deviceId, bd = b.deviceId;
        if (ad.isEmpty && bd.isNotEmpty) return -1;
        if (ad.isNotEmpty && bd.isEmpty) return 1;
        return ad.compareTo(bd);
      });

      // The sort put the newest event last (ts asc, then deviceId asc). The
      // winner is that last element. One policy override: if the newest
      // tombstone shares the winning (ts, deviceId) with an account, prefer
      // the tombstone (err toward not resurrecting a deletion).
      final winner = candidates.last;
      final hasAccount = candidates.any(
        (c) => c.kind == 1 && c.ts == winner.ts && c.deviceId == winner.deviceId,
      );
      final hasTomb = candidates.any(
        (c) =>
            c.kind == 0 && c.ts == winner.ts && c.deviceId == winner.deviceId,
      );
      if (winner.kind == 1 && hasTomb) {
        // Account won the sort but a tombstone shares its version key →
        // the tombstone wins by policy.
        final tomb = candidates.firstWhere(
          (c) =>
              c.kind == 0 &&
              c.ts == winner.ts &&
              c.deviceId == winner.deviceId,
        );
        mergedTombstones.add(tomb.payload as SyncTombstone);
      } else if (winner.kind == 0) {
        mergedTombstones.add(winner.payload as SyncTombstone);
      } else {
        mergedAccounts.add(winner.payload as ThirdPartyAccount);
      }
      // hasAccount is tracked for the policy check above; no further use.
      assert(hasAccount || winner.kind == 0);
    }

    return SyncEnvelope(
      v: SyncSchema.current,
      accounts: mergedAccounts,
      tombstones: mergedTombstones,
    );
  }

}

class _MergeCandidate {
  final int kind; // 0 = tombstone, 1 = account
  final String deviceId;
  final DateTime ts;
  final Object payload;
  _MergeCandidate(this.kind, this.deviceId, this.ts, this.payload);
}
