import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';
import 'package:techpie/features/campus_card/data/api/ecard_cipher.dart';

void main() {
  const key = 'AbCdEfGhIjKlMnOp';
  const subjectId = 'test-subject';
  const identity = EcardVerifiedIdentity(
    subjectId: subjectId,
    idSerial: 'TEST-ID-SERIAL',
    cardId: 'TEST-CARD-ID',
  );

  group('EcardCipher', () {
    test('matches the documented key permutation', () {
      expect(EcardCipher.encodeHeader(key), 'jIhGfEdCbApOnMlK');
      expect(EcardCipher.decodeHeader('jIhGfEdCbApOnMlK'), key);
    });

    test('matches an OpenSSL AES-128-ECB-PKCS7 vector', () {
      final envelope = EcardCipher.encodeWithKey({'code': 'abc', 'n': 1}, key);
      expect(
        envelope,
        'jIhGfEdCbApOnMlKxon/WjfDlQ4cQy8wUg4Iz8a71vR0PtdnPN+VpQ3WT3k=',
      );
      expect(EcardCipher.decodeEnvelope(envelope), <String, Object?>{
        'code': 'abc',
        'n': 1,
      });
    });

    test('passes through responses without datajson', () {
      final body = {'success': false, 'message': 'plain'};
      expect(EcardCipher.decodeResponse(body), same(body));
    });

    test('normalizes an outer JSON string before decrypting datajson', () {
      final encrypted = EcardCipher.encodeWithKey(
        {
          'success': true,
          'message': 'CORE10008',
        },
        key,
      );

      expect(EcardCipher.decodeResponse(jsonEncode({'datajson': encrypted})), {
        'success': true,
        'message': 'CORE10008',
      });
    });

    test(
      'parses a JSON object returned as a whitespace-prefixed JSON string',
      () {
        final whitespace = EcardCipher.encodeWithKey(
          '  {"success":true,"data":[]}',
          key,
        );

        expect(EcardCipher.decodeEnvelope(whitespace), {
          'success': true,
          'data': <Object>[],
        });
      },
    );

    test('rejects truncated and malformed encrypted responses', () {
      expect(() => EcardCipher.decodeEnvelope('short'), throwsFormatException);
      expect(
        () => EcardCipher.decodeEnvelope('jIhGfEdCbApOnMlK***'),
        throwsFormatException,
      );
    });
  });

  group('EcardApiClient', () {
    test('lets Dio encode GET datajson exactly once', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _CaptureAdapter();
      dio.httpClientAdapter = adapter;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=test-only',
          openId: 'test-openid',
          orgId: '2',
          subjectId: subjectId,
        ),
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );

      await client.get('/test', const {'value': 1});

      final uri = adapter.lastOptions!.uri;
      expect(uri.query, contains('datajson='));
      expect(uri.query, contains('%2F'));
      expect(uri.query, contains('%2B'));
      expect(uri.query, isNot(contains('%252F')));
    });

    test('keeps request OpenID and cookie from the same account snapshot',
        () async {
      const accountA = EcardSession(
        sessionCookie: 'SESSION=account-a',
        openId: 'test-open-id',
        orgId: '2',
        subjectId: subjectId,
      );
      const accountB = EcardSession(
        sessionCookie: 'SESSION=account-b',
        openId: 'other-open-id',
        orgId: '2',
        subjectId: 'other-subject',
      );
      var active = accountA;
      final adapter = _CaptureAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'))
        ..httpClientAdapter = adapter;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(
          keyGenerator: () {
            active = accountB;
            return key;
          },
        ),
        sessionReader: () async => active,
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );
      addTearDown(client.dispose);
      await expectLater(
        client.post('/test', const {}),
        throwsA(isA<AppFailure>()),
      );
      final options = adapter.lastOptions!;
      expect(options.headers['cookie'], accountA.sessionCookie);
      final body = options.data as Map<String, Object?>;
      final request = EcardCipher.decodeEnvelope(body['datajson']! as String)
          as Map<String, dynamic>;
      expect(request['openid'], accountA.openId);
    });

    test('rejects a business response for another eCard identity', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.httpClientAdapter = _CaptureAdapter(
        body: const {
          'success': true,
          'data': {'idserial': 'OTHER-ID-SERIAL'},
        },
      );
      var mismatchRejected = false;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=test-only',
          openId: 'test-openid',
          orgId: '2',
          subjectId: subjectId,
        ),
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () => mismatchRejected = true,
      );

      await expectLater(
        client.get('/test', const {}),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'AUTH_RESPONSE_IDENTITY_MISMATCH',
          ),
        ),
      );
      expect(mismatchRejected, isTrue);
    });

    test('does not send when the active account subject changed', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _CaptureAdapter();
      dio.httpClientAdapter = adapter;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=test-only',
          openId: 'different-openid',
          orgId: '2',
          subjectId: 'different-subject',
        ),
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );

      await expectLater(
        client.get('/test', const {}),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'AUTH_SESSION_SUBJECT_CHANGED',
          ),
        ),
      );
      expect(adapter.requestCount, 0);
    });

    test('does not send stale identifiers from another account', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _CaptureAdapter();
      dio.httpClientAdapter = adapter;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=test-only',
          openId: 'test-openid',
          orgId: '2',
          subjectId: subjectId,
        ),
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );

      await expectLater(
        client.get('/card/cardQuotaModify', const {
          'idserial': 'OTHER-ID-SERIAL',
          'cardid': 'OTHER-CARD-ID',
        }),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'AUTH_REQUEST_IDENTITY_MISMATCH',
          ),
        ),
      );
      expect(adapter.requestCount, 0);
    });

    test('allows the card-binding endpoint to target a new student number',
        () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _CaptureAdapter();
      dio.httpClientAdapter = adapter;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=test-only',
          openId: 'test-openid',
          orgId: '2',
          subjectId: subjectId,
        ),
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );

      await client.post('/bind/wechatBind', const {
        'idserial': 'NEW-STUDENT',
      });

      expect(adapter.requestCount, 1);
    });

    test('concurrent business requests remain identity-serialized', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _ConcurrencyAdapter();
      dio.httpClientAdapter = adapter;
      var guardCalls = 0;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=test-only',
          openId: 'test-openid',
          orgId: '2',
          subjectId: subjectId,
        ),
        identityGuard: () async {
          guardCalls++;
          return identity;
        },
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );

      final responses = await Future.wait([
        for (var index = 0; index < 4; index++)
          client.get('/test', {'index': index}),
      ]);

      expect(responses, hasLength(4));
      expect(guardCalls, 4);
      expect(adapter.requestCount, 4);
      expect(adapter.maxConcurrentRequests, 1);
    });

    test('discards a response when the account changes in flight', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _BlockingAdapter();
      dio.httpClientAdapter = adapter;
      var session = const EcardSession(
        sessionCookie: 'SESSION=account-a',
        openId: 'account-a-openid',
        orgId: '2',
        subjectId: subjectId,
      );
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => session,
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {},
        onIdentityMismatch: () {},
      );

      final pending = client.get('/test', const {});
      await adapter.started.future;
      session = const EcardSession(
        sessionCookie: 'SESSION=account-b',
        openId: 'account-b-openid',
        orgId: '2',
        subjectId: 'account-b-subject',
      );
      adapter.release.complete();

      await expectLater(
        pending,
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'AUTH_SESSION_SUBJECT_CHANGED',
          ),
        ),
      );
    });

    test('maps 401 to auth expiry and does not expose credentials', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.httpClientAdapter = _CaptureAdapter(statusCode: 401);
      var expired = false;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => const EcardSession(
          sessionCookie: 'SESSION=secret-test-value',
          openId: 'secret-openid',
          orgId: '2',
          subjectId: subjectId,
        ),
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) => expired = true,
        onIdentityMismatch: () {},
      );

      try {
        await client.get('/test', const {});
        fail('Expected AppFailure');
      } on AppFailure catch (failure) {
        expect(failure.kind, FailureKind.authenticationExpired);
        expect(failure.toString(), isNot(contains('secret')));
      }
      expect(expired, isTrue);
    });

    test(
      'replays a GET once after successful single-flight recovery',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
        final adapter = _SequenceAdapter([401, 200]);
        dio.httpClientAdapter = adapter;
        var session = const EcardSession(
          sessionCookie: 'SESSION=expired-test-value',
          openId: 'test-openid',
          orgId: '2',
          subjectId: subjectId,
        );
        var recoveries = 0;
        final client = EcardApiClient(
          dio: dio,
          cipher: EcardCipher(keyGenerator: () => key),
          sessionReader: () async => session,
          identityGuard: () async => identity,
          onAuthenticationExpired: (_) {
            recoveries++;
            session = const EcardSession(
              sessionCookie: 'SESSION=recovered-test-value',
              openId: 'test-openid',
              orgId: '2',
              subjectId: subjectId,
            );
          },
          onIdentityMismatch: () {},
        );

        final response = await client.get('/home/userImageIsexists', const {});

        expect(response, {'success': true});
        expect(recoveries, 1);
        expect(adapter.requestCount, 2);
      },
    );

    test('does not replay a mutation after successful session recovery', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = _SequenceAdapter([401, 200]);
      dio.httpClientAdapter = adapter;
      var session = const EcardSession(
        sessionCookie: 'SESSION=expired-test-value',
        openId: 'test-openid',
        orgId: '2',
        subjectId: subjectId,
      );
      var recoveries = 0;
      final client = EcardApiClient(
        dio: dio,
        cipher: EcardCipher(keyGenerator: () => key),
        sessionReader: () async => session,
        identityGuard: () async => identity,
        onAuthenticationExpired: (_) {
          recoveries++;
          session = const EcardSession(
            sessionCookie: 'SESSION=recovered-test-value',
            openId: 'test-openid',
            orgId: '2',
            subjectId: subjectId,
          );
        },
        onIdentityMismatch: () {},
      );

      await expectLater(client.post('/scan/scanningResult', const {'qrcode': 'SYNTHETIC'}),
          throwsA(isA<AppFailure>()),);
      expect(recoveries, 1);
      expect(adapter.requestCount, 1);
    });
  });
}

final class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter({this.statusCode = 200, this.body = const {'success': true}});

  final int statusCode;
  final Object body;
  RequestOptions? lastOptions;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    lastOptions = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _ConcurrencyAdapter implements HttpClientAdapter {
  int requestCount = 0;
  int concurrentRequests = 0;
  int maxConcurrentRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    concurrentRequests++;
    if (concurrentRequests > maxConcurrentRequests) {
      maxConcurrentRequests = concurrentRequests;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
    concurrentRequests--;
    return ResponseBody.fromString(
      jsonEncode({'success': true}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _BlockingAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await release.future;
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'account': 'account-a'}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this._statusCodes);

  final List<int> _statusCodes;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    if (_statusCodes.isEmpty) throw StateError('No queued status code');
    return ResponseBody.fromString(
      jsonEncode({'success': true}),
      _statusCodes.removeAt(0),
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
