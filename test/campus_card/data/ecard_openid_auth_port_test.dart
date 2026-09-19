import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/api/ecard_cipher.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_openid_auth_port.dart';
import 'package:techpie/features/campus_card/data/auth/geekpie_ecard_session_issuer.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/services/campus_card_http_trace.dart';
import 'package:techpie/services/debug_logger.dart';

void main() {
  const openId = 'SYNTHETIC_OPENID_0123456789ABCDEF';
  const idSerial = 'DEMO-STUDENT-0001';
  const cardId = 'DEMO-CARD-0001';

  test('login retries inconsistent identity before exposing an error', () async {
    final adapter = _QueueAdapter([
      _Reply.issued('JSESSIONID=bad', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, 'DIFFERENT-CARD')),
      _Reply.issued('JSESSIONID=good', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, cardId)),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    final auth = EcardOpenIdAuthPort(dio: _dio(adapter), sessionIssuer: _issuer(adapter),
      sessionStore: store, purgeAccountBoundCredentials: () async {},);
    addTearDown(auth.dispose);
    final states = <AuthState>[];
    final subscription = auth.changes.listen((event) => states.add(event.state));
    addTearDown(subscription.cancel);
    await auth.signIn(const OpenIdAuthCredential(openId: openId));
    expect(await store.readSessionCookie(), 'JSESSIONID=good');
    expect(states, [AuthState.signingIn, AuthState.authenticated]);
    expect(adapter.requests, hasLength(4));
  });

  test('changing only the channel replaces the account and recovery keeps Alipay', () async {
    final adapter = _QueueAdapter([
      _Reply.issued('JSESSIONID=alipay-one', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, cardId)),
      _Reply.issued('JSESSIONID=alipay-two', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, cardId)),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(sessionCookie: 'JSESSIONID=wechat', openId: openId, orgId: '2',
      verifiedIdSerial: idSerial, verifiedCardId: cardId,);
    var purges = 0;
    final auth = EcardOpenIdAuthPort(dio: _dio(adapter), sessionIssuer: _issuer(adapter),
      sessionStore: store, purgeAccountBoundCredentials: () async { purges++; },);
    addTearDown(auth.dispose);
    final result = await auth.signIn(const OpenIdAuthCredential(openId: openId, channel: EcardOpenIdChannel.alipay));
    expect(result.session!.subjectId, EcardOpenIdChannel.alipay.subjectId(openId));
    expect(result.session!.subjectId, isNot(EcardOpenIdChannel.wechat.subjectId(openId)));
    expect(await store.readOpenIdChannel(), EcardOpenIdChannel.alipay);
    expect((await auth.readSession())!.channel, EcardOpenIdChannel.alipay);
    expect(purges, 1);
    await auth.handleAuthenticationFailure(401);
    expect(await store.readOpenIdChannel(), EcardOpenIdChannel.alipay);
    expect(purges, 1);
    final issues = adapter.requests.where((request) => request.uri.path == '/api/auth/third-party/ecard');
    expect(issues, hasLength(2));
    expect(issues.map((request) => (request.data as Map)['method']), everyElement('alipay_openid'));
  });

  test('restored Alipay sessions verify only quota against the saved identity', () async {
    final adapter = _QueueAdapter([
      _Reply.encrypted(_quota(idSerial, cardId)),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(sessionCookie: 'JSESSIONID=alipay', openId: openId, orgId: '2',
      verifiedIdSerial: idSerial, verifiedCardId: cardId, channel: EcardOpenIdChannel.alipay,);
    final auth = EcardOpenIdAuthPort(dio: _dio(adapter), sessionIssuer: _issuer(adapter),
      sessionStore: store, purgeAccountBoundCredentials: () async {},);
    addTearDown(auth.dispose);
    await auth.restore();
    final request = EcardCipher.decodeEnvelope((adapter.requests.first.data as Map)['datajson'] as String) as Map;
    expect(request['openid'], openId);
    expect(adapter.requests.single.uri.path, '/virtualcard/openQrcodeQuotaModify');
    expect(adapter.requests, hasLength(1));
  });

  test(
    'bootstraps JSESSIONID, binds OpenID, and cross-checks quota identity',
    () async {
      final adapter = _QueueAdapter([
        _Reply.issued('JSESSIONID=synthetic-session; Path=/; HttpOnly', idSerial, cardId),
        _Reply.encrypted(_quota(idSerial, cardId)),
      ]);
      final store = SecureSessionCredentialStore(
        InMemorySecureCredentialStore(),
      );
      var cleanupCalls = 0;
      final logger = DebugLogger()..enabled = true;
      final auth = EcardOpenIdAuthPort(
        httpTrace: campusCardHttpTrace(logger),
        sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
        cipher: EcardCipher(keyGenerator: () => 'AbCdEfGhIjKlMnOp'),
        sessionStore: store,
        purgeAccountBoundCredentials: () async => cleanupCalls += 1,
      );

      final snapshot = await auth.signIn(
        const OpenIdAuthCredential(
          openId: openId,
          expectedIdSerial: idSerial,
          expectedCardId: cardId,
        ),
      );

      expect(logger.entries, hasLength(2));
      expect(
        logger.entries.every((entry) => entry.tag == 'Campus Card'),
        isTrue,
      );
      expect(
        logger.entries.map((entry) => entry.requestBody).join(),
        isNot(contains(openId)),
      );
      expect(snapshot.state, AuthState.authenticated);
      expect(snapshot.session!.subjectId, isNot(contains(openId)));
      expect(await store.readSessionCookie(), 'JSESSIONID=synthetic-session');
      expect(await store.readOpenId(), openId);
      expect(await store.readVerifiedIdSerial(), idSerial);
      expect(await store.readVerifiedCardId(), cardId);
      expect(
        adapter.requests.map((request) => '${request.method} ${request.uri.path}'),
        [
          'POST /api/auth/third-party/ecard',
          'POST /virtualcard/openQrcodeQuotaModify',
        ],
      );
      expect(
        cleanupCalls,
        0,
        reason: 'first login has no prior account-bound material',
      );
    },
  );

  test(
    'fails closed before quota request when caller identity expectation differs',
    () async {
      final adapter = _QueueAdapter([
        _Reply.issued('JSESSIONID=synthetic-session; Path=/', idSerial, cardId),
      ]);
      final secure = InMemorySecureCredentialStore();
      final store = SecureSessionCredentialStore(secure);
      var cleanupCalls = 0;
      final auth = EcardOpenIdAuthPort(
        sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
        sessionStore: store,
        purgeAccountBoundCredentials: () async => cleanupCalls += 1,
      );

      await expectLater(
        auth.signIn(
          const OpenIdAuthCredential(
            openId: openId,
            expectedIdSerial: 'DIFFERENT-STUDENT',
          ),
        ),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'AUTH_EXPECTED_IDSERIAL_MISMATCH',
          ),
        ),
      );

      expect(adapter.requests, hasLength(1));
      expect(await store.readSessionCookie(), isNull);
      expect(await store.readOpenId(), isNull);
      expect(cleanupCalls, 1);
    },
  );

  test('clears session when the issuer and quota endpoints disagree', () async {
    final adapter = _QueueAdapter([
      _Reply.issued('JSESSIONID=synthetic-session; Path=/', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, 'DIFFERENT-CARD')),
      _Reply.issued('JSESSIONID=synthetic-session; Path=/', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, 'DIFFERENT-CARD')),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    await expectLater(
      auth.signIn(const OpenIdAuthCredential(openId: openId)),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'AUTH_IDENTITY_MISMATCH',
        ),
      ),
    );
    expect(await store.readSessionCookie(), isNull);
  });

  test('background refresh rejects a replacement that still violates the local pin',
      () async {
    final adapter = _QueueAdapter([
      _Reply.encrypted(_quota('OTHER-STUDENT', 'OTHER-CARD')),
      _Reply.issued('JSESSIONID=wrong-replacement', 'OTHER-STUDENT', 'OTHER-CARD'),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(
      sessionCookie: 'JSESSIONID=verified-session',
      openId: openId,
      orgId: '2',
      verifiedIdSerial: idSerial,
      verifiedCardId: cardId,
    );
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      cipher: EcardCipher(keyGenerator: () => 'AbCdEfGhIjKlMnOp'),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    final local = await auth.restoreLocal();
    await expectLater(
      auth.restore(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'AUTH_PINNED_IDENTITY_MISMATCH',
        ),
      ),
    );

    expect(local.state, AuthState.authenticated);
    expect(await store.readSessionCookie(), isNull);
    expect(await store.readOpenId(), openId);
    expect(await store.readVerifiedIdSerial(), idSerial);
    expect(await store.readVerifiedCardId(), cardId);
    expect(adapter.requests, hasLength(2));
  });

  for (final restore in [true, false]) {
    test('missing identity obtains a new TechPie session before quota (restore=$restore)', () async {
      final adapter = _QueueAdapter([
        _Reply.issued('JSESSIONID=from-techpie', idSerial, cardId),
        _Reply.encrypted(_quota(idSerial, cardId)),
      ]);
      final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
      await store.writeSession(sessionCookie: 'JSESSIONID=unverified', openId: openId, orgId: '2',
        verifiedIdSerial: '', verifiedCardId: '',);
      final auth = EcardOpenIdAuthPort(dio: _dio(adapter), sessionIssuer: _issuer(adapter),
        sessionStore: store, purgeAccountBoundCredentials: () async {},);
      addTearDown(auth.dispose);
      if (restore) { await auth.restore(); } else { await auth.verifyCurrentIdentity(); }
      expect(adapter.requests.map((request) => request.uri.path),
        ['/api/auth/third-party/ecard', '/virtualcard/openQrcodeQuotaModify'],);
      expect(await store.readSessionCookie(), 'JSESSIONID=from-techpie');
      expect(await store.readVerifiedIdSerial(), idSerial);
    });
  }

  test('missing baseline never adopts a mismatched quota response as identity', () async {
    final adapter = _QueueAdapter([
      _Reply.issued('JSESSIONID=from-techpie', idSerial, cardId),
      _Reply.encrypted(_quota('OTHER-STUDENT', 'OTHER-CARD')),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(sessionCookie: 'JSESSIONID=unverified', openId: openId, orgId: '2',
      verifiedIdSerial: '', verifiedCardId: '',);
    final auth = EcardOpenIdAuthPort(dio: _dio(adapter), sessionIssuer: _issuer(adapter),
      sessionStore: store, purgeAccountBoundCredentials: () async {},);
    addTearDown(auth.dispose);
    await expectLater(auth.restore(), throwsA(isA<AppFailure>()));
    expect(await store.readSessionCookie(), isNull);
    expect(await store.readVerifiedIdSerial(), '');
    expect(adapter.requests.map((request) => request.uri.path),
      ['/api/auth/third-party/ecard', '/virtualcard/openQrcodeQuotaModify'],);
  });

  test('concurrent identity checks share one verified server probe', () async {
    final adapter = _QueueAdapter([
      _Reply.encrypted(_quota(idSerial, cardId)),
    ]);
    final secureStore = InMemorySecureCredentialStore();
    final store = SecureSessionCredentialStore(secureStore);
    await store.writeSession(
      sessionCookie: 'JSESSIONID=verified-session',
      openId: openId,
      orgId: '2',
      verifiedIdSerial: idSerial,
      verifiedCardId: cardId,
    );
    secureStore.failNextWrite = true;
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      cipher: EcardCipher(keyGenerator: () => 'AbCdEfGhIjKlMnOp'),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    final identities = await Future.wait([
      for (var index = 0; index < 4; index++) auth.verifyCurrentIdentity(),
    ]);

    expect(identities, everyElement(identities.first));
    expect(adapter.requests, hasLength(1));
    expect(secureStore.failNextWrite, isTrue);
  });

  test(
    're-authenticates an expired same-account session without purging offline material',
    () async {
      final adapter = _QueueAdapter([
        const _Reply(status: 401, body: ''),
        _Reply.issued('JSESSIONID=renewed-session; Path=/', idSerial, cardId),
        _Reply.encrypted(_quota(idSerial, cardId)),
      ]);
      final store = SecureSessionCredentialStore(
        InMemorySecureCredentialStore(),
      );
      await store.writeSession(
        sessionCookie: 'JSESSIONID=expired-session',
        openId: openId,
        orgId: '2',
        verifiedIdSerial: idSerial,
        verifiedCardId: cardId,
      );
      var cleanupCalls = 0;
      final auth = EcardOpenIdAuthPort(
        sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
        sessionStore: store,
        purgeAccountBoundCredentials: () async => cleanupCalls += 1,
      );

      final snapshot = await auth.restore();

      expect(snapshot.state, AuthState.authenticated);
      expect(await store.readSessionCookie(), 'JSESSIONID=renewed-session');
      expect(await store.readOpenId(), openId);
      expect(cleanupCalls, 0);
      expect(
        adapter.requests.map((request) => '${request.method} ${request.uri.path}'),
        [
          'POST /virtualcard/openQrcodeQuotaModify',
          'POST /api/auth/third-party/ecard',
          'POST /virtualcard/openQrcodeQuotaModify',
        ],
      );
    },
  );

  test(
    'rebinds the stored OpenID when a second launch gets a stale-session business response',
    () async {
      final adapter = _QueueAdapter([
        _Reply.encrypted(const {
          'success': false,
          'message': 'synthetic stale session',
        }),
        _Reply.issued('JSESSIONID=second-launch-session; Path=/', idSerial, cardId),
        _Reply.encrypted(_quota(idSerial, cardId)),
      ]);
      final store = SecureSessionCredentialStore(
        InMemorySecureCredentialStore(),
      );
      await store.writeSession(
        sessionCookie: 'JSESSIONID=first-launch-session',
        openId: openId,
        orgId: '2',
        verifiedIdSerial: idSerial,
        verifiedCardId: cardId,
      );
      final auth = EcardOpenIdAuthPort(
        sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
        sessionStore: store,
        purgeAccountBoundCredentials: () async {},
      );

      final snapshot = await auth.restore();

      expect(snapshot.state, AuthState.authenticated);
      expect(await store.readOpenId(), openId);
      expect(
        await store.readSessionCookie(),
        'JSESSIONID=second-launch-session',
      );
      expect(
        adapter.requests.map((request) => '${request.method} ${request.uri.path}'),
        [
          'POST /virtualcard/openQrcodeQuotaModify',
          'POST /api/auth/third-party/ecard',
          'POST /virtualcard/openQrcodeQuotaModify',
        ],
      );
    },
  );

  test('same-account renewal failure preserves the stored OpenID', () async {
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(
      sessionCookie: 'JSESSIONID=old-session',
      openId: openId,
      orgId: '2',
      verifiedIdSerial: idSerial,
      verifiedCardId: cardId,
    );
    final adapter = _QueueAdapter([
      const _Reply(status: 500, body: ''),
      _Reply.issued('JSESSIONID=retry-session; Path=/', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, cardId)),
    ]);
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    await expectLater(
      auth.signIn(const OpenIdAuthCredential(openId: openId)),
      throwsA(isA<AppFailure>()),
    );

    expect(await store.readOpenId(), openId);
    expect(await store.readSessionCookie(), 'JSESSIONID=old-session');
    expect(await store.readOrgId(), '2');
  });

  test('a rejected replacement OPENID preserves the active account', () async {
    const previousOpenId = 'PREVIOUS_OPENID_0123456789ABCDEF';
    const previousIdSerial = 'PREVIOUS-STUDENT';
    const previousCardId = 'PREVIOUS-CARD';
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(
      sessionCookie: 'JSESSIONID=previous-session',
      openId: previousOpenId,
      orgId: '2',
      verifiedIdSerial: previousIdSerial,
      verifiedCardId: previousCardId,
    );
    final adapter = _QueueAdapter([
      _Reply.issued('JSESSIONID=candidate-session; Path=/', idSerial, cardId),
      _Reply.encrypted(_quota('OTHER-STUDENT', 'OTHER-CARD')),
      _Reply.issued('JSESSIONID=candidate-session; Path=/', idSerial, cardId),
      _Reply.encrypted(_quota('OTHER-STUDENT', 'OTHER-CARD')),
    ]);
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      cipher: EcardCipher(keyGenerator: () => 'AbCdEfGhIjKlMnOp'),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    await expectLater(
      auth.signIn(const OpenIdAuthCredential(openId: openId)),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'AUTH_IDENTITY_MISMATCH',
        ),
      ),
    );

    expect(await store.readOpenId(), previousOpenId);
    expect(await store.readSessionCookie(), 'JSESSIONID=previous-session');
    expect(await store.readVerifiedIdSerial(), previousIdSerial);
    expect(await store.readVerifiedCardId(), previousCardId);
  });

  test('restores the local account before an offline refresh completes',
      () async {
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(
      sessionCookie: 'JSESSIONID=cached-session',
      openId: openId,
      orgId: '2',
      verifiedIdSerial: idSerial,
      verifiedCardId: cardId,
    );
    final adapter = _QueueAdapter([const _Reply(status: 500, body: '')]);
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    final snapshot = await auth.restoreLocal();

    expect(snapshot.state, AuthState.authenticated);
    expect(adapter.requests, isEmpty);
    expect(await store.readSessionCookie(), 'JSESSIONID=cached-session');
    final refreshed = await auth.restore();
    expect(refreshed.state, AuthState.authenticated);
    expect(await store.readOpenId(), openId);
    expect(await store.readSessionCookie(), 'JSESSIONID=cached-session');
  });

  test('checks an OpenID without replacing the saved account', () async {
    final adapter = _QueueAdapter([
      _Reply.issued('JSESSIONID=checked-session; Path=/', idSerial, cardId),
      _Reply.encrypted(_quota(idSerial, cardId)),
    ]);
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    final auth = EcardOpenIdAuthPort(
      sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
      cipher: EcardCipher(keyGenerator: () => 'AbCdEfGhIjKlMnOp'),
      sessionStore: store,
      purgeAccountBoundCredentials: () async {},
    );

    await auth.verifyOpenId(openId);

    expect(await store.readOpenId(), isNull);
    expect(await store.readSessionCookie(), isNull);
    expect(adapter.requests, hasLength(2));
  });

  test('signing out clears both session and account-bound material', () async {
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(
      sessionCookie: 'JSESSIONID=synthetic-session',
      openId: openId,
      orgId: '2',
      verifiedIdSerial: idSerial,
      verifiedCardId: cardId,
    );
    var cleanupCalls = 0;
    final auth = EcardOpenIdAuthPort(
      dio: _dio(_QueueAdapter([])),
      sessionStore: store,
      purgeAccountBoundCredentials: () async => cleanupCalls += 1,
    );

    await auth.signOut();

    expect(await store.readSessionCookie(), isNull);
    expect(await store.readOpenId(), isNull);
    expect(await store.readVerifiedIdSerial(), isNull);
    expect(await store.readVerifiedCardId(), isNull);
    expect(cleanupCalls, 1);
  });

  test(
    '401 recovery is single-flight and preserves account material',
    () async {
      final adapter = _QueueAdapter([
        _Reply.issued('JSESSIONID=recovered-session; Path=/', idSerial, cardId),
        _Reply.encrypted(_quota(idSerial, cardId)),
      ]);
      final store = SecureSessionCredentialStore(
        InMemorySecureCredentialStore(),
      );
      await store.writeSession(
        sessionCookie: 'JSESSIONID=expired-session',
        openId: openId,
        orgId: '2',
        verifiedIdSerial: idSerial,
        verifiedCardId: cardId,
      );
      var cleanupCalls = 0;
      final auth = EcardOpenIdAuthPort(
        sessionIssuer: _issuer(adapter),
      dio: _dio(adapter),
        sessionStore: store,
        purgeAccountBoundCredentials: () async => cleanupCalls += 1,
      );

      await Future.wait([
        auth.handleAuthenticationFailure(401),
        auth.handleAuthenticationFailure(401),
      ]);

      expect(await store.readSessionCookie(), 'JSESSIONID=recovered-session');
      expect(await store.readOpenId(), openId);
      expect(cleanupCalls, 0);
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    '403 deletes only the online cookie and preserves the configured account',
    () async {
      final store = SecureSessionCredentialStore(
        InMemorySecureCredentialStore(),
      );
      await store.writeSession(
        sessionCookie: 'JSESSIONID=forbidden-session',
        openId: openId,
        orgId: '2',
        verifiedIdSerial: idSerial,
        verifiedCardId: cardId,
      );
      var cleanupCalls = 0;
      final auth = EcardOpenIdAuthPort(
        dio: _dio(_QueueAdapter([])),
        sessionStore: store,
        purgeAccountBoundCredentials: () async => cleanupCalls += 1,
      );

      await auth.handleAuthenticationFailure(403);

      expect(await store.readSessionCookie(), isNull);
      expect(await store.readOpenId(), openId);
      expect(await store.readVerifiedIdSerial(), idSerial);
      expect(await store.readVerifiedCardId(), cardId);
      expect((await auth.restoreLocal()).state, AuthState.authenticated);
      expect(await auth.readSession(), isNull);
      expect(cleanupCalls, 0);
    },
  );
}

Dio _dio(_QueueAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Map<String, Object?> _quota(String idSerial, String cardId) => {
      'success': true,
      'data': {'idserial': idSerial, 'cardid': cardId},
    };

final class _Reply {
  const _Reply({
    required this.status,
    required this.body,
    this.headers = const {},
  });

  factory _Reply.issued(String cookie, String sid, String cardId) {
    final token = cookie.split(';').first;
    return _Reply(status: 200, body: jsonEncode({'success': true, 'data': {
      'sid': sid, 'token': token, 'raw': {'cookies': token, 'orgid': '2', 'idserial': sid, 'cardid': cardId},
    },}), headers: {Headers.contentTypeHeader: ['application/json']},);
  }

  factory _Reply.encrypted(Map<String, Object?> body) {
    final envelope = EcardCipher.encodeWithKey(body, 'AbCdEfGhIjKlMnOp');
    return _Reply(
      status: 200,
      body: jsonEncode({'datajson': envelope}),
      headers: const {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  final int status;
  final String body;
  final Map<String, List<String>> headers;
}

final class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this._replies);

  final List<_Reply> _replies;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_replies.isEmpty) throw StateError('No queued response');
    final reply = _replies.removeAt(0);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: reply.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

EcardSessionIssuer _issuer(_QueueAdapter adapter) => GeekPieEcardSessionIssuer(
  endpoint: () => Uri.parse('https://geekpie.invalid/api/auth/third-party/ecard'), dio: _dio(adapter),);
