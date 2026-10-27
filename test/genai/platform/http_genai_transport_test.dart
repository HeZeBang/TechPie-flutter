@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/http_genai_transport.dart';

import '../support/fakes.dart';

void main() {
  test('native POST delivers answer before the server releases completion',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    final received = Completer<String>();
    final served = Completer<void>();
    final subscription = server.listen((request) async {
      received.complete(await utf8.decoder.bind(request).join());
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
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
    final streaming = api
        .streamChat(chatRequest(), 'synthetic-token', GenAiCancellation())
        .forEach((event) {
      events.add(event);
      if (event is GenAiTextDelta) partial.complete();
    });
    await partial.future.timeout(const Duration(seconds: 3));
    expect(served.isCompleted, isFalse);
    expect(jsonDecode(await received.future)['chatInfo'], '你好');
    release.complete();
    await streaming;
    await served.future;
    expect(events.whereType<GenAiChatFinished>().length, 1);
  });

  test(
      'cancellation before headers returns promptly and closes only that client',
      () async {
    final client = _PendingClient();
    final cancellation = GenAiCancellation();
    final transport = HttpGenAiTransport(createClient: () => client);
    addTearDown(transport.dispose);
    final pending = transport.send(
      method: 'POST',
      uri: Uri.https('example.invalid', '/chat'),
      cancellation: cancellation,
    );
    final expectation =
        expectLater(pending, throwsA(failure(GenAiFailureKind.cancelled)));
    cancellation.cancel();
    await expectation;
    expect(client.closed, isTrue);
    client.gate.completeError(
      http.ClientException('raw URL and token must stay private'),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('header timeout aborts the pending connection and sanitizes its failure',
      () async {
    final client = _PendingClient();
    final transport = HttpGenAiTransport(
      createClient: () => client,
      headerTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(transport.dispose);
    await expectLater(
      transport.send(
        method: 'GET',
        uri: Uri.https('example.invalid'),
        cancellation: GenAiCancellation(),
      ),
      throwsA(failure(GenAiFailureKind.timeout)),
    );
    expect(client.closed, isTrue);
    client.gate.completeError(http.ClientException('secret'));
  });

  test(
      'image generation requests receive dedicated image timeout and ignore short header timeout',
      () async {
    final client = _PendingClient();
    final transport = HttpGenAiTransport(
      createClient: () => client,
      headerTimeout: const Duration(milliseconds: 20),
      chatHeaderTimeout: const Duration(milliseconds: 20),
      imageTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(transport.dispose);

    // Chat SSE uses its dedicated header budget.
    final chatStopwatch = Stopwatch()..start();
    await expectLater(
      transport.send(
        method: 'POST',
        uri: Uri.parse('http://127.0.0.1/htk/chat/start/chat'),
        cancellation: GenAiCancellation(),
        headers: {'Accept': 'text/event-stream'},
      ),
      throwsA(failure(GenAiFailureKind.timeout)),
    );
    expect(chatStopwatch.elapsedMilliseconds, lessThan(100));

    // Image generation uses imageTimeout even with browser Accept header
    final imageStopwatch = Stopwatch()..start();
    await expectLater(
      transport.send(
        method: 'POST',
        uri: Uri.parse('http://127.0.0.1/htk/chat/start/chat'),
        cancellation: GenAiCancellation(),
        headers: {'Accept': 'application/json, text/plain, */*'},
      ),
      throwsA(failure(GenAiFailureKind.timeout)),
    );
    expect(imageStopwatch.elapsedMilliseconds, greaterThanOrEqualTo(120));
    client.gate.completeError(http.ClientException('done'));
  });

  test(
      'slow vision headers survive the short metadata budget and remain cancellable',
      () async {
    final clients = <_PendingClient>[];
    final transport = HttpGenAiTransport(
      createClient: () {
        final client = _PendingClient();
        clients.add(client);
        return client;
      },
      headerTimeout: const Duration(milliseconds: 10),
      chatHeaderTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(transport.dispose);
    final cancellation = GenAiCancellation();
    final pending = transport.send(
      method: 'POST',
      uri: Uri.https('example.invalid', '/htk/chat/start/chat'),
      cancellation: cancellation,
      headers: {'Accept': 'text/event-stream'},
      body: '{"imageUrl":"https://example.invalid/red.png"}',
    );
    final timer = Timer(const Duration(milliseconds: 40), () {
      clients.first.gate
          .complete(http.StreamedResponse(const Stream.empty(), 200));
    });
    addTearDown(timer.cancel);
    final result = await pending;
    expect(result.statusCode, 200);
    result.close();
    final stopped = transport.send(
      method: 'POST',
      uri: Uri.https('example.invalid', '/htk/chat/start/chat'),
      cancellation: cancellation,
      headers: {'Accept': 'text/event-stream'},
    );
    final expectation =
        expectLater(stopped, throwsA(failure(GenAiFailureKind.cancelled)));
    cancellation.cancel();
    await expectation;
    expect(clients.last.closed, isTrue);
    clients.last.gate.completeError(http.ClientException('cancelled'));
  });

  test('redirects cannot forward GenAI credentials to another origin',
      () async {
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
