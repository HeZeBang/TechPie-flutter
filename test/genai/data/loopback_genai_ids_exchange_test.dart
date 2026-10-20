import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/loopback_genai_ids_exchange.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/services/session/cookie_provider.dart';

import '../support/fakes.dart';

void main() {
  const provider = CookieProvider(
    cookies: 'CASTGC=ids-tgc',
    studentId: '20240001',
    domain: 'ids.shanghaitech.edu.cn',
  );
  test(
      'browser bridge exchanges existing IDS cookies for a separate credential',
      () async {
    final transport = ScriptedTransport((request) async {
      expect(
        request.uri.toString(),
        'http://127.0.0.1:18768/preview/ids-exchange',
      );
      expect(jsonDecode(request.body!), {'cookies': 'CASTGC=ids-tgc'});
      expect(request.headers.containsKey('X-Access-Token'), isFalse);
      return response(
        text: '{"success":true,"code":200,"result":{"token":"genai-token"}}',
      );
    });
    final exchange = LoopbackGenAiIdsExchange(
      'http://127.0.0.1:18768',
      transport: transport,
    );
    expect(
      (await exchange.exchange(provider, GenAiCancellation())).token,
      'genai-token',
    );
  });
  test('expired IDS session requests the existing renewal flow', () async {
    final transport = ScriptedTransport((_) async => response(status: 401));
    final exchange = LoopbackGenAiIdsExchange(
      'http://127.0.0.1:18768',
      transport: transport,
    );
    await expectLater(
      exchange.exchange(provider, GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
  });
  test('campus cookies cannot be sent to a remote preview broker', () {
    expect(
      () => LoopbackGenAiIdsExchange('https://evil.example'),
      throwsArgumentError,
    );
  });
}
