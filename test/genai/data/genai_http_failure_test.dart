import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_http_failure.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/presentation/genai_copy.dart';

import '../support/fakes.dart';

const _blockedHtml = '<!DOCTYPE html><html><body>'
    '<div class="info1">该服务暂不开放外网访问，仅支持校内访问</div></body></html>';

Matcher get _campusFailure => isA<GenAiFailure>()
    .having((error) => error.kind, 'kind', GenAiFailureKind.campusNetworkRequired)
    .having((error) => error.statusCode, 'HTTP status', 404)
    .having((error) => error.effectNotDispatched, 'not dispatched', isTrue);

void main() {
  final requests = <String, Future<Object?> Function(GenAiApiClient, GenAiCancellation)>{
    'JSON GET': (api, cancel) => api.listModels('token', cancel),
    'JSON POST': (api, cancel) => api.generateImage(
          'token',
          GenAiImageRequest(
            prompt: 'A square',
            model: const GenAiModel(name: 'Image', aiType: 'image', rootAiType: 'image', status: 2),
            groupId: 'group',
          ),
          cancel,
        ),
    'DELETE': (api, cancel) => api.deleteImage('token', 'image', cancel).then<Object?>((_) => null),
    'SSE POST': (api, cancel) => api.streamChat(chatRequest(), 'token', cancel).toList(),
    'document multipart': (api, cancel) => api.uploadDocument(
          'token',
          groupId: 'group',
          aiType: 'model',
          fileName: 'note.txt',
          bytes: utf8.encode('note'),
          cancellation: cancel,
        ),
    'image multipart': (api, cancel) => api.uploadVisionImage(
          'token',
          fileName: 'image.png',
          bytes: [1, 2, 3],
          cancellation: cancel,
        ),
    'audio multipart': (api, cancel) => api.recognizeAudio(
          'token',
          fileName: 'voice.wav',
          bytes: [1, 2, 3],
          cancellation: cancel,
        ),
    'audio response': (api, cancel) => api.convertTextToSpeech(
          'token',
          text: 'hello',
          cancellation: cancel,
        ),
  };
  for (final entry in requests.entries) {
    test('${entry.key} recognizes the campus block, closes once and never replays', () async {
      var closed = 0;
      final transport = ScriptedTransport(
        (_) async => response(
          status: 404,
          type: 'text/html; charset=utf-8',
          bytes: Stream.fromIterable(utf8.encode(_blockedHtml).map((byte) => [byte])),
          close: () => closed++,
        ),
      );
      await expectLater(
        entry.value(GenAiApiClient(transport: transport), GenAiCancellation()),
        throwsA(_campusFailure),
      );
      expect(transport.requests, hasLength(1));
      expect(closed, 1);
    });
  }

  test('only 404 HTML with the exact notice identifies the campus restriction', () async {
    for (final (status, type, body, kind) in [
      (404, 'text/html', '<html>Not found</html>', GenAiFailureKind.rejected),
      (404, 'text/html', '<html>仅支持校内访问</html>', GenAiFailureKind.rejected),
      (404, 'text/html', '<script>"该服务暂不开放外网访问，仅支持校内访问"</script>', GenAiFailureKind.rejected),
      (404, 'text/html', '<!--该服务暂不开放外网访问，仅支持校内访问-->', GenAiFailureKind.rejected),
      (404, 'text/html', '<p title="该服务暂不开放外网访问，仅支持校内访问">404</p>', GenAiFailureKind.rejected),
      (404, 'application/json', _blockedHtml, GenAiFailureKind.rejected),
      (403, 'text/html', _blockedHtml, GenAiFailureKind.rejected),
      (401, 'text/html', _blockedHtml, GenAiFailureKind.authenticationRequired),
      (200, 'text/html', _blockedHtml, GenAiFailureKind.protocol),
    ]) {
      final transport = ScriptedTransport(
        (_) async => response(status: status, type: type, text: body),
      );
      await expectLater(
        GenAiApiClient(transport: transport).listModels('token', GenAiCancellation()),
        throwsA(
          isA<GenAiFailure>()
              .having((error) => error.kind, 'kind', kind)
              .having((error) => error.effectNotDispatched, 'not dispatched', false),
        ),
      );
    }
  });

  test('diagnostic body has a byte limit and stops listening at that limit', () async {
    var stopped = false;
    final wire = StreamController<List<int>>(onCancel: () => stopped = true);
    final pending = checkGenAiHttpStatus(
      statusCode: 404,
      contentType: 'text/html',
      bytes: wire.stream,
      cancellation: GenAiCancellation(),
      maxErrorBodyBytes: 16,
    );
    final expected = expectLater(pending, throwsA(failure(GenAiFailureKind.rejected)));
    wire.add(utf8.encode('${' ' * 16}$_blockedHtml'));
    await expected;
    expect(stopped, isTrue);
    await wire.close();
  });

  test('diagnostic body has a total deadline even while chunks keep arriving', () async {
    var stopped = false;
    final wire = StreamController<List<int>>(onCancel: () => stopped = true);
    final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => wire.add([32]));
    addTearDown(timer.cancel);
    await expectLater(
      checkGenAiHttpStatus(
        statusCode: 404,
        contentType: 'text/html',
        bytes: wire.stream,
        cancellation: GenAiCancellation(),
        errorBodyTimeout: const Duration(milliseconds: 20),
      ).timeout(const Duration(seconds: 1)),
      throwsA(failure(GenAiFailureKind.rejected)),
    );
    expect(stopped, isTrue);
    timer.cancel();
    await wire.close();
  });

  test('cancellation during error-body inspection wins and closes the response', () async {
    for (final kind in [GenAiFailureKind.cancelled, GenAiFailureKind.accountChanged]) {
      var closed = 0;
      final listening = Completer<void>();
      final wire = StreamController<List<int>>(onListen: listening.complete);
      final cancel = GenAiCancellation();
      final api = GenAiApiClient(
        transport: ScriptedTransport(
          (_) async =>
              response(status: 404, type: 'text/html', bytes: wire.stream, close: () => closed++),
        ),
      );
      final expected = expectLater(
        api.streamChat(chatRequest(), 'token', cancel).toList(),
        throwsA(failure(kind)),
      );
      await listening.future;
      cancel.cancel(kind);
      await expected;
      expect(closed, 1);
      await wire.close();
    }
  });

  test('campus guidance is actionable without exposing response content', () {
    const error = GenAiFailure(GenAiFailureKind.campusNetworkRequired, statusCode: 404);
    expect(genAiFailureText(error), contains('校园网或学校 VPN'));
    expect(genAiFailureText(error), isNot(contains('登录已过期')));
    expect(error.toString(), isNot(contains(_blockedHtml)));
  });
}
