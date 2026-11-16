import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/async_mutex.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/models/offline_models.dart';
import '../../domain/ports/credential_store.dart';
import '../../domain/ports/offline_ports.dart';

final class SecureOfflineCredentialRepository
    implements OfflineCredentialRepository {
  SecureOfflineCredentialRepository(this._store);

  static const _indexKey = 'offline.bundle.index.v1';

  final SecureCredentialStore _store;
  // Bundle updates and account-wide removal share an ordering boundary.
  final AsyncMutex _mutationMutex = AsyncMutex();

  String _bundleKey(String cardId) =>
      'offline.bundle.v1.${sha256.convert(utf8.encode(cardId))}';

  @override
  Future<OfflineAuthorization?> read(
    String cardId, {
    required String deviceCode,
  }) async {
    final bundle = await _readBundle(cardId, expectedDeviceCode: deviceCode);
    return bundle?.authorization;
  }

  @override
  Future<OfflineAuthorization?> readMostRecent({
    required String deviceCode,
  }) async {
    final index = await _readIndex();
    _OfflineBundle? newest;
    for (final key in index) {
      final raw = await _store.read(key);
      if (raw == null) continue;
      try {
        final candidate = _decodeBundle(raw);
        if (candidate.authorization.deviceCode != deviceCode) continue;
        if (newest == null ||
            candidate.authorization.updatedAt.isAfter(
              newest.authorization.updatedAt,
            )) {
          newest = candidate;
        }
      } catch (_) {
        // One damaged historical bundle must not hide another usable grant.
      }
    }
    return newest?.authorization;
  }

  @override
  Future<String?> readPrivateKey(
    String cardId, {
    required String deviceCode,
  }) async {
    final bundle = await _readBundle(cardId, expectedDeviceCode: deviceCode);
    return bundle?.privateKeyHex;
  }

  @override
  Future<void> install({
    required OfflineAuthorization authorization,
    required String privateKeyHex,
  }) =>
      _mutationMutex.protect(() async {
        _validatePrivateKey(privateKeyHex);
        final key = _bundleKey(authorization.cardId);
        await _store.write(key, _encodeBundle(authorization, privateKeyHex));
        final index = await _readIndex()
          ..add(key);
        await _store.write(_indexKey, jsonEncode(index.toList()..sort()));
      });

  @override
  Future<OfflineAuthorization> reserveUse(
    String cardId, {
    required String deviceCode,
  }) =>
      _mutationMutex.protect(() async {
        final bundle = await _readBundle(
          cardId,
          expectedDeviceCode: deviceCode,
        );
        if (bundle == null) {
          throw const AppFailure(
            FailureKind.credentialMissing,
            '此设备没有可用的离线付款授权。',
            code: 'OFFLINE_CREDENTIAL_MISSING',
          );
        }
        final totalUses = bundle.authorization.totalUses;
        if (totalUses != null && bundle.authorization.used >= totalUses) {
          throw const AppFailure(
            FailureKind.offlineQuotaExhausted,
            '离线付款次数已用完，请联网续期。',
            code: 'OFFLINE_QUOTA_EXHAUSTED',
          );
        }
        if (totalUses == null) return bundle.authorization;
        final reserved = bundle.authorization.copyWith(
          used: bundle.authorization.used + 1,
        );
        // One secure-storage value contains authorization, counter, and key.
        // The increment completes before the reserved use is returned.
        await _store.write(
          _bundleKey(cardId),
          _encodeBundle(reserved, bundle.privateKeyHex),
        );
        return reserved;
      });

  @override
  Future<void> updateAuthorization(
    OfflineAuthorization authorization, {
    bool resetUsage = false,
  }) =>
      _mutationMutex.protect(() async {
        final bundle = await _readBundle(
          authorization.cardId,
          expectedDeviceCode: authorization.deviceCode,
        );
        if (bundle == null) {
          throw const AppFailure(
            FailureKind.credentialMissing,
            '此设备没有可用的离线付款授权。',
            code: 'OFFLINE_CREDENTIAL_MISSING',
          );
        }
        if (authorization.publicKeyCompressed !=
            bundle.authorization.publicKeyCompressed) {
          throw const AppFailure(
            FailureKind.cancelled,
            '离线付款授权已更新，请重试。',
            code: 'OFFLINE_CREDENTIAL_CHANGED',
          );
        }
        if (authorization.used < bundle.authorization.used && !resetUsage) {
          throw const AppFailure(
            FailureKind.protocol,
            '离线付款计数不能回退。',
            code: 'OFFLINE_COUNTER_ROLLBACK',
          );
        }
        await _store.write(
          _bundleKey(authorization.cardId),
          _encodeBundle(authorization, bundle.privateKeyHex),
        );
      });

  @override
  Future<void> remove(String cardId) => _mutationMutex.protect(() async {
        final key = _bundleKey(cardId);
        await _store.delete(key);
        final index = await _readIndex()
          ..remove(key);
        if (index.isEmpty) {
          await _store.delete(_indexKey);
        } else {
          await _store.write(_indexKey, jsonEncode(index.toList()..sort()));
        }
      });

  @override
  Future<void> removeAll() => _mutationMutex.protect(() async {
        final index = await _readIndex();
        await _store.deleteAll({...index, _indexKey});
      });

  Future<_OfflineBundle?> _readBundle(
    String cardId, {
    String? expectedDeviceCode,
  }) async {
    final raw = await _store.read(_bundleKey(cardId));
    if (raw == null) return null;
    try {
      return _decodeBundle(
        raw,
        expectedCardId: cardId,
        expectedDeviceCode: expectedDeviceCode,
      );
    } catch (error) {
      if (error is AppFailure) rethrow;
      throw AppFailure(
        FailureKind.credentialMissing,
        '离线付款授权已损坏，请联网重新开通。',
        code: 'OFFLINE_CREDENTIAL_CORRUPT',
        cause: error,
      );
    }
  }

  _OfflineBundle _decodeBundle(
    String raw, {
    String? expectedCardId,
    String? expectedDeviceCode,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    final storedCardId = decoded['cardId'] as String;
    if (storedCardId.isEmpty ||
        (expectedCardId != null && storedCardId != expectedCardId)) {
      throw const FormatException();
    }
    final privateKeyHex = decoded['privateKeyHex'] as String;
    _validatePrivateKey(privateKeyHex);
    final storedDeviceCode = decoded['deviceCode'] as String;
    if (storedDeviceCode.isEmpty) throw const FormatException();
    if (expectedDeviceCode != null && storedDeviceCode != expectedDeviceCode) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '离线付款授权不属于当前登录账户，已停止使用。',
        code: 'OFFLINE_IDENTITY_MISMATCH',
      );
    }
    final expiresRaw = decoded['expiresOn'] as String?;
    final storedTotal = decoded['totalUses'];
    final totalUses =
        storedTotal is int && storedTotal > 0 ? storedTotal : null;
    return _OfflineBundle(
      authorization: OfflineAuthorization(
        cardId: storedCardId,
        deviceCode: storedDeviceCode,
        publicKeyCompressed: decoded['publicKeyCompressed'] as String,
        authorInfo: decoded['authorInfo'] as String,
        totalUses: totalUses,
        used: decoded['used'] as int,
        updatedAt: DateTime.parse(decoded['updatedAt'] as String),
        expiresOn: expiresRaw == null ? null : DateTime.parse(expiresRaw),
      ),
      privateKeyHex: privateKeyHex,
    );
  }

  String _encodeBundle(
    OfflineAuthorization authorization,
    String privateKeyHex,
  ) =>
      jsonEncode({
        'version': 1,
        'cardId': authorization.cardId,
        'deviceCode': authorization.deviceCode,
        'publicKeyCompressed': authorization.publicKeyCompressed,
        'authorInfo': authorization.authorInfo,
        'totalUses': authorization.totalUses,
        'used': authorization.used,
        'updatedAt': authorization.updatedAt.toUtc().toIso8601String(),
        'expiresOn': authorization.expiresOn?.toUtc().toIso8601String(),
        'privateKeyHex': privateKeyHex,
      });

  Future<Set<String>> _readIndex() async {
    final raw = await _store.read(_indexKey);
    if (raw == null) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException();
      return decoded.map((value) => value.toString()).toSet();
    } catch (error) {
      throw AppFailure(
        FailureKind.credentialMissing,
        '离线付款授权索引已损坏，请移除此设备后重试。',
        code: 'OFFLINE_INDEX_CORRUPT',
        cause: error,
      );
    }
  }

  void _validatePrivateKey(String value) {
    if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(value)) {
      throw const AppFailure(
        FailureKind.credentialMissing,
        '离线付款私钥无效。',
        code: 'OFFLINE_PRIVATE_KEY_INVALID',
      );
    }
  }
}

final class _OfflineBundle {
  const _OfflineBundle({
    required this.authorization,
    required this.privateKeyHex,
  });
  final OfflineAuthorization authorization;
  final String privateKeyHex;
}
