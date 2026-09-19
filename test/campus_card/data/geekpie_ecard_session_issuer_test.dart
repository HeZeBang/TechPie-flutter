import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/auth/geekpie_ecard_session_issuer.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';

Map<String, Object?> response() => {'success': true, 'data': {
  'sid': 'STUDENT', 'token': 'JSESSIONID=synthetic',
  'raw': {'cookies': 'JSESSIONID=synthetic', 'orgid': '2', 'idserial': 'STUDENT', 'cardid': 'CARD'},
},};

void main() {
  test('uses the selected GeekPie endpoint and accepts only a consistent session', () async {
    final adapter = _Adapter(response());
    var endpoint = Uri.parse('http://localhost:3000/api/auth/third-party/ecard');
    final issuer = GeekPieEcardSessionIssuer(endpoint: () => endpoint,
      dio: Dio()..httpClientAdapter = adapter,);
    final session = await issuer.issue('SYNTHETIC_OPENID_123456');
    expect(session.cookie, 'JSESSIONID=synthetic');
    expect(session.idSerial, 'STUDENT');
    expect(adapter.requests.single.uri, endpoint);
    expect(adapter.requests.single.data, {'method': 'wechat_openid', 'openid': 'SYNTHETIC_OPENID_123456'});
    expect(adapter.requests.single.followRedirects, isFalse);
    endpoint = Uri.parse('https://example.invalid/api/auth/third-party/ecard');
    await issuer.issue('SYNTHETIC_OPENID_123456');
    expect(adapter.requests.last.uri, endpoint);
  });

  test('Alipay OPENID is sent using the Alipay method', () async {
    final adapter = _Adapter(response());
    final issuer = GeekPieEcardSessionIssuer(endpoint: () => Uri.parse('http://localhost:3000/api/auth/third-party/ecard'),
      dio: Dio()..httpClientAdapter = adapter,);
    await issuer.issue('SYNTHETIC_OPENID_123456', channel: EcardOpenIdChannel.alipay);
    expect(adapter.requests.single.data, {'method': 'alipay_openid', 'openid': 'SYNTHETIC_OPENID_123456'});
  });

  test('rejects mismatched identity, cookies, header injection and incomplete payloads', () async {
    for (final field in ['sid', 'cookie', 'newline', 'missing']) {
      final body = response();
      final data = body['data']! as Map;
      final raw = data['raw'] as Map;
      switch(field) {
        case 'sid': data['sid'] = 'DIFFERENT';
        case 'cookie': raw['cookies'] = 'JSESSIONID=another';
        case 'newline': data['token'] = raw['cookies'] = 'JSESSIONID=abc\r\nHeader: injected';
        case 'missing': raw.remove('cardid');
      }
      final adapter = _Adapter(body);
      final issuer = GeekPieEcardSessionIssuer(endpoint: () => Uri.parse('http://localhost:3000/api/auth/third-party/ecard'),
        dio: Dio()..httpClientAdapter = adapter,);
      await expectLater(issuer.issue('SYNTHETIC_OPENID_123456'), throwsA(isA<AppFailure>()));
      expect(adapter.requests, hasLength(1));
    }
  });

  test('failure never falls back to the campus root or another endpoint', () async {
    final adapter = _Adapter(response(), status: 503);
    final issuer = GeekPieEcardSessionIssuer(endpoint: () => Uri.parse('http://localhost:3000/api/auth/third-party/ecard'),
      dio: Dio()..httpClientAdapter = adapter,);
    await expectLater(issuer.issue('SYNTHETIC_OPENID_123456'), throwsA(isA<AppFailure>()));
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.host, 'localhost');
  });

  test('changing localhost setting discards an in-flight response', () async {
    final adapter = _Adapter(response())..wait = Completer<void>();
    var endpoint = Uri.parse('http://localhost:3000/api/auth/third-party/ecard');
    final issuer = GeekPieEcardSessionIssuer(endpoint: () => endpoint, dio: Dio()..httpClientAdapter = adapter);
    final pending = issuer.issue('SYNTHETIC_OPENID_123456');
    final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
    await adapter.started.future;
    endpoint = Uri.parse('https://example.invalid/api/auth/third-party/ecard');
    adapter.wait!.complete();
    await rejected;
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, {this.status = 200});
  final Object body;
  final int status;
  final requests = <RequestOptions>[];
  Completer<void>? wait;
  final started = Completer<void>();
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    await wait?.future;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override void close({bool force = false}) {}
}
