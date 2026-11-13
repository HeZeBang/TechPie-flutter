import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/native_genai_ids_exchange_io.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';
import 'package:techpie/services/session/cookie_provider.dart';

import '../support/fakes.dart';

const _provider = CookieProvider(cookies: 'CASTGC=synthetic-ids-cookie; route=ids');

GenAiResponse redirect(String location, {String? setCookie}) => GenAiResponse(
  statusCode: 302,
  headers: {'location': location, if (setCookie != null) 'set-cookie': setCookie},
  bytes: const Stream.empty(),
  close: () {},
);

ScriptedTransport sequence(List<GenAiResponse> responses) =>
    ScriptedTransport((_) async => responses.removeAt(0));

void main() {
  const blockedHtml = '<html>该服务暂不开放外网访问，仅支持校内访问</html>';
  for (final (status, body, kind) in [
    (404, blockedHtml, GenAiFailureKind.campusNetworkRequired),
    (404, '<html>Not Found</html>', GenAiFailureKind.rejected),
    (401, blockedHtml, GenAiFailureKind.authenticationRequired),
    (200, '<html>Login required</html>', GenAiFailureKind.authenticationRequired),
  ]) {
    test('native exchange distinguishes $status $kind from expired login', () async {
      final client = sequence([response(status: status, type: 'text/html', text: body)]);
      await expectLater(
        NativeGenAiIdsExchange(
          createTransport: () => client,
        ).exchange(_provider, GenAiCancellation()),
        throwsA(
          isA<GenAiFailure>()
              .having((error) => error.kind, 'kind', kind)
              .having(
                (error) => error.effectNotDispatched,
                'not dispatched',
                kind == GenAiFailureKind.campusNetworkRequired,
              ),
        ),
      );
      expect(client.requests, hasLength(1));
      expect(client.disposed, isTrue);
    });
  }

  test('native exchange cancellation while inspecting a campus error closes the client', () async {
    final listening = Completer<void>();
    final wire = StreamController<List<int>>(onListen: listening.complete);
    final client = sequence([response(status: 404, type: 'text/html', bytes: wire.stream)]);
    final cancel = GenAiCancellation();
    final expected = expectLater(
      NativeGenAiIdsExchange(createTransport: () => client).exchange(_provider, cancel),
      throwsA(failure(GenAiFailureKind.cancelled)),
    );
    await listening.future;
    cancel.cancel();
    await expected;
    expect(client.disposed, isTrue);
    await wire.close();
  });

  test('native exchange scopes cookies and intercepts the token callback', () async {
    final client = sequence([
      redirect(
        'https://ids.shanghaitech.edu.cn/authserver/login?service=genai',
        setCookie: 'JSESSIONID=genai-session; Path=/',
      ),
      redirect('https://genai.shanghaitech.edu.cn/htk/user/login?ticket=fixture-ticket'),
      redirect('https://genai.shanghaitech.edu.cn/?token=fixture-token'),
    ]);
    final exchange = NativeGenAiIdsExchange(createTransport: () => client);
    final credential = await exchange.exchange(_provider, GenAiCancellation());
    expect(credential.token, 'fixture-token');
    expect(client.requests, hasLength(3));
    expect(client.requests.first.headers['cookie'], isNull);
    expect(client.requests[1].headers['cookie'], _provider.cookies);
    expect(client.requests[2].headers['cookie'], 'JSESSIONID=genai-session');
    expect(client.requests.every((r) => !r.uri.queryParameters.containsKey('token')), isTrue);
    expect(client.disposed, isTrue);
  });

  for (final target in [
    'https://evil.test/?token=leak',
    'http://ids.shanghaitech.edu.cn/login',
    'https://ids.shanghaitech.edu.cn:8443/login',
    'https://genai.shanghaitech.edu.cn/?token=a#fragment',
    'https://user@genai.shanghaitech.edu.cn/?token=a',
  ]) {
    test('native exchange rejects an unsafe redirect $target before requesting it', () async {
      final client = sequence([redirect(target)]);
      await expectLater(
        NativeGenAiIdsExchange(
          createTransport: () => client,
        ).exchange(_provider, GenAiCancellation()),
        throwsA(failure(GenAiFailureKind.authenticationRequired)),
      );
      expect(client.requests, hasLength(1));
      expect(client.disposed, isTrue);
    });
  }

  test('joined Set-Cookie headers retain Expires dates and cookie paths', () async {
    final client = sequence([
      redirect(
        '/htk/oauth/callback',
        setCookie:
            'route=one; Path=/htk; Expires=Wed, 09 Jun 2038 10:18:14 GMT, '
            'other=two; Path=/elsewhere, CASTGC=must-not-leak; Path=/',
      ),
      redirect('https://genai.shanghaitech.edu.cn/?token=fixture-token'),
    ]);
    await NativeGenAiIdsExchange(
      createTransport: () => client,
    ).exchange(_provider, GenAiCancellation());
    expect(client.requests[1].headers['cookie'], 'route=one');
  });

  test('malformed IDS cookies fail safely before creating a native client', () async {
    var created = false;
    await expectLater(
      NativeGenAiIdsExchange(
        createTransport: () {
          created = true;
          return sequence([]);
        },
      ).exchange(
        const CookieProvider(cookies: 'CASTGC=synthetic-secret; invalid name=private-value'),
        GenAiCancellation(),
      ),
      throwsA(failure(GenAiFailureKind.transport)),
    );
    expect(created, isFalse);
  });

  test('cancellation while waiting for headers closes the native client', () async {
    final gate = Completer<GenAiResponse>();
    final client = ScriptedTransport((request) => request.cancellation.race(gate.future));
    final cancellation = GenAiCancellation();
    final pending = NativeGenAiIdsExchange(
      createTransport: () => client,
    ).exchange(_provider, cancellation);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel(GenAiFailureKind.accountChanged);
    await expectLater(pending, throwsA(failure(GenAiFailureKind.accountChanged)));
    expect(client.disposed, isTrue);
    gate.complete(response());
  });
}
