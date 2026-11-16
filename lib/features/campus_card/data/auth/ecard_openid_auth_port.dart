import 'dart:async';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:techpie/services/api_base_url.dart';

import '../../core/async_mutex.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/ports/auth_port.dart';
import '../../domain/ports/credential_store.dart';
import '../api/decrypted_http_trace.dart';
import '../api/ecard_api_client.dart';
import '../api/ecard_cipher.dart';
import 'geekpie_ecard_session_issuer.dart';

typedef AuthSecurityCleanup = Future<void> Function();
typedef AuthPinnedIdSerialReader = Future<String?> Function();

final class EcardOpenIdAuthPort implements AuthPort, OpenIdAuthVerifier {
  EcardOpenIdAuthPort({
    Dio? dio,
    Clock? clock,
    EcardSessionIssuer? sessionIssuer,
    DecryptedHttpTraceInterceptor? httpTrace,
    EcardCipher? cipher,
    required SessionCredentialStore sessionStore,
    required AuthSecurityCleanup purgeAccountBoundCredentials,
    AuthPinnedIdSerialReader? pinnedIdSerialReader,
    String baseUrl = 'https://ecard.shanghaitech.edu.cn',
  })  : _clock = clock ?? const Clock(),
        _sessionIssuer = sessionIssuer ?? GeekPieEcardSessionIssuer(
          endpoint: () => Uri.parse('$prodApiBaseUrl/auth/third-party/ecard'),
        ),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 6),
                sendTimeout: const Duration(seconds: 6),
                headers: const {
                  'content-type': 'application/json',
                  'x-requested-with': 'XMLHttpRequest',
                  'session-type': 'uniapp',
                  'isWechatApp': 'true',
                  'orgid': '2',
                },
              ),
            ),
        _cipher = cipher ?? EcardCipher(),
        _sessionStore = sessionStore,
        _purgeAccountBoundCredentials = purgeAccountBoundCredentials,
        _pinnedIdSerialReader = pinnedIdSerialReader {
    installDecryptedHttpTrace(_dio, trace: httpTrace);
    unawaited(_sessionMutex.protect(() async {
      if (!_disposed) await _expireIdleSession();
    }).catchError((Object _) {}),);
  }

  static const sessionIdleTimeout = Duration(minutes: 30);

  /// How often a request may rewrite the stored idle timestamp. Far shorter
  /// than [sessionIdleTimeout], so the deadline stays accurate.
  static const _activityWriteInterval = Duration(minutes: 1);
  final Clock _clock;
  Timer? _idleTimer;
  bool _disposed = false;
  final Dio _dio;
  final EcardSessionIssuer _sessionIssuer;
  final EcardCipher _cipher;
  final SessionCredentialStore _sessionStore;
  final AuthSecurityCleanup _purgeAccountBoundCredentials;
  final AuthPinnedIdSerialReader? _pinnedIdSerialReader;
  final AsyncMutex _sessionMutex = AsyncMutex();
  int _generation = 0;
  int _accountRevision = 0;
  int _accountOperations = 0;
  int get generation => _generation;
  int get accountRevision => _accountRevision;
  String? _verifiedSessionCookie;

  /// The session [_readSession] last built.
  ///
  /// Reading it back from the platform store costs a dozen channel calls — the
  /// cookie, the account, the channel and the identity pin — and it happened
  /// twice for every request, once as the request entered and once as it
  /// recorded activity. On a phone that is seconds in front of a request the
  /// server answers in a tenth of that.
  ///
  /// The store stays the authority: every path that clears the session or writes
  /// a new one drops this, and the idle check reads the store directly.
  EcardSession? _sessionCache;
  int _sessionCacheGeneration = -1;
  int _sessionCacheRevision = -1;
  DateTime? _lastActivityWrittenAt;

  /// The process's idea of when the session was last used. This is the deadline
  /// the idle check compares against, and it is deliberately not
  /// [_lastActivityWrittenAt]: that one is the write throttle's basis and only
  /// moves when a write happens, so a session restored with fresh activity would
  /// be expired against a stale one.
  DateTime? _lastActivityAt;
  Future<void>? _sessionRecovery;
  Future<AuthSnapshot>? _sessionRefresh;
  Future<EcardVerifiedIdentity>? _identityVerification;
  final StreamController<AuthSnapshot> _changes =
      StreamController<AuthSnapshot>.broadcast(sync: true);

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  // Storage commits share the account lock. Reads inside a commit are reentrant.
  final Object _commitZone = Object();

  Future<EcardSession?> readSession() => Zone.current[_commitZone] == true
      ? _readSession()
      : _sessionMutex.protect(_readSession);

  Future<EcardVerifiedIdentity?> readRequestIdentity() {
    final revision = _accountRevision;
    // The authenticated event may start new requests before signIn returns.
    // At that point its verified cookie has already been committed.
    if (_accountOperations != 0 && _verifiedSessionCookie == null) {
      return Future.error(const AppFailure(FailureKind.cancelled,
          '校园卡账户正在变化，本次操作已取消。', code: 'AUTH_REQUEST_ACCOUNT_CHANGED',),);
    }
    return _sessionMutex.protect(() async {
      if (revision != _accountRevision) {
        throw const AppFailure(FailureKind.cancelled, '校园卡账户已变化，本次操作已取消。',
            code: 'AUTH_REQUEST_ACCOUNT_CHANGED',);
      }
      return readCachedIdentity();
    });
  }

  /// Called once at request entry; never used by response/provenance checks.
  Future<EcardSession?> prepareSession() {
    final accountRevision = _accountRevision;
    return _sessionMutex.protect(() async {
      if (accountRevision != _accountRevision) {
        throw const AppFailure(FailureKind.authenticationExpired,
          '请求期间校园卡账户已变化，请重试。', code: 'AUTH_SESSION_SUBJECT_CHANGED',);
      }
      final current = await _readSession();
      if (current != null && current.identity != null) {
        // Request entry is activity. Extend before identity verification so a
        // request started just before the deadline is not expired mid-check.
        await _markActivity(_clock.now().toUtc());
        return current;
      }
      final openId = await _sessionStore.readOpenId();
      if (openId == null) return null;
      await _replaceStoredSession(openId);
      return _readSession();
    });
  }

  Future<void> recordSessionActivity(EcardSession expected) =>
      _sessionMutex.protect(() async {
        final current = await _readSession();
        if (current == null || !current.sameSession(expected)) {
          throw const AppFailure(FailureKind.authenticationExpired,
            '校园卡会话已失效，请重试。', code: 'AUTH_SESSION_SUBJECT_CHANGED',);
        }
        await _markActivity(_clock.now().toUtc());
      });

  /// Extends the idle deadline, writing it to the keystore at most once per
  /// [_activityWriteInterval].
  ///
  /// Every request used to write, which put a keystore write on the hot path to
  /// serve a deadline measured in [_sessionIdleTimeout] minutes. The in-process
  /// timer is scheduled from the exact time either way; only a cold start reads
  /// the stored value, and it can be at most one interval away from the truth,
  /// so a session can expire up to that much early rather than late.
  Future<void> _markActivity(DateTime now) async {
    final writtenAt = _lastActivityWrittenAt;
    if (writtenAt == null ||
        now.difference(writtenAt) >= _activityWriteInterval) {
      await _sessionStore.writeSessionLastActivity(now);
      _lastActivityWrittenAt = now;
    }
    _lastActivityAt = now;
    _scheduleExpiry(now);
  }

  Future<void> _expireIdleSession() async {
    final cookie = await _sessionStore.readSessionCookie();
    if (cookie == null) return;
    final last = await _sessionStore.readSessionLastActivity();
    final now = _clock.now().toUtc();
    if (last == null || now.isBefore(last) || now.difference(last) >= sessionIdleTimeout) {
      await _clearSessionCookie();
    } else {
      // This is the process's idea of the last activity now, so the next check
      // does not have to read the store again.
      _lastActivityAt = last;
      _scheduleExpiry(last);
    }
  }

  void _scheduleExpiry(DateTime lastActivity) {
    _idleTimer?.cancel();
    if (_disposed) return;
    final remaining = sessionIdleTimeout - _clock.now().toUtc().difference(lastActivity.toUtc());
    _idleTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      unawaited(_sessionMutex.protect(_expireIdleSession).catchError((Object _) {}));
    });
  }

  Future<void> commitInSession(
          EcardSession expected, Future<void> Function() action,) =>
      _sessionMutex.protect(
        () => runZoned(
          () async {
            Future<void> validate() async {
              final current = await _readSession();
              if (current == null || !current.sameSession(expected)) {
                throw const AppFailure(
                  FailureKind.authenticationExpired,
                  '请求期间校园卡会话已变化。',
                  code: 'AUTH_SESSION_SUBJECT_CHANGED',
                );
              }
            }

            await validate();
            await action();
            await validate();
          },
          zoneValues: {_commitZone: true},
        ),
      );

  Future<EcardSession?> _readSession() async {
    // The deadline is checked before the cache is believed, or a session would
    // outlive its own expiry. Once this process has marked activity the check is
    // memory-only; a cold start has nothing to compare against and asks the
    // store.
    final lastActivity = _lastActivityAt;
    if (lastActivity == null) {
      await _expireIdleSession();
    } else if (_clock.now().toUtc().difference(lastActivity) >=
        sessionIdleTimeout) {
      await _clearSessionCookie();
      return null;
    }
    final cached = _sessionCache;
    // A session this process cleared, replaced or switched accounts under has a
    // stale stamp: both counters move on those paths, so the cache is rebuilt
    // rather than trusted.
    if (cached != null &&
        _sessionCacheGeneration == _generation &&
        _sessionCacheRevision == _accountRevision) {
      return cached;
    }
    final cookie = await _sessionStore.readSessionCookie();
    final openId = await _sessionStore.readOpenId();
    final orgId = await _sessionStore.readOrgId();
    if (cookie == null || openId == null || orgId == null) return null;
    final channel = await _sessionStore.readOpenIdChannel();
    final session = EcardSession(
      sessionCookie: cookie,
      openId: openId,
      orgId: orgId,
      subjectId: channel.subjectId(openId),
      generation: _generation,
      identity: await readCachedIdentity(),
      channel: channel,
    );
    _sessionCache = session;
    _sessionCacheGeneration = _generation;
    _sessionCacheRevision = _accountRevision;
    return session;
  }

  Future<EcardVerifiedIdentity?> readCachedIdentity() async {
    // The client asks for the request's identity on every request, and building
    // it means four store reads. The session this port already built carries the
    // same identity, and both counters that could invalidate it move on every
    // path that clears, replaces or switches the session.
    final cached = _sessionCache?.identity;
    if (cached != null &&
        _sessionCacheGeneration == _generation &&
        _sessionCacheRevision == _accountRevision) {
      return cached;
    }
    final openId = await _sessionStore.readOpenId();
    final baseline = await _storedIdentity();
    return openId == null || baseline == null
        ? null
        : _verifiedIdentity(openId, baseline, channel: await _sessionStore.readOpenIdChannel());
  }

  Future<void> _clearSessionCookie() async {
    _idleTimer?.cancel();
    _generation++;
    _verifiedSessionCookie = null;
    _sessionCache = null;
    _lastActivityAt = null;
    await _sessionStore.clearSessionCookie();
  }

  @override
  Future<AuthSnapshot> restoreLocal() async {
    final openId = await _sessionStore.readOpenId();
    final orgId = await _sessionStore.readOrgId() ?? '2';
    if (openId == null || openId.isEmpty) {
      return const AuthSnapshot(state: AuthState.signedOut);
    }
    return await _authenticated(openId, orgId);
  }

  @override
  Future<AuthSnapshot> restore() {
    final active = _sessionRefresh;
    if (active != null) return active;
    late final Future<AuthSnapshot> operation;
    operation = _sessionMutex.protect(_restoreFromServer).whenComplete(() {
      if (identical(_sessionRefresh, operation)) _sessionRefresh = null;
    });
    _sessionRefresh = operation;
    return operation;
  }

  Future<AuthSnapshot> _restoreFromServer() async {
    await _expireIdleSession();
    final cookie = await _sessionStore.readSessionCookie();
    final openId = await _sessionStore.readOpenId();
    final orgId = await _sessionStore.readOrgId() ?? '2';
    if (openId == null || openId.isEmpty) {
      return _emit(const AuthSnapshot(state: AuthState.signedOut));
    }
    final storedIdentity = await _storedIdentity();
    if (cookie == null || cookie.isEmpty || storedIdentity == null) {
      try {
        final replacement = await _replaceStoredSession(openId);
        return await _authenticated(openId, replacement.orgId);
      } on AppFailure catch (failure) {
        if (_isTransient(failure)) {
          return _emit(await _authenticated(openId, orgId));
        }
        if (_isIdentityMismatch(failure)) {
          await _clearSessionCookie();
        }
        rethrow;
      }
    }
    try {
      if (cookie == _verifiedSessionCookie) {
        return await _authenticated(openId, orgId);
      }
      await _verifyQuotaIdentity(
        cookie: cookie, openId: openId, orgId: orgId, expected: storedIdentity,
      );
      if (await _sessionStore.readOpenId() != openId) {
        throw const AppFailure(
          FailureKind.authenticationExpired,
          '校验期间登录账户发生变化，已丢弃本次会话。',
          code: 'AUTH_SESSION_SUBJECT_CHANGED',
        );
      }
      _verifiedSessionCookie = cookie;
      return _emit(await _authenticated(openId, orgId));
    } on AppFailure catch (failure) {
      if (_isTransient(failure)) {
        return _emit(await _authenticated(openId, orgId));
      }
      if (_canRebindStoredOpenId(failure)) {
        try {
          final replacement = await _replaceStoredSession(openId);
          return await _authenticated(openId, replacement.orgId);
        } on AppFailure catch (rebindFailure) {
          if (_isTransient(rebindFailure)) {
            return _emit(await _authenticated(openId, orgId));
          }
          if (_isIdentityMismatch(rebindFailure)) {
            await _clearSessionCookie();
          }
          rethrow;
        }
      }
      if (_isIdentityMismatch(failure)) {
        await _clearSessionCookie();
      }
      rethrow;
    }
  }

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) {
    _accountRevision++;
    _generation++;
    _verifiedSessionCookie = null;
    _accountOperations++;
    return _sessionMutex.protect(() => _signIn(credential))
        .whenComplete(() => _accountOperations--);
  }

  Future<AuthSnapshot> _signIn(AuthCredential credential) async {
    if (credential is! OpenIdAuthCredential) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '当前登录适配器需要 OpenID。',
        code: 'OPENID_CREDENTIAL_REQUIRED',
      );
    }
    credential.validate();
    final openId = credential.openId.trim();
    _emit(const AuthSnapshot(state: AuthState.signingIn));

    final previousOpenId = await _sessionStore.readOpenId();
    final previousChannel = await _sessionStore.readOpenIdChannel();
    try {
      final verified = await _authenticateForUser(credential);
      if (previousOpenId != null && (previousOpenId != openId || previousChannel != credential.channel)) {
        // Validate the replacement first. A typo must not destroy the current
        // account or its usable offline authorization.
        await _clearSessionAndAccountMaterial();
      } else {
        await _clearSessionCookie();
      }
      _generation++;
      await _sessionStore.writeSession(
        sessionCookie: verified.cookie,
        lastActivityAt: _clock.now(),
        openId: openId,
        orgId: verified.orgId,
        verifiedIdSerial: verified.identity.idSerial,
        verifiedCardId: verified.identity.cardId,
        channel: credential.channel,
      );
      _sessionCache = null;
      _lastActivityAt = _clock.now().toUtc();
      _verifiedSessionCookie = verified.cookie;
      _scheduleExpiry(_clock.now());
      return _emit(await _authenticated(openId, verified.orgId,
        reason: previousOpenId != null && (previousOpenId != openId || previousChannel != credential.channel)
            ? AuthChangeReason.accountChanged : null,),);
    } catch (error) {
      final identityMismatch =
          error is AppFailure && _isIdentityMismatch(error);
      if (identityMismatch && previousOpenId == null) {
        await _clearSessionAndAccountMaterial();
      } else if (identityMismatch && previousOpenId == openId && previousChannel == credential.channel) {
        await _clearSessionCookie();
      }
      final restoredOpenId = await _sessionStore.readOpenId();
      final restoredOrgId = await _sessionStore.readOrgId() ?? '2';
      _emit(
        restoredOpenId == null
            ? const AuthSnapshot(state: AuthState.signedOut)
            : await _authenticated(restoredOpenId, restoredOrgId),
      );
      rethrow;
    }
  }

  @override
  Future<void> verifyOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) => _sessionMutex.protect(() async {
        final credential = OpenIdAuthCredential(openId: openId.trim(), channel: channel);
        credential.validate();
        await _authenticateForUser(credential);
      });

  Future<_VerifiedEcardSession> _replaceStoredSession(String openId) async {
    await _clearSessionCookie();
    final operationGeneration = _generation;
    final verified = await _authenticate(OpenIdAuthCredential(openId: openId, channel: await _sessionStore.readOpenIdChannel()));
    if (operationGeneration != _generation || await _sessionStore.readOpenId() != openId) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '校验期间登录账户发生变化，已丢弃本次会话。',
        code: 'AUTH_SESSION_SUBJECT_CHANGED',
      );
    }
    _generation++;
    await _sessionStore.writeSession(
      sessionCookie: verified.cookie,
      lastActivityAt: _clock.now(),
      openId: openId,
      orgId: verified.orgId,
      verifiedIdSerial: verified.identity.idSerial,
      verifiedCardId: verified.identity.cardId,
        channel: await _sessionStore.readOpenIdChannel(),
    );
    _sessionCache = null;
    _lastActivityAt = _clock.now().toUtc();
    _verifiedSessionCookie = verified.cookie;
    _scheduleExpiry(_clock.now());
    _emit(await _authenticated(openId, verified.orgId));
    return verified;
  }

  Future<_VerifiedEcardSession> _authenticateForUser(
      OpenIdAuthCredential credential,) async {
    final revision = _accountRevision;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final session = await _authenticate(credential);
        if (revision != _accountRevision) {
          throw const AppFailure(FailureKind.cancelled, '校园卡账户已变化，本次操作已取消。',
              code: 'AUTH_REQUEST_ACCOUNT_CHANGED',);
        }
        return session;
      } on AppFailure catch (failure) {
        if (attempt == 0 &&
            revision == _accountRevision &&
            failure.isRecoverableSessionFailure &&
            failure.code != 'AUTH_SESSION_SUBJECT_CHANGED' &&
            failure.code != 'HTTP_401') {
          continue;
        }
        rethrow;
      }
    }
    throw StateError('Unreachable authentication retry state');
  }

  Future<_VerifiedEcardSession> _authenticate(
    OpenIdAuthCredential credential,
  ) async {
    credential.validate();
    final openId = credential.openId.trim();
    final issued = await _sessionIssuer.issue(openId, channel: credential.channel);
    final cookie = issued.cookie;
    final orgId = issued.orgId;
    final homeIdentity = _EcardIdentity(issued.idSerial, issued.cardId);
    _assertOptionalExpectedIdentity(homeIdentity, credential);
    final currentOpenId = await _sessionStore.readOpenId();
    final sameAccount = currentOpenId == openId && await _sessionStore.readOpenIdChannel() == credential.channel;
    final storedIdentity = sameAccount ? await _storedIdentity() : null;
    final pinned = sameAccount && storedIdentity == null
        ? await _readPinnedIdSerial() : null;
    if (storedIdentity != null && storedIdentity != homeIdentity ||
        pinned != null && pinned.isNotEmpty && pinned != homeIdentity.idSerial) {
      throw const AppFailure(FailureKind.authenticationExpired,
        'eCard 会话身份与本机已验证身份不一致。', code: 'AUTH_PINNED_IDENTITY_MISMATCH',);
    }
    final quota = await _quotaIdentity(cookie: cookie, openId: openId, orgId: orgId);
    if (quota != homeIdentity) {
      throw const AppFailure(FailureKind.authenticationExpired,
        '登录身份校验不一致，已停止请求。', code: 'AUTH_IDENTITY_MISMATCH',);
    }
    final identity = _verifiedIdentity(openId, homeIdentity, channel: credential.channel);
    return _VerifiedEcardSession(
      cookie: cookie,
      orgId: orgId,
      identity: identity,
    );
  }

  Future<void> rejectCurrentOnlineSession() {
    final active = _sessionRecovery;
    if (active != null) return active;
    _generation++;
    late final Future<void> recovery;
    recovery = _sessionMutex.protect(() async {
      await _clearSessionCookie();
      final openId = await _sessionStore.readOpenId();
      if (openId == null) return;
      try {
        await _replaceStoredSession(openId);
      } on AppFailure {
        // Keep the original identity pin. A rejected replacement must not
        // adopt the identity carried by the inconsistent response.
      }
    }).whenComplete(() {
      if (identical(_sessionRecovery, recovery)) _sessionRecovery = null;
    });
    _sessionRecovery = recovery;
    return recovery;
  }

  Future<EcardVerifiedIdentity> verifyCurrentIdentity() {
    final active = _identityVerification;
    if (active != null) return active;
    late final Future<EcardVerifiedIdentity> operation;
    operation = _sessionMutex.protect(_verifyCurrentIdentity).whenComplete(() {
      if (identical(_identityVerification, operation)) {
        _identityVerification = null;
      }
    });
    _identityVerification = operation;
    return operation;
  }

  Future<EcardVerifiedIdentity> _verifyCurrentIdentity() async {
    await _expireIdleSession();
    final cookie = await _sessionStore.readSessionCookie();
    final openId = await _sessionStore.readOpenId();
    final orgId = await _sessionStore.readOrgId() ?? '2';
    if (cookie == null || openId == null || openId.isEmpty) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '登录身份尚未通过在线校验。',
        code: 'AUTH_VERIFIED_SESSION_MISSING',
      );
    }
    try {
      final storedIdentity = await _storedIdentity();
      if (storedIdentity == null) {
        // A quota response is a check, never the source of a new identity pin.
        return (await _replaceStoredSession(openId)).identity;
      }
      return await _verifyQuotaIdentity(
        cookie: cookie, openId: openId, orgId: orgId, expected: storedIdentity,
      );
    } on AppFailure catch (failure) {
      if (_canRebindStoredOpenId(failure)) {
        final replacement = await _replaceStoredSession(openId);
        return replacement.identity;
      }
      if (_isIdentityMismatch(failure)) {
        await _clearSessionCookie();
      }
      rethrow;
    }
  }

  /// Restore only an encrypted-sync login parameter. This is not a verified session.
  Future<void> importOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) {
    OpenIdAuthCredential(openId: openId, channel: channel).validate();
    _accountRevision++;
    _generation++;
    _verifiedSessionCookie = null;
    _accountOperations++;
    return _sessionMutex.protect(() async {
      final previous = await _sessionStore.readOpenId();
      final previousChannel = await _sessionStore.readOpenIdChannel();
      await _clearSessionAndAccountMaterial();
      await _sessionStore.stageOpenId(openId, channel: channel);
      _emit(await _authenticated(openId, '2', reason: previous != null &&
          (previous != openId || previousChannel != channel) ? AuthChangeReason.accountChanged : null,),);
    }).whenComplete(() => _accountOperations--);
  }

  @override
  Future<void> signOut() {
    _accountRevision++;
    _generation++;
    _verifiedSessionCookie = null;
    _accountOperations++;
    return _sessionMutex.protect(_signOut)
        .whenComplete(() => _accountOperations--);
  }

  Future<void> _signOut() async {
    await _clearSessionAndAccountMaterial();
    _emit(const AuthSnapshot(state: AuthState.signedOut, reason: AuthChangeReason.userSignedOut));
  }

  Future<void> dispose() async {
    _disposed = true;
    _idleTimer?.cancel();
    final verification = _identityVerification;
    if (verification != null) {
      try {
        await verification;
      } catch (_) {
        // A failed identity check is already reflected in the session store.
      }
    }
    final refresh = _sessionRefresh;
    if (refresh != null) {
      try {
        await refresh;
      } catch (_) {
        // Background refresh errors are intentionally non-fatal.
      }
    }
    final recovery = _sessionRecovery;
    if (recovery != null) {
      try {
        await recovery;
      } catch (_) {
        // Runtime shutdown does not surface an already-failed recovery.
      }
    }
    await _changes.close();
  }

  Future<void> handleAuthenticationFailure(int statusCode) {
    final active = _sessionRecovery;
    if (statusCode == 401 && active != null) return active;
    _generation++;
    _verifiedSessionCookie = null;
    if (statusCode != 401) {
      return _sessionMutex.protect(_expireWithoutAutomaticRecovery);
    }
    late final Future<void> recovery;
    recovery = _sessionMutex.protect(_recoverExpiredSession).whenComplete(() {
      if (identical(_sessionRecovery, recovery)) _sessionRecovery = null;
    });
    _sessionRecovery = recovery;
    return recovery;
  }

  Future<void> _recoverExpiredSession() async {
    final openId = await _sessionStore.readOpenId();
    if (openId == null || openId.isEmpty) {
      await _expireWithoutAutomaticRecovery();
      return;
    }
    await _clearSessionCookie();
    try {
      await _replaceStoredSession(openId);
    } on AppFailure {
      // Binding and offline credentials remain valid while online recovery
      // is unavailable. Never send an automatic recovery through signIn's
      // interactive account-switch state or reset a pending payment to idle.
    }
  }

  Future<void> _expireWithoutAutomaticRecovery() async {
    // A rejected online cookie is not a request to disconnect the saved account.
    // Only explicit sign-out/unbinding may remove OpenID and identity pins.
    await _clearSessionCookie();
    final openId = await _sessionStore.readOpenId();
    if (openId == null || openId.isEmpty) {
      _emit(const AuthSnapshot(state: AuthState.signedOut));
    } else {
      _emit(await _authenticated(openId, await _sessionStore.readOrgId() ?? '2'));
    }
  }

  bool _canRebindStoredOpenId(AppFailure failure) => const {
        'HTTP_401',
        'HTTP_403',
        'AUTH_BUSINESS_REJECTED',
        'AUTH_IDENTITY_MISMATCH',
        'AUTH_RESPONSE_IDENTITY_MISMATCH',
        'AUTH_IDENTITY_FIELDS_MISSING',
      }.contains(failure.code);

  bool _isTransient(AppFailure failure) =>
      failure.kind == FailureKind.network ||
      failure.kind == FailureKind.timeout ||
      failure.retryable;

  bool _isIdentityMismatch(AppFailure failure) => const {
        'AUTH_IDENTITY_MISMATCH',
        'AUTH_PINNED_IDENTITY_MISMATCH',
        'AUTH_EXPECTED_IDSERIAL_MISMATCH',
        'AUTH_EXPECTED_CARDID_MISMATCH',
        'AUTH_RESPONSE_IDENTITY_MISMATCH',
        'AUTH_SESSION_SUBJECT_CHANGED',
        'AUTH_RECOVERY_IDENTITY_CHANGED',
      }.contains(failure.code);

  Future<Map<String, Object?>> _encryptedRequest({
    required String path,
    required String cookie,
    required String orgId,
    required Map<String, Object?> payload,
  }) async {
    final envelope = _cipher.encodeRequest(payload);
    try {
      final response = await _dio.post<Object?>(
        path,
        data: {'datajson': envelope},
        options: Options(headers: {'cookie': cookie, 'orgid': orgId}),
      );
      final decoded = EcardCipher.decodeResponse(response.data);
      final map = requireObjectMap(decoded, context: 'AUTH_RESPONSE');
      if (apiRejected(map)) {
        throw AppFailure(
          FailureKind.server,
          apiMessage(map, fallback: '登录验证失败。'),
          code: 'AUTH_BUSINESS_REJECTED',
        );
      }
      return map;
    } on DioException catch (error) {
      throw _mapDio(error);
    } on FormatException catch (error) {
      throw AppFailure(
        FailureKind.protocol,
        '登录响应格式无效。',
        code: 'AUTH_RESPONSE_INVALID',
        cause: error,
      );
    }
  }

  Future<EcardVerifiedIdentity> _verifyQuotaIdentity({
    required String cookie,
    required String openId,
    required String orgId,
    required _EcardIdentity expected,
  }) async {
    final actual = await _quotaIdentity(cookie: cookie, openId: openId, orgId: orgId);
    if (actual != expected) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '当前会话身份与本机已验证身份不一致，已停止请求。',
        code: 'AUTH_IDENTITY_MISMATCH',
      );
    }
    return _verifiedIdentity(openId, expected, channel: await _sessionStore.readOpenIdChannel());
  }

  Future<_EcardIdentity> _quotaIdentity({
    required String cookie,
    required String openId,
    required String orgId,
  }) async {
    final response = await _encryptedRequest(
      path: '/virtualcard/openQrcodeQuotaModify',
      cookie: cookie,
      orgId: orgId,
      payload: {'openid': openId},
    );
    return _identityFromCard(_unwrapData(response));
  }

  Future<_EcardIdentity?> _storedIdentity() async {
    final idSerial = await _sessionStore.readVerifiedIdSerial();
    final cardId = await _sessionStore.readVerifiedCardId();
    if (idSerial == null ||
        idSerial.isEmpty ||
        cardId == null ||
        cardId.isEmpty) {
      return null;
    }
    return _EcardIdentity(idSerial, cardId);
  }

  Future<String?> _readPinnedIdSerial() =>
      _pinnedIdSerialReader?.call() ?? Future<String?>.value();

  EcardVerifiedIdentity _verifiedIdentity(
    String openId,
    _EcardIdentity identity, {
    required EcardOpenIdChannel channel,
  }) =>
      EcardVerifiedIdentity(
        subjectId: channel.subjectId(openId),
        idSerial: identity.idSerial,
        cardId: identity.cardId,
      );

  Map<String, Object?> _unwrapData(Map<String, Object?> response) {
    final data = response['data'];
    if (data is Map) return requireObjectMap(data, context: 'AUTH_DATA');
    return response;
  }

  _EcardIdentity _identityFromCard(Map<String, Object?> card) {
    final idSerial = card['idserial']?.toString() ?? '';
    final cardId = card['cardid']?.toString() ?? '';
    if (idSerial.isEmpty || cardId.isEmpty) {
      throw const AppFailure(
        FailureKind.protocol,
        '服务未返回完整身份字段。',
        code: 'AUTH_IDENTITY_FIELDS_MISSING',
      );
    }
    return _EcardIdentity(idSerial, cardId);
  }

  void _assertOptionalExpectedIdentity(
    _EcardIdentity actual,
    OpenIdAuthCredential credential,
  ) {
    if (credential.expectedIdSerial != null &&
        credential.expectedIdSerial != actual.idSerial) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '登录学号与预期不一致，已停止请求。',
        code: 'AUTH_EXPECTED_IDSERIAL_MISMATCH',
      );
    }
    if (credential.expectedCardId != null &&
        credential.expectedCardId != actual.cardId) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '登录卡号与预期不一致，已停止请求。',
        code: 'AUTH_EXPECTED_CARDID_MISMATCH',
      );
    }
  }

  Future<AuthSnapshot> _authenticated(String openId, String orgId, {AuthChangeReason? reason}) async => AuthSnapshot(
        state: AuthState.authenticated,
        reason: reason,
        session: AuthSession(
          subjectId: (await _sessionStore.readOpenIdChannel()).subjectId(openId),
          orgId: orgId,
          generation: _generation,
          maskedIdentity: _maskOpenId(openId),
        ),
      );

  String _maskOpenId(String value) {
    if (value.length <= 8) return '****';
    return '${value.substring(0, 4)}****${value.substring(value.length - 4)}';
  }

  AuthSnapshot _emit(AuthSnapshot value) {
    _changes.add(value);
    return value;
  }

  Future<void> _clearSessionAndAccountMaterial() async {
    _idleTimer?.cancel();
    await _sessionStore.clear();
    await _purgeAccountBoundCredentials();
  }

  AppFailure _mapDio(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return AppFailure(
        FailureKind.authenticationExpired,
        '登录状态已失效。',
        code: 'HTTP_$status',
      );
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        const AppFailure(
          FailureKind.timeout,
          '连接校园支付服务超时。',
          code: 'AUTH_NETWORK_TIMEOUT',
          retryable: true,
        ),
      DioExceptionType.connectionError => const AppFailure(
          FailureKind.network,
          '当前无法连接校园支付服务。',
          code: 'AUTH_NETWORK_UNREACHABLE',
          retryable: true,
        ),
      _ => AppFailure(
          FailureKind.server,
          '校园登录服务暂时不可用。',
          code: status == null ? 'AUTH_HTTP_UNKNOWN' : 'AUTH_HTTP_$status',
          retryable: status == null || status >= 500,
        ),
    };
  }
}

final class _EcardIdentity {
  const _EcardIdentity(this.idSerial, this.cardId);
  final String idSerial;
  final String cardId;

  @override
  bool operator ==(Object other) =>
      other is _EcardIdentity &&
      other.idSerial == idSerial &&
      other.cardId == cardId;

  @override
  int get hashCode => Object.hash(idSerial, cardId);
}

final class _VerifiedEcardSession {
  const _VerifiedEcardSession({
    required this.cookie,
    required this.orgId,
    required this.identity,
  });

  final String cookie;
  final String orgId;
  final EcardVerifiedIdentity identity;
}
