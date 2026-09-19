import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_bind_code_client.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';

/// The exchange endpoint is the only way an OPENID gets in without a human
/// typing it, and every way it can say no has to reach the user as a sentence
/// they can act on. This file pins down that translation.
void main() {
  late List<String> urls;
  late List<Map<String, String>> headers;
  late List<String> bodies;

  EcardBindCodeClient answering(
    String body, {
    int status = 200,
    Duration timeout = const Duration(seconds: 15),
  }) => EcardBindCodeClient(
    timeout: timeout,
    send: (method, url, requestHeaders, requestBody) async {
      urls.add(url);
      headers.add(requestHeaders);
      bodies.add(requestBody);
      return (status, body);
    },
  );

  Future<AppFailure> failureOf(
    EcardBindCodeClient client, {
    String code = 'AB12CD',
  }) async {
    try {
      await client.exchange(code);
    } on AppFailure catch (failure) {
      return failure;
    }
    fail('expected the exchange to fail');
  }

  setUp(() {
    urls = <String>[];
    headers = <Map<String, String>>[];
    bodies = <String>[];
  });

  test('sends the code to the campus host, normalized, with the endpoint token', () async {
    final client = answering(
      '{"ok":true,"openid":"SYNTHETIC_OPENID_FROM_CODE","usertype":"8","orgid":"2"}',
    );

    await client.exchange(' ab12cd ');

    expect(Uri.parse(urls.single).host, EcardBindCodeClient.bindHost);
    expect(bodies.single, '{"code":"AB12CD"}');
    expect(headers.single['content-type'], 'application/json');
    expect(headers.single['X-Bind-Token'], isNotEmpty);
  });

  test('maps the mini-program usertype onto the OPENID channel', () async {
    const payload = '{"ok":true,"openid":"SYNTHETIC_OPENID_FROM_CODE"';

    final wechat = await answering('$payload,"usertype":"8"}').exchange('AB12CD');
    final alipay = await answering('$payload,"usertype":"18"}').exchange('AB12CD');
    // The usertype is not guaranteed to arrive as a string.
    final numeric = await answering('$payload,"usertype":8}').exchange('AB12CD');
    final unlabelled = await answering('$payload}').exchange('AB12CD');

    expect(wechat.channel, EcardOpenIdChannel.wechat);
    expect(alipay.channel, EcardOpenIdChannel.alipay);
    expect(numeric.channel, EcardOpenIdChannel.wechat);
    expect(unlabelled.channel, EcardOpenIdChannel.wechat);
  });

  test('an empty code never reaches the endpoint', () async {
    final failure = await failureOf(
      answering('{"ok":true,"openid":"A"}'),
      code: '   ',
    );

    expect(failure.kind, FailureKind.invalidInput);
    expect(failure.safeMessage, '请输入绑定码');
    expect(urls, isEmpty);
  });

  test('translates every endpoint refusal into a user-facing failure', () async {
    const cases = <int, (FailureKind, String)>{
      400: (FailureKind.invalidInput, '绑定码格式不正确'),
      401: (FailureKind.permissionDenied, '绑定服务未授权，请联系管理员'),
      404: (FailureKind.authenticationExpired, '绑定码无效或已过期，请在小程序重新获取'),
      410: (FailureKind.authenticationExpired, '绑定码无效或已过期，请在小程序重新获取'),
      500: (FailureKind.server, '绑定服务暂时不可用，请稍后重试'),
    };

    for (final entry in cases.entries) {
      final (kind, message) = entry.value;
      final failure = await failureOf(
        answering('{"ok":false,"error":"synthetic"}', status: entry.key),
      );

      expect(failure.kind, kind, reason: 'status ${entry.key}');
      expect(failure.safeMessage, message, reason: 'status ${entry.key}');
    }
  });

  test('an answer that is not the bind service is reported as unavailable', () async {
    // With the tunnel off, the ordinary campus host answers instead of ours.
    final failure = await failureOf(
      answering('<html><body>404 Not Found</body></html>', status: 404),
    );

    expect(failure.kind, FailureKind.server);
    expect(failure.safeMessage, '绑定服务暂时不可用，请稍后重试');
  });

  test('a 200 without an OPENID is a protocol failure', () async {
    final failure = await failureOf(answering('{"ok":true,"openid":"   "}'));

    expect(failure.kind, FailureKind.protocol);
    expect(failure.safeMessage, '绑定服务返回异常，请重试');
  });

  test('transport failures keep the tunnel hint', () async {
    final offline = await failureOf(
      EcardBindCodeClient(
        send: (method, url, headers, body) async =>
            throw const SocketException('synthetic'),
      ),
    );
    final slow = await failureOf(
      EcardBindCodeClient(
        timeout: const Duration(milliseconds: 20),
        send: (method, url, headers, body) => Completer<(int, String)>().future,
      ),
    );

    expect(offline.kind, FailureKind.network);
    expect(offline.safeMessage, '网络异常，请检查劫持是否开启后重试');
    expect(slow.kind, FailureKind.timeout);
    expect(slow.safeMessage, '网络异常，请检查劫持是否开启后重试');
  });
}
