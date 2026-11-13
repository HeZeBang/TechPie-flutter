@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/url_session_genai_transport.dart';

import '../support/fakes.dart' show failure;

void main() {
  test('Apple URLSession streams bytes before the loopback response finishes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    final subscription = server.listen((request) async {
      expect(request.headers.value('accept'), 'text/event-stream');
      expect(request.contentLength, 2);
      expect(await utf8.decoder.bind(request).join(), '{}');
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      request.response.write('data: first\n\n');
      await request.response.flush();
      await release.future;
      await request.response.close();
    });
    final transport = UrlSessionGenAiTransport();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      transport.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });
    final response = await transport.send(
      method: 'POST',
      uri: Uri.parse('http://127.0.0.1:${server.port}/htk/chat/start/chat'),
      headers: {'Accept': 'text/event-stream'},
      body: '{}',
      cancellation: GenAiCancellation(),
    );
    final iterator = StreamIterator(response.bytes);
    expect(await iterator.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(utf8.decode(iterator.current), contains('data: first'));
    expect(release.isCompleted, isFalse);
    await iterator.cancel();
  });

  test('Apple URLSession leaves redirects under caller control', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      expect(request.headers.value('X-Access-Token'), 'synthetic');
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set('location', '/must-not-follow');
      await request.response.close();
    });
    final transport = UrlSessionGenAiTransport();
    addTearDown(() async {
      transport.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });
    final response = await transport.send(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:${server.port}/start'),
      cancellation: GenAiCancellation(),
      headers: {'X-Access-Token': 'synthetic'},
    );
    expect(response.statusCode, HttpStatus.found);
    response.close();
    expect(paths, ['/start']);
  });

  test('Apple URLSession cancellation also works before headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    final release = Completer<void>();
    final subscription = server.listen((request) async {
      received.complete();
      await release.future;
      await request.response.close();
    });
    final transport = UrlSessionGenAiTransport();
    addTearDown(() async {
      release.complete();
      transport.dispose();
      await subscription.cancel();
      await server.close(force: true);
    });
    final cancellation = GenAiCancellation();
    final pending = transport.send(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1:${server.port}/wait'),
      cancellation: cancellation,
    );
    final expected = expectLater(pending, throwsA(failure(GenAiFailureKind.cancelled)));
    await received.future.timeout(const Duration(seconds: 5));
    cancellation.cancel();
    await expected.timeout(const Duration(seconds: 2));
  });
}
