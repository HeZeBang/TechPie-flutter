import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';
import 'package:techpie/features/campus_card/data/api/ecard_cipher.dart';
import 'package:techpie/services/campus_card_http_trace.dart';
import 'package:techpie/services/debug_logger.dart';

void main() {
  test('online code aliases are redacted without modifying the response', () async {
    final logger = DebugLogger()..enabled = true;
    final dio = Dio(BaseOptions(baseUrl: 'https://ecard.test'));
    addTearDown(() => dio.close(force: true));
    final receipt = {'success': true, 'data': {'code': 'secret-online-code', 'qrcode': 'secret-qr', 'cardbal': '65.48'}};
    dio.interceptors.add(campusCardHttpTrace(logger));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: receipt, statusCode: 200), true);
    },),);
    final response = await dio.post<Object?>('/offlineCode/openVirtualcard');
    expect((response.data as Map)['data'], receipt['data']);
    final logged = logger.entries.last.responseBody!;
    expect(logged, isNot(contains('secret-')));
    expect(jsonDecode(logged)['data']['cardbal'], '65.48');
  });

  test('shared debug switch records card requests, responses and failures',
      () async {
    final logger = DebugLogger();
    final dio = Dio(BaseOptions(baseUrl: 'https://ecard.test'));
    const identity = EcardVerifiedIdentity(
      subjectId: 'subject',
      idSerial: 'student',
      cardId: 'card',
    );
    final client = EcardApiClient(
      dio: dio,
      httpTrace: campusCardHttpTrace(logger),
      sessionReader: () async => const EcardSession(
        sessionCookie: 'JSESSIONID=secret-cookie',
        openId: 'secret-openid',
        orgId: '2',
        subjectId: 'subject',
      ),
      identityGuard: () async => identity,
      onAuthenticationExpired: (_) async {},
      onIdentityMismatch: () async {},
    );
    addTearDown(client.dispose);
    var failure = false;
    Completer<void>? responseGate;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (responseGate != null) await responseGate.future;
          if (failure) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
              true,
            );
          } else {
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'datajson': EcardCipher.encodeWithKey(
                    {
                      'balance': 123,
                      'payCode': 'secret-paycode',
                      'nested': {'userprivatekey': 'secret-key'},
                    },
                    'AbCdEfGhIjKlMnOp',
                  ),
                },
              ),
              true,
            );
          }
        },
      ),
    );
    await client.get('/balance', {});
    expect(logger.entries, isEmpty);

    logger.enabled = true;
    await client.post('/balance', {'password': 'secret-password'});
    expect(logger.entries, hasLength(2));
    final request = logger.entries.first;
    final response = logger.entries.last;
    expect(request.method, 'POST');
    expect(request.url, 'https://ecard.test/balance');
    expect(request.tag, 'Campus Card');
    expect(request.requestBody, contains('decryptedDatajson'));
    expect(response.statusCode, 200);
    expect(jsonDecode(response.responseBody!)['balance'], 123);
    // The wait is reported split: how long the request took, and how much of it
    // happened before anything was sent. A send is not a duration.
    expect(response.durationMicros, isNotNull);
    expect(response.prepMicros, isNotNull);
    expect(request.durationMicros, isNull);
    expect(
      '${request.requestBody}${response.responseBody}${request.url}',
      isNot(contains('secret-')),
    );

    failure = true;
    await expectLater(client.get('/unreachable', {}), throwsA(anything));
    expect(logger.entries.last.error, 'connectionError');
    expect(logger.entries.last.prepMicros, isNotNull);

    failure = false;
    responseGate = Completer<void>();
    final inFlight = client.get('/in-flight', {});
    await Future<void>.delayed(Duration.zero);
    final count = logger.entries.length;
    logger.enabled = false;
    responseGate.complete();
    await inFlight;
    expect(logger.entries, hasLength(count));
    responseGate = null;
    await client.get('/disabled', {});
    expect(logger.entries, hasLength(count));
  });

  test('scan code fingerprints prove both phases carry the same value',
      () async {
    final logger = DebugLogger()..enabled = true;
    final dio = Dio(BaseOptions(baseUrl: 'https://ecard.test'));
    const identity = EcardVerifiedIdentity(
      subjectId: 'subject',
      idSerial: 'student',
      cardId: 'card',
    );
    const code = '.s:p010_SYNTHETIC%2B%2F%3D%3D';
    final client = EcardApiClient(
      dio: dio,
      httpTrace: campusCardHttpTrace(logger),
      sessionReader: () async => const EcardSession(
        sessionCookie: 'JSESSIONID=secret-cookie',
        openId: 'secret-openid',
        orgId: '2',
        subjectId: 'subject',
      ),
      identityGuard: () async => identity,
      onAuthenticationExpired: (_) async {},
      onIdentityMismatch: () async {},
    );
    addTearDown(client.dispose);
    var calls = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'datajson': EcardCipher.encodeWithKey(
                  calls == 1
                      ? {
                          'success': true,
                          'url': '/pages/common/inputPass/inputPass',
                          'data': {'qrcode': code},
                        }
                      : {
                          'success': true,
                          'message': '密码错误',
                          'url': '/pages/common/fail/fail',
                          'data': 'payment rejected',
                        },
                  'AbCdEfGhIjKlMnOp',
                ),
              },
            ),
            true,
          );
        },
      ),
    );

    final challenge = await client.post('/scan/scanningResult', {
      'qrcode': code,
      'paytime': 1,
    });
    await client.submitScanPayment(
      {'qrcode': code, 'paytime': 2, 'password': '111222'},
      (challenge as EcardResponseMap).requestContext,
    );

    final fingerprints = <Map<String, Object?>>[];
    for (final entry in logger.entries) {
      final body = entry.requestBody ?? entry.responseBody;
      if (body == null) continue;
      final decoded = jsonDecode(body) as Map<String, Object?>;
      final fingerprint = decoded['qrcodeFingerprint'];
      if (fingerprint is Map) {
        fingerprints.add(fingerprint.cast<String, Object?>());
      }
    }

    expect(fingerprints, hasLength(3));
    expect(fingerprints.map(jsonEncode).toSet(), hasLength(1));
    expect(fingerprints.first['length'], code.length);
    expect(
      logger.entries
          .map((e) => '${e.requestBody}${e.responseBody}')
          .join(),
      isNot(contains('p010_')),
    );
  });

  test('redaction covers campus credentials in nested and malformed JSON', () {
    final result = DebugLogger.redactSensitive(
      jsonEncode({
        'OpenID': 'secret-openid',
        'nested': [
          {'JSESSIONID': 'secret-session', 'authorinfo': 'secret-offline'},
        ],
        'datajson': 'secret-wire',
        'balance': 123,
      }),
    );
    expect(result, isNot(contains('secret-')));
    expect(result, contains('123'));
    expect(
      DebugLogger.redactSensitive('{"OPENID":"secret-openid", broken'),
      isNot(contains('secret-openid')),
    );
  });
}
