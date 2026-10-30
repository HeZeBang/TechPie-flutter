import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/native_genai_ids_exchange_io.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/services/session/cookie_provider.dart';

import '../support/fakes.dart' show failure;

const _provider = CookieProvider(cookies: 'CASTGC=synthetic-ids-cookie; route=ids');

void main() {
  const blockedHtml = '<html>该服务暂不开放外网访问，仅支持校内访问</html>';
  for (final (status, body, kind) in [
    (404, blockedHtml, GenAiFailureKind.campusNetworkRequired),
    (404, '<html>Not Found</html>', GenAiFailureKind.rejected),
    (401, blockedHtml, GenAiFailureKind.authenticationRequired),
    (200, '<html>Login required</html>', GenAiFailureKind.authenticationRequired),
  ]) {
    test('native exchange distinguishes $status $kind from expired login', () async {
      final client = _Client([
        _Response(
          null,
          statusCode: status,
          contentType: 'text/html',
          body: Stream.value(utf8.encode(body)),
        ),
      ]);
      await expectLater(
        NativeGenAiIdsExchange(createClient: () => client).exchange(_provider, GenAiCancellation()),
        throwsA(
          isA<GenAiFailure>().having((error) => error.kind, 'kind', kind).having(
                (error) => error.effectNotDispatched,
                'not dispatched',
                kind == GenAiFailureKind.campusNetworkRequired,
              ),
        ),
      );
      expect(client.requests, hasLength(1));
      expect(client.closed, isTrue);
    });
  }

  test('native exchange cancellation while inspecting a campus error closes the client', () async {
    final listening = Completer<void>();
    final wire = StreamController<List<int>>(onListen: listening.complete);
    final client = _Client([
      _Response(null, statusCode: 404, contentType: 'text/html', body: wire.stream),
    ]);
    final cancel = GenAiCancellation();
    final expected = expectLater(
      NativeGenAiIdsExchange(createClient: () => client).exchange(_provider, cancel),
      throwsA(failure(GenAiFailureKind.cancelled)),
    );
    await listening.future;
    cancel.cancel();
    await expected;
    expect(client.closed, isTrue);
    await wire.close();
  });

  test('native exchange scopes cookies and intercepts the token callback', () async {
    final client = _Client([
      _Response(
        'https://ids.shanghaitech.edu.cn/authserver/login?service=genai',
        cookies: [Cookie('JSESSIONID', 'genai-session')..path = '/'],
      ),
      _Response(
        'https://genai.shanghaitech.edu.cn/htk/user/login?ticket=fixture-ticket',
      ),
      _Response('https://genai.shanghaitech.edu.cn/?token=fixture-token'),
    ]);
    final exchange = NativeGenAiIdsExchange(createClient: () => client);
    final credential = await exchange.exchange(_provider, GenAiCancellation());
    expect(credential.token, 'fixture-token');
    expect(client.requests, hasLength(3));
    expect(client.requests.first.cookies, isEmpty);
    expect(client.requests[1].cookies.map((c) => c.name), contains('CASTGC'));
    expect(client.requests[2].cookies.map((c) => c.name), ['JSESSIONID']);
    expect(client.requests.every((r) => !r.followRedirects), isTrue);
    expect(
      client.uris.every((u) => !u.queryParameters.containsKey('token')),
      isTrue,
    );
    expect(client.closed, isTrue);
  });

  for (final target in [
    'https://evil.test/?token=leak',
    'http://ids.shanghaitech.edu.cn/login',
    'https://ids.shanghaitech.edu.cn:8443/login',
    'https://genai.shanghaitech.edu.cn/?token=a#fragment',
    'https://user@genai.shanghaitech.edu.cn/?token=a',
  ]) {
    test('native exchange rejects an unsafe redirect $target before requesting it', () async {
      final client = _Client([_Response(target)]);
      await expectLater(
        NativeGenAiIdsExchange(createClient: () => client).exchange(_provider, GenAiCancellation()),
        throwsA(failure(GenAiFailureKind.authenticationRequired)),
      );
      expect(client.requests, hasLength(1));
      expect(client.closed, isTrue);
    });
  }

  test('malformed IDS cookies fail safely before creating a native client', () async {
    var created = false;
    await expectLater(
      NativeGenAiIdsExchange(
        createClient: () {
          created = true;
          return _Client([]);
        },
      ).exchange(
        const CookieProvider(
          cookies: 'CASTGC=synthetic-secret; invalid name=private-value',
        ),
        GenAiCancellation(),
      ),
      throwsA(failure(GenAiFailureKind.transport)),
    );
    expect(created, isFalse);
  });

  test('a rendered IDS login page requires reauthentication', () async {
    final client = _Client([_Response(null, statusCode: 200)]);
    await expectLater(
      NativeGenAiIdsExchange(createClient: () => client).exchange(_provider, GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(client.closed, isTrue);
  });

  test('cancellation while waiting for headers closes the native client', () async {
    final gate = Completer<HttpClientResponse>();
    final client = _Client([])..pendingResponse = gate.future;
    final cancellation = GenAiCancellation();
    final pending =
        NativeGenAiIdsExchange(createClient: () => client).exchange(_provider, cancellation);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel(GenAiFailureKind.accountChanged);
    await expectLater(
      pending,
      throwsA(failure(GenAiFailureKind.accountChanged)),
    );
    expect(client.closed, isTrue);
    gate.complete(_Response(null, statusCode: 200));
  });
}

class _Client implements HttpClient {
  _Client(this.responses);
  final List<_Response> responses;
  final requests = <_Request>[];
  final uris = <Uri>[];
  Future<HttpClientResponse>? pendingResponse;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uris.add(url);
    final request = _Request(pendingResponse ?? Future.value(responses.removeAt(0)));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  final cookies = <Cookie>[];
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    String? location, {
    this.cookies = const [],
    this.statusCode = 302,
    String? contentType,
    Stream<List<int>>? body,
  })  : headers = _Headers(location, contentType),
        _body = body ?? const Stream<List<int>>.empty();
  final Stream<List<int>> _body;
  @override
  final List<Cookie> cookies;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _body.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers(this.location, this.mediaType);
  final String? location;
  final String? mediaType;
  @override
  String? value(String name) => name == HttpHeaders.locationHeader
      ? location
      : name == HttpHeaders.contentTypeHeader
          ? mediaType
          : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
