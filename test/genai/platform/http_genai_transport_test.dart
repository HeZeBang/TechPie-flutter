@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/http_genai_transport.dart';

import '../support/fakes.dart';

void main() {
  test('chat tolerates prefill after headers but cancellation still closes the stream', () async {
    final client = _PendingClient();
    final source = StreamController<List<int>>();
    final transport = HttpGenAiTransport(
      createClient: () => client,
      idleTimeout: const Duration(milliseconds: 5),
      chatIdleTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(transport.dispose);
    final cancellation = GenAiCancellation();
    final pending = transport.send(
      method: 'POST',
      uri: Uri.https('example.invalid', '/htk/chat/start/chat'),
      cancellation: cancellation,
      headers: {'Accept': 'text/event-stream'},
    );
    client.gate.complete(http.StreamedResponse(source.stream, 200));
    final response = await pending;
    final iterator = StreamIterator(response.bytes);
    final first = iterator.moveNext();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    source.add([1]);
    expect(await first, true);
    final stopped = expectLater(iterator.moveNext(), throwsA(failure(GenAiFailureKind.cancelled)));
    cancellation.cancel();
    source.add([2]);
    await stopped;
    expect(client.closed, true);
    await iterator.cancel();
    await source.close();
  });

  test('native POST delivers answer before the server releases completion', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    final received = Completer<String>();
    final served = Completer<void>();
    final subscription = server.listen((request) async {
      received.complete(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.bufferOutput = false;
      request.response.write(sseChunk(text: '你好'));
      await request.response.flush();
      await release.future;
      request.response.write(sseChunk(finish: 'stop'));
      await request.response.close();
      served.complete();
    });
    final transport = HttpGenAiTransport();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      transport.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });
    final api = GenAiApiClient(
      transport: transport,
      apiBase: Uri.parse('http://127.0.0.1:${server.port}/htk/'),
    );
    final partial = Completer<void>();
    final events = <GenAiChatEvent>[];
    final streaming = api.streamChat(chatRequest(), 'synthetic-token', GenAiCancellation()).forEach(
      (event) {
        events.add(event);
        if (event is GenAiTextDelta) partial.complete();
      },
    );
    await partial.future.timeout(const Duration(seconds: 3));
    expect(served.isCompleted, isFalse);
    expect(jsonDecode(await received.future)['chatInfo'], '你好');
    release.complete();
    await streaming;
    await served.future;
    expect(events.whereType<GenAiChatFinished>().length, 1);
  });

  test('cancelling a vision request before headers closes the waiting client', () async {
    final client = _PendingClient();
    final cancellation = GenAiCancellation();
    final transport = HttpGenAiTransport(createClient: () => client);
    addTearDown(transport.dispose);
    final pending = transport.send(
      method: 'POST',
      uri: Uri.https('example.invalid', '/htk/chat/start/chat'),
      headers: {'Accept': 'text/event-stream'},
      body: '{"imageUrl":"temp/red.png"}',
      cancellation: cancellation,
    );
    final expectation = expectLater(pending, throwsA(failure(GenAiFailureKind.cancelled)));
    cancellation.cancel();
    await expectation;
    expect(client.closed, isTrue);
    client.gate.completeError(http.ClientException('raw URL and token must stay private'));
    await Future<void>.delayed(Duration.zero);
  });

  for (final (path, accept, deadline) in [
    ('/htk/user/info', 'application/json', const Duration(seconds: 1)),
    ('/htk/chat/start/chat', 'text/event-stream', const Duration(seconds: 2)),
    ('/htk/chat/start/chat', 'application/json, text/plain, */*', const Duration(seconds: 3)),
  ]) {
    test('$path with $accept aborts at its configured header deadline', () {
      fakeAsync((clock) {
        final client = _PendingClient();
        final transport = HttpGenAiTransport(
          createClient: () => client,
          headerTimeout: const Duration(seconds: 1),
          chatHeaderTimeout: const Duration(seconds: 2),
          imageTimeout: const Duration(seconds: 3),
        );
        final pending = transport.send(
          method: path.endsWith('chat') ? 'POST' : 'GET',
          uri: Uri.https('example.invalid', path),
          cancellation: GenAiCancellation(),
          headers: {'Accept': accept},
        );
        Object? failureSeen;
        unawaited(
          pending.then<void>(
            (_) => fail('Received headers from a pending client'),
            onError: (Object error) {
              failureSeen = error;
            },
          ),
        );
        const tick = Duration(microseconds: 1);
        clock.elapse(deadline - tick);
        expect(client.closed, isFalse);
        clock.elapse(tick);
        expect(failureSeen, failure(GenAiFailureKind.timeout));
        expect(client.closed, isTrue);
        client.gate.completeError(http.ClientException('secret'));
        clock.flushMicrotasks();
        transport.dispose();
      });
    });
  }

  test('redirects cannot forward GenAI credentials to another origin', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set('location', '/must-not-follow');
      await request.response.close();
    });
    final transport = HttpGenAiTransport();
    addTearDown(() async {
      transport.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });
    final result = await transport.send(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:${server.port}/start'),
      cancellation: GenAiCancellation(),
      headers: {'X-Access-Token': 'synthetic'},
    );
    expect(result.statusCode, HttpStatus.found);
    result.close();
    expect(paths, ['/start']);
  });
}

final class _PendingClient extends http.BaseClient {
  final gate = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => gate.future;
  @override
  void close() {
    closed = true;
  }
}
