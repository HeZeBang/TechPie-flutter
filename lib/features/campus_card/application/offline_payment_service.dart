import 'dart:async';

import 'package:clock/clock.dart';

import '../core/async_mutex.dart';
import '../core/errors/app_failure.dart';
import '../data/api/qr_payload_codec.dart';
import '../data/crypto/sm2_offline_crypto.dart';
import '../domain/models/offline_models.dart';
import '../domain/models/watch_models.dart';
import '../domain/ports/offline_ports.dart';
import '../domain/ports/platform_ports.dart';

typedef OfflineDeviceCodeReader = Future<String?> Function();

final class OfflinePaymentService {
  OfflinePaymentService({
    required OfflineCredentialRepository credentials,
    required OfflineAuthorizationRemotePort remote,
    required ConnectivityPort connectivity,
    required Sm2OfflineCrypto crypto,
    required OfflineDeviceCodeReader deviceCodeReader,
    Clock? clock,
    Duration transientRetryDelay = const Duration(milliseconds: 180),
  })  : _credentials = credentials,
        _remote = remote,
        _connectivity = connectivity,
        _crypto = crypto,
        _deviceCodeReader = deviceCodeReader,
        _clock = clock ?? const Clock(),
        _transientRetryDelay = transientRetryDelay;

  final OfflineCredentialRepository _credentials;
  final OfflineAuthorizationRemotePort _remote;
  final ConnectivityPort _connectivity;
  final Sm2OfflineCrypto _crypto;
  final OfflineDeviceCodeReader _deviceCodeReader;
  final Clock _clock;
  final Duration _transientRetryDelay;
  final Map<String, Future<OfflineAuthorization>> _activations = {};
  final Map<String, Future<OfflineAuthorization>> _renewals = {};
  final _credentialChanges = AsyncMutex();
  int _removalGeneration = 0;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();

  /// Reads without consuming a presentation. Rechecks identity and grant after
  /// reading the separately exposed key to reject a concurrent renewal/sign-out.
  Future<WatchOfflineCredential?> exportForWatch(String cardId) async {
    final device = await _requireDeviceCode();
    final grant = await _credentials.read(cardId, deviceCode: device);
    if (grant == null || grant.expiresOn == null || grant.isLimited || _isExpired(grant.expiresOn)) {
      return null;
    }
    final key = await _credentials.readPrivateKey(cardId, deviceCode: device);
    final current = await _credentials.read(cardId, deviceCode: device);
    if (key == null ||
        current == null ||
        current.publicKeyCompressed != grant.publicKeyCompressed ||
        current.authorInfo != grant.authorInfo ||
        current.updatedAt != grant.updatedAt ||
        current.expiresOn != grant.expiresOn ||
        await _deviceCodeReader() != device) {
      return null;
    }
    return WatchOfflineCredential(grant, key, Sm2OfflineCrypto.deviceChecksum(device));
  }

  Future<OfflineAuthorization?> mostRecentAuthorization() async {
    final deviceCode = await _deviceCodeReader();
    if (deviceCode == null || deviceCode.isEmpty) return null;
    return _credentials.readMostRecent(deviceCode: deviceCode);
  }

  /// Describes a stored grant. Pure, so a caller that already holds the
  /// authorization and the key can describe it without reading secure storage
  /// again: every read here is a keystore round trip, and a payment tap must not
  /// pay for the same one four times.
  OfflineAuthorizationView viewOf(
    OfflineAuthorization? authorization, {
    required bool hasPrivateKey,
  }) {
    if (authorization == null || !hasPrivateKey) {
      return OfflineAuthorizationView(
        state: OfflineAuthorizationState.missingCredential,
        authorization: authorization,
      );
    }
    if (authorization.isLimited && authorization.remaining == 0) {
      return OfflineAuthorizationView(
        state: OfflineAuthorizationState.exhausted,
        authorization: authorization,
      );
    }
    if (_isExpired(authorization.expiresOn)) {
      return OfflineAuthorizationView(
        state: OfflineAuthorizationState.expired,
        authorization: authorization,
      );
    }
    if (_renewalDue(authorization.expiresOn)) {
      return OfflineAuthorizationView(
        state: OfflineAuthorizationState.renewalDue,
        authorization: authorization,
      );
    }
    return OfflineAuthorizationView(
      state: OfflineAuthorizationState.active,
      authorization: authorization,
    );
  }

  Future<OfflineAuthorizationView> status(String cardId) async {
    final deviceCode = await _requireDeviceCode();
    final authorization = await _credentials.read(
      cardId,
      deviceCode: deviceCode,
    );
    if (authorization == null) {
      return viewOf(null, hasPrivateKey: false);
    }
    final key = await _credentials.readPrivateKey(
      cardId,
      deviceCode: deviceCode,
    );
    return viewOf(authorization, hasPrivateKey: key != null);
  }

  Future<OfflineAuthorization> activate({required String cardId}) {
    final active = _activations[cardId];
    if (active != null) return active;
    late final Future<OfflineAuthorization> operation;
    operation = _activate(cardId).whenComplete(() {
      if (identical(_activations[cardId], operation)) {
        unawaited(_activations.remove(cardId));
      }
    });
    _activations[cardId] = operation;
    return operation;
  }

  Future<OfflineAuthorization> _activate(String cardId) async {
    final generation = _removalGeneration;
    final deviceCode = await _requireDeviceCode();
    final keyPair = _crypto.generateKeyPair();
    final request = OfflineActivationRequest(
      cardId: cardId,
      deviceCode: deviceCode,
      publicKeyCompressed: keyPair.publicKeyCompressed,
      privateKeyHex: keyPair.privateKeyHex,
    );
    // Connectivity APIs can briefly report `none` while iOS is rebuilding its
    // path. The actual HTTPS request is authoritative. A transient failure is
    // retried once with the exact same key pair so the activation remains
    // idempotent from the device's point of view.
    final response = await _retryTransient(() => _remote.activate(request));
    final authorization = OfflineAuthorization(
      cardId: cardId,
      deviceCode: deviceCode,
      publicKeyCompressed: keyPair.publicKeyCompressed,
      authorInfo: response.authorInfo,
      totalUses: response.totalUses,
      used: 0,
      updatedAt: _clock.now().toUtc(),
      expiresOn: response.expiresOn,
    );
    await response.validateContext?.call();
    Future<void> install() => _credentialChanges.protect(() async {
      if (generation != _removalGeneration) {
        throw const AppFailure(
          FailureKind.cancelled,
          '离线付款授权已移除，请重新开通。',
          code: 'OFFLINE_ACTIVATION_CANCELLED',
        );
      }
      await _credentials.install(
        authorization: authorization,
        privateKeyHex: keyPair.privateKeyHex,
      );
    });
    await (response.commitInSession?.call(install) ?? install());
    await response.validateContext?.call();
    if (!_changes.isClosed) _changes.add(null);
    return authorization;
  }

  Future<OfflineAuthorization> renew(
    String cardId, {
    bool force = false,
  }) async {
    final deviceCode = await _requireDeviceCode();
    final authorization = await _credentials.read(
      cardId,
      deviceCode: deviceCode,
    );
    if (authorization == null) {
      throw const AppFailure(
        FailureKind.credentialMissing,
        '此设备没有可续期的离线付款授权。',
        code: 'OFFLINE_CREDENTIAL_MISSING',
      );
    }
    if (!force && !_renewalDue(authorization.expiresOn)) return authorization;
    if (!await _connectivity.isOnline()) return authorization;
    final active = _renewals[cardId];
    if (active != null) return active;
    late final Future<OfflineAuthorization> operation;
    operation = _renewOnline(authorization).whenComplete(() {
      if (identical(_renewals[cardId], operation)) {
        unawaited(_renewals.remove(cardId));
      }
    });
    _renewals[cardId] = operation;
    return operation;
  }

  Future<OfflineAuthorization> _renewOnline(
    OfflineAuthorization authorization,
  ) async {
    final response = await _retryTransient(() => _remote.renew(authorization));
    if (response == null) return authorization;
    final renewed = authorization.copyWith(
      authorInfo: response.authorInfo,
      totalUses: response.totalUses,
      replaceTotalUses: true,
      used: 0,
      updatedAt: _clock.now().toUtc(),
      expiresOn: response.expiresOn,
    );
    await response.validateContext?.call();
    Future<void> update() => _credentials.updateAuthorization(renewed, resetUsage: true);
    await (response.commitInSession?.call(update) ?? update());
    await response.validateContext?.call();
    if (!_changes.isClosed) _changes.add(null);
    return renewed;
  }

  Future<T> _retryTransient<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on AppFailure catch (failure) {
      final transient = failure.kind == FailureKind.network ||
          failure.kind == FailureKind.timeout ||
          failure.retryable;
      if (!transient) rethrow;
      if (_transientRetryDelay > Duration.zero) {
        await Future<void>.delayed(_transientRetryDelay);
      }
      return request();
    }
  }

  Future<OfflineQrCode> generate(String cardId) async =>
      (await generateWithGrant(cardId)).code;

  /// Generates a local code and hands back the grant it consumed, so the caller
  /// can report the new remaining count without reading storage again.
  Future<({OfflineQrCode code, OfflineAuthorization authorization})>
      generateWithGrant(String cardId) async {
    final deviceCode = await _requireDeviceCode();
    final authorization = await _credentials.read(
      cardId,
      deviceCode: deviceCode,
    );
    final privateKey = await _credentials.readPrivateKey(
      cardId,
      deviceCode: deviceCode,
    );
    final view = viewOf(authorization, hasPrivateKey: privateKey != null);
    if (view.state == OfflineAuthorizationState.expired) {
      throw const AppFailure(
        FailureKind.offlineAuthorizationExpired,
        '离线付款授权已过期，请联网续期。',
        code: 'OFFLINE_AUTHORIZATION_EXPIRED',
      );
    }
    if (view.state == OfflineAuthorizationState.exhausted) {
      throw const AppFailure(
        FailureKind.offlineQuotaExhausted,
        '已达到离线付款码最大使用次数，之后的交易可能失效。请联网续期离线码。',
        code: 'OFFLINE_QUOTA_EXHAUSTED',
      );
    }
    if (privateKey == null || authorization == null) {
      throw const AppFailure(
        FailureKind.credentialMissing,
        '此设备缺少离线付款私钥。',
        code: 'OFFLINE_PRIVATE_KEY_MISSING',
      );
    }
    // Reserve and persist before any QR payload is calculated or exposed.
    final reserved = await _credentials.reserveUse(
      cardId,
      deviceCode: deviceCode,
    );
    final current = await _credentials.read(cardId, deviceCode: deviceCode);
    if (current == null ||
        authorization.publicKeyCompressed != reserved.publicKeyCompressed ||
        current.publicKeyCompressed != reserved.publicKeyCompressed ||
        current.authorInfo != reserved.authorInfo ||
        current.updatedAt != reserved.updatedAt ||
        await _credentials.readPrivateKey(cardId, deviceCode: deviceCode) !=
            privateKey ||
        await _deviceCodeReader() != deviceCode) {
      throw const AppFailure(
        FailureKind.cancelled,
        '离线付款授权已更新，请重试。',
        code: 'OFFLINE_CREDENTIAL_CHANGED',
      );
    }
    if (_isExpired(reserved.expiresOn)) {
      throw const AppFailure(
        FailureKind.offlineAuthorizationExpired,
        '离线付款授权已过期，请联网续期。',
        code: 'OFFLINE_AUTHORIZATION_EXPIRED',
      );
    }
    final generatedAt = _clock.now().toUtc();
    final hex = _crypto.buildOfflineQrHex(
      authorInfo: reserved.authorInfo,
      deviceCode: reserved.deviceCode,
      privateKeyHex: privateKey,
      now: generatedAt,
    );
    return (
      code: OfflineQrCode(
        hex: hex,
        payload: QrPayloadCodec.offline(hex),
        reservedUse: reserved.used,
        generatedAt: generatedAt,
      ),
      authorization: reserved,
    );
  }

  Future<void> removeFromThisDevice(String cardId) async {
    _removalGeneration++;
    final deviceCode = await _requireDeviceCode();
    await _credentialChanges.protect(() async {
      await _credentials.read(cardId, deviceCode: deviceCode);
      await _credentials.remove(cardId);
    });
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> removeAllFromThisDevice() async {
    _removalGeneration++;
    await _credentialChanges.protect(_credentials.removeAll);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<String> _requireDeviceCode() async {
    final deviceCode = await _deviceCodeReader();
    if (deviceCode == null || deviceCode.isEmpty) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '登录状态缺少离线设备标识，请重新登录。',
        code: 'OFFLINE_DEVICE_CODE_MISSING',
      );
    }
    return deviceCode;
  }

  bool _isExpired(DateTime? expiration) {
    if (expiration == null) return false;
    final now = _dateOnly(_clock.now().toUtc());
    return expiration.isBefore(now);
  }

  bool _renewalDue(DateTime? expiration) {
    if (expiration == null) return true;
    final threshold = _dateOnly(
      _clock.now().toUtc(),
    ).add(const Duration(days: 4));
    return !expiration.isAfter(threshold);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
