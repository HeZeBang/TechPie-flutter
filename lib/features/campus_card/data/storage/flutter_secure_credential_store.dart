import 'dart:convert';

// TechPie ships the OpenHarmony hard fork directly. Importing the upstream
// facade would fall through to an unsupported platform on OHOS.
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:techpie/utils/secure_storage.dart';

import '../../core/async_mutex.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/ports/credential_store.dart';

final class FlutterSecureCredentialStore implements SecureCredentialStore {
  FlutterSecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;
  static final _storageMutex = AsyncMutex();
  static const _journalKey = 'geekpay.secure.journal';

  Future<T> _withStorage<T>(Future<T> Function() operation) =>
      _guardPlatformStorage(
        () => _storageMutex.protect(() async {
          await _recoverInterruptedUpdate();
          return operation();
        }),
      );

  @override
  Future<String?> read(String key) =>
      _withStorage(() => _storage.read(key: key));

  @override
  Future<void> write(String key, String value) =>
      _withStorage(() => _storage.write(key: key, value: value));

  @override
  Future<void> delete(String key) =>
      _withStorage(() => _storage.delete(key: key));

  @override
  Future<void> deleteAll(Iterable<String> keys) => _withStorage(() async {
        for (final key in keys) {
          await _storage.delete(key: key);
        }
      });

  @override
  Future<void> replaceAtomically(Map<String, String?> values) {
    final replacement = Map<String, String?>.unmodifiable(values);
    return _withStorage(() async {
      final before = <String, String?>{};
      for (final key in replacement.keys) {
        before[key] = await _storage.read(key: key);
      }
      // The rollback snapshot is encrypted by the same secure store as the
      // credentials. Readers restore the last complete session after interruption.
      await _storage.write(
        key: _journalKey,
        value: jsonEncode({'version': 1, 'before': before}),
      );
      for (final entry in replacement.entries) {
        if (entry.value == null) {
          await _storage.delete(key: entry.key);
        } else {
          await _storage.write(key: entry.key, value: entry.value);
        }
      }
      await _storage.delete(key: _journalKey);
    });
  }

  Future<void> _recoverInterruptedUpdate() async {
    final raw = await _storage.read(key: _journalKey);
    if (raw == null) return;
    final Map<String, String?> rollback;
    try {
      final journal = jsonDecode(raw) as Map<String, dynamic>;
      if (journal['version'] == 1 && journal['before'] is Map) {
        rollback = Map<String, String?>.from(journal['before'] as Map);
      } else if (!journal.containsKey('version') && journal['keys'] is List) {
        // Legacy journals have no committed snapshot to restore.
        rollback = {
          for (final key in List<String>.from(journal['keys'] as List))
            key: null,
        };
      } else {
        throw const FormatException('Invalid credential journal');
      }
      if (rollback.keys.any(
        (key) =>
            key == _journalKey ||
            (!key.startsWith('geekpay.') && !key.startsWith('offline.bundle.')),
      )) {
        throw const FormatException('Invalid credential journal scope');
      }
    } catch (_) {
      throw const AppFailure(
        FailureKind.unavailable,
        '安全存储状态不完整，无法读取校园卡凭证。',
        code: 'SECURE_STORAGE_INVALID_JOURNAL',
      );
    }
    for (final entry in rollback.entries) {
      if (entry.value == null) {
        await _storage.delete(key: entry.key);
      } else {
        await _storage.write(key: entry.key, value: entry.value);
      }
    }
    await _storage.delete(key: _journalKey);
  }

  static Future<T> _guardPlatformStorage<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      final missingEntitlement =
          error.code == 'Unexpected security result code' &&
              error.details == -34018;
      throw AppFailure(
        missingEntitlement
            ? FailureKind.permissionDenied
            : FailureKind.unavailable,
        missingEntitlement ? 'iOS 安全存储权限无效，请安装正确签名的应用。' : '无法访问安全存储，请重试。',
        code: missingEntitlement
            ? 'IOS_KEYCHAIN_MISSING_ENTITLEMENT'
            : 'SECURE_STORAGE_UNAVAILABLE',
        retryable: !missingEntitlement,
        cause: error,
      );
    }
  }
}

final class SecureSessionCredentialStore implements SessionCredentialStore {
  SecureSessionCredentialStore(this._store);

  static const _sessionKey = 'geekpay.auth.session_cookie';
  static const _lastActivityKey = 'geekpay.auth.last_activity';
  static const _openIdKey = 'geekpay.auth.openid';
  static const _channelKey = 'geekpay.auth.openid_channel';
  static const _orgIdKey = 'geekpay.auth.orgid';
  static const _verifiedIdSerialKey = 'geekpay.auth.verified_idserial';
  static const _verifiedCardIdKey = 'geekpay.auth.verified_cardid';

  final SecureCredentialStore _store;

  @override
  Future<String?> readSessionCookie() => _store.read(_sessionKey);

  @override
  Future<DateTime?> readSessionLastActivity() async {
    final value = await _store.read(_lastActivityKey);
    return value == null ? null : DateTime.tryParse(value)?.toUtc();
  }

  @override
  Future<void> writeSessionLastActivity(DateTime value) =>
      _store.write(_lastActivityKey, value.toUtc().toIso8601String());

  @override
  Future<String?> readOpenId() => _store.read(_openIdKey);

  @override
  Future<EcardOpenIdChannel> readOpenIdChannel() async => EcardOpenIdChannel.parse(await _store.read(_channelKey));

  @override
  Future<String?> readOrgId() => _store.read(_orgIdKey);

  @override
  Future<String?> readVerifiedIdSerial() => _store.read(_verifiedIdSerialKey);

  @override
  Future<String?> readVerifiedCardId() => _store.read(_verifiedCardIdKey);

  @override
  Future<void> writeSession({
    required String sessionCookie,
    required String openId,
    required String orgId,
    required String verifiedIdSerial,
    required String verifiedCardId,
    DateTime? lastActivityAt,
    EcardOpenIdChannel channel = EcardOpenIdChannel.wechat,
  }) =>
      _store.replaceAtomically({
        _sessionKey: sessionCookie,
        _lastActivityKey: (lastActivityAt ?? DateTime.now()).toUtc().toIso8601String(),
        _openIdKey: openId,
        _channelKey: channel.method,
        _orgIdKey: orgId,
        _verifiedIdSerialKey: verifiedIdSerial,
        _verifiedCardIdKey: verifiedCardId,
      });

  @override
  Future<void> stageOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) => _store.replaceAtomically({
    _openIdKey: openId, _channelKey: channel.method, _orgIdKey: '2', _sessionKey: null, _lastActivityKey: null,
    _verifiedIdSerialKey: null, _verifiedCardIdKey: null,
  });

  @override
  Future<void> clearSessionCookie() =>
      _store.replaceAtomically({_sessionKey: null, _lastActivityKey: null});

  @override
  Future<void> clear() => _store.replaceAtomically({
        _sessionKey: null,
        _lastActivityKey: null,
        _openIdKey: null,
        _channelKey: null,
        _orgIdKey: null,
        _verifiedIdSerialKey: null,
        _verifiedCardIdKey: null,
      });
}
