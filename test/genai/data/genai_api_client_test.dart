import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/data/genai_sse_decoder.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

import '../support/fakes.dart';

void main() {
  test(
    'vision is transient multimodal context with canonical recovery and active selection',
    () async {
      const oldImage = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/old.png';
      const currentImage = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/current.png';
      var closed = 0;
      final transport = ScriptedTransport(
        (request) async => request.method == 'GET'
            ? response(type: 'image/png', bytes: Stream.value([1, 2, 3]), close: () => closed++)
            : response(
                type: 'text/event-stream',
                text: sseChunk(text: 'seen', finish: 'stop'),
              ),
      );
      final api = GenAiApiClient(transport: transport);
      final request = GenAiChatRequest(
        chatGroupId: 'vision',
        prompt: 'Inspect current',
        aiType: 'Kimi-k3',
        rootAiType: 'xinference',
        history: const [
          GenAiMessage(role: GenAiRole.user, content: 'Earlier', imageUrls: [oldImage]),
        ],
        imageUrl: currentImage,
        imageUrls: const [currentImage, currentImage],
        requestGuide: 'Final tool guide',
        record: const {
          'step_id': 'step',
          'turn': {
            'id': 'turn',
            'images': [currentImage],
          },
        },
      );
      final original = jsonEncode(request.toJson());
      await api.streamChat(request, 'secret', GenAiCancellation()).toList();
      expect(transport.requests.map((r) => r.method), ['GET', 'POST']);
      expect(transport.requests.first.uri.toString(), currentImage);
      expect(transport.requests.first.headers, {
        'Accept': 'image/png,image/jpeg,image/webp,image/gif',
      });
      expect(closed, 1);
      final payload = jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
      expect(payload.containsKey('imageUrl'), isFalse);
      expect(payload.containsKey('imageUrls'), isFalse);
      expect(payload['chatInfo'], request.storedPrompt);
      expect(payload['chatInfo'], isNot(contains('base64')));
      final messages = payload['messages'] as List<dynamic>;
      expect(messages.first, {'role': 'user', 'content': 'Earlier'});
      expect(messages.last, {'role': 'system', 'content': 'Final tool guide'});
      expect(messages[1]['content'], [
        {'type': 'text', 'text': 'Image: $currentImage'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,AQID'},
        },
      ]);
      expect(jsonEncode(request.toJson()), original);
      // A new client can rebuild the same request from canonical URLs; no cache is required.
      await GenAiApiClient(
        transport: transport,
      ).streamChat(request, 'secret', GenAiCancellation()).toList();
      expect(transport.requests.last.body, transport.requests[1].body);
    },
  );

  test(
    'image preparation rejects unsafe, oversized and non-image content before chat dispatch',
    () async {
      GenAiChatRequest request(String url) => GenAiChatRequest(
        chatGroupId: 'vision',
        prompt: 'Inspect',
        aiType: 'Kimi-k3',
        rootAiType: 'xinference',
        imageUrl: url,
      );
      final transport = ScriptedTransport((_) async => response(type: 'text/html', text: 'denied'));
      final api = GenAiApiClient(transport: transport);
      await expectLater(
        api
            .streamChat(request('https://other.example/image.png'), 'secret', GenAiCancellation())
            .toList(),
        throwsA(failure(GenAiFailureKind.protocol)),
      );
      expect(transport.requests, isEmpty);
      const url = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/image.png';
      await expectLater(
        api.streamChat(request(url), 'secret', GenAiCancellation()).toList(),
        throwsA(failure(GenAiFailureKind.protocol)),
      );
      var closed = false;
      transport.handle = (_) async => response(
        type: 'image/png',
        bytes: Stream.fromIterable(List.filled(11, List.filled(1024 * 1024, 0))),
        close: () => closed = true,
      );
      await expectLater(
        api.streamChat(request(url), 'secret', GenAiCancellation()).toList(),
        throwsA(failure(GenAiFailureKind.messageTooLarge)),
      );
      expect(closed, isTrue);
      expect(transport.requests.every((r) => r.method == 'GET'), isTrue);
    },
  );

  test('cancelling an image download closes it without dispatching chat', () async {
    final ready = Completer<void>();
    final wire = StreamController<List<int>>();
    var closed = false;
    final transport = ScriptedTransport((_) async {
      ready.complete();
      return response(type: 'image/png', bytes: wire.stream, close: () => closed = true);
    });
    final cancellation = GenAiCancellation();
    final result = GenAiApiClient(transport: transport)
        .streamChat(
          GenAiChatRequest(
            chatGroupId: 'vision',
            prompt: 'Inspect',
            aiType: 'Kimi-k3',
            rootAiType: 'xinference',
            imageUrl: 'https://genaipic.shanghaitech.edu.cn/sys/common/static/image.png',
          ),
          'secret',
          cancellation,
        )
        .toList();
    final assertion = expectLater(result, throwsA(failure(GenAiFailureKind.cancelled)));
    await ready.future;
    cancellation.cancel();
    await assertion;
    unawaited(wire.close());
    expect(closed, isTrue);
    expect(transport.requests.single.method, 'GET');
  });

  test('a save error after model stop is not a successful completion', () async {
    final wire = StreamController<List<int>>();
    final textSeen = Completer<void>();
    final transport = ScriptedTransport(
      (_) async => response(type: 'text/event-stream', bytes: wire.stream),
    );
    final events = <GenAiChatEvent>[];
    final result = GenAiApiClient(transport: transport)
        .streamChat(chatRequest(), 'token', GenAiCancellation())
        .map((event) {
          events.add(event);
          if (event is GenAiTextDelta) textSeen.complete();
          return event;
        })
        .toList();
    final assertion = expectLater(result, throwsA(failure(GenAiFailureKind.rejected)));
    wire.add(utf8.encode(sseChunk(text: 'visible answer', finish: 'stop')));
    await textSeen.future;
    expect(events.whereType<GenAiChatFinished>(), isEmpty);
    wire.add(utf8.encode('data: {"code":500,"errMsg":"save failed"}\n\n'));
    await assertion;
    await wire.close();
    expect(events.whereType<GenAiChatFinished>(), isEmpty);
  });

  test('vision upload expires authentication on HTTP 401 and closes response', () async {
    var closed = false;
    final api = GenAiApiClient(
      transport: ScriptedTransport((_) async => response(status: 401, close: () => closed = true)),
      signer: const GenAiRequestSigner('fixture'),
    );
    await expectLater(
      api.uploadVisionImage(
        'token',
        fileName: 'test.png',
        bytes: [1],
        cancellation: GenAiCancellation(),
      ),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(closed, isTrue);
  });

  test('chat serializes prior history separately and disables unverified search', () {
    final history = [const GenAiMessage(role: GenAiRole.user, content: 'earlier')];
    final request = GenAiChatRequest(
      chatGroupId: 'chat',
      prompt: 'current',
      aiType: 'model',
      rootAiType: 'provider',
      history: history,
      maxTokens: 99,
    );
    history.clear();
    expect(request.toJson(), {
      'chatInfo': 'current',
      'messages': [
        {'role': 'user', 'content': 'earlier'},
      ],
      'chatGroupId': 'chat',
      'aiType': 'model',
      'rootAiType': 'provider',
      'type': '3',
      'stream': true,
      'thinking': false,
      'netGo': false,
      'maxToken': 99,
    });
    expect(() => request.history.clear(), throwsUnsupportedError);
  });

  test('envelope distinguishes business auth, rejection and invalid shape', () {
    expect(genAiEnvelope({'success': true, 'code': 0, 'result': 42}), 42);
    expect(
      () => genAiEnvelope({'success': false, 'code': 401}),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(
      () => genAiEnvelope({'success': false, 'code': 500, 'message': 'secret'}),
      throwsA(failure(GenAiFailureKind.rejected)),
    );
    expect(
      () => genAiEnvelope({'success': true, 'code': '200'}),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
  });

  test('SSE handles every byte boundary, CRLF, BOM, comments and multiline data', () async {
    final bytes = utf8.encode(
      '\ufeff: heartbeat\r\nevent: message\r\ndata: 你好\r\ndata: 世界\r\n\r\n',
    );
    final events = await const GenAiSseDecoder()
        .decode(Stream.fromIterable(bytes.map((b) => [b])))
        .toList();
    expect(events.single.data, '你好\n世界');
    expect(events.single.type, 'message');
  });

  test('SSE discards unterminated data and bounds individual lines and events', () async {
    expect(
      await const GenAiSseDecoder().decode(Stream.value(utf8.encode('data: [DONE]'))).toList(),
      isEmpty,
    );
    await expectLater(
      const GenAiSseDecoder(
        maxEventBytes: 8,
      ).decode(Stream.value(utf8.encode('data: too long\n\n'))).toList(),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
    await expectLater(
      const GenAiSseDecoder(
        maxEventBytes: 20,
      ).decode(Stream.value(utf8.encode('data: 123\ndata: 456\ndata: 789\n\n'))).toList(),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
    await expectLater(
      const GenAiSseDecoder().decode(Stream.value([255, 10, 10])).toList(),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
  });

  test('profile request verifies upstream identity without sending a primary token', () async {
    final transport = ScriptedTransport((_) async => profileResponse());
    final api = GenAiApiClient(
      transport: transport,
      now: () => DateTime.fromMillisecondsSinceEpoch(1234),
    );
    final profile = await api.verifyToken('synthetic.jwt', GenAiCancellation());
    expect(profile.username, ownerA.studentId);
    expect(transport.requests.single.uri.path, '/htk/user/info/synthetic.jwt');
    expect(transport.requests.single.uri.queryParameters, {'_t': '1234'});
    expect(transport.requests.single.headers['X-Access-Token'], 'synthetic.jwt');
    expect(transport.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('catalog is dynamic and rejects undocumented shapes rather than inventing models', () async {
    final transport = ScriptedTransport(
      (_) async => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              {
                'aiName': 'Synthetic',
                'aiType': 'fixture',
                'rootAiType': 'future-provider',
                'payType': 'FREE',
                'enableDeepThink': 1,
              },
            ],
          },
        },
      ),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    final models = await api.listModels('token', GenAiCancellation());
    expect(models.single.rootAiType, 'future-provider');
    expect(models.single.supportsThinking, isTrue);
    expect(
      const GenAiModel(
        name: 'Kimi-K3',
        aiType: 'kimi',
        rootAiType: 'kimi',
        payType: 'FREE',
      ).supportsThinking,
      isFalse,
    );
    expect(transport.requests.first.uri.queryParameters['showStatusList'], '2,3');
    transport.handle = (_) async =>
        response(json: {'success': true, 'code': 200, 'result': <Object?>[]});
    await expectLater(
      api.listModels('token', GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
  });

  test('POST emits reasoning and answer before response completion and closes once', () async {
    final wire = StreamController<List<int>>();
    final observed = Completer<void>();
    var closed = 0;
    final transport = ScriptedTransport(
      (_) async => response(
        type: 'text/event-stream; charset=utf-8',
        bytes: wire.stream,
        close: () => closed++,
      ),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    final events = <GenAiChatEvent>[];
    final done = api.streamChat(chatRequest(), 'token', GenAiCancellation()).forEach((event) {
      events.add(event);
      if (event is GenAiTextDelta && !observed.isCompleted) observed.complete();
    });
    final first = utf8.encode(sseChunk(reasoning: '思考') + sseChunk(text: '你好'));
    for (final byte in first) {
      wire.add([byte]);
    }
    await observed.future.timeout(const Duration(seconds: 2));
    expect(events.whereType<GenAiReasoningDelta>().single.text, '思考');
    expect(closed, 0);
    wire.add(utf8.encode('${sseChunk(finish: 'length')}data: [DONE]\n\n'));
    await done;
    await wire.close();
    expect(events.whereType<GenAiChatFinished>().single.reason, GenAiFinishReason.length);
    expect(closed, 1);
    expect(transport.requests.single.method, 'POST');
    expect(transport.requests.single.headers['Accept'], 'text/event-stream');
    expect(jsonDecode(transport.requests.single.body!)['chatInfo'], '你好');
  });

  final azureRequest = GenAiChatRequest(
    chatGroupId: 'azure-conversation',
    prompt: 'Reply OK',
    aiType: 'GPT-6.1-Sol',
    rootAiType: 'azure',
  );

  test(
    'Azure streams through moderation and DONE, completing only on the school receipt',
    () async {
      for (final encodedReceipt in [false, true]) {
        final wire = StreamController<List<int>>();
        final observed = Completer<void>();
        final events = <GenAiChatEvent>[];
        var closed = 0;
        final api = GenAiApiClient(
          transport: ScriptedTransport(
            (_) async =>
                response(type: 'text/event-stream', bytes: wire.stream, close: () => closed++),
          ),
        );
        final done = api.streamChat(azureRequest, 'token', GenAiCancellation()).forEach((event) {
          events.add(event);
          if (event is GenAiTextDelta) observed.complete();
        });
        wire.add(
          utf8.encode(
            'data: {"choices":[],"prompt_filter_results":[]}\n\n'
            'data: {"choices":[],"prompt_annotations":[],"usage":null}\n\n'
            '${sseChunk(text: 'OK')}',
          ),
        );
        await observed.future.timeout(const Duration(seconds: 2));
        expect(events.whereType<GenAiTextDelta>().single.text, 'OK');
        wire.add(
          utf8.encode(
            'data: {"choices":[{"content_filter_results":{},"delta":null}]}\n\n'
            '${sseChunk(finish: 'stop')}'
            'data: {"choices":[],"usage":{"total_tokens":10}}\n\n'
            'data: [DONE]\n\n',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<GenAiChatFinished>(), isEmpty);
        expect(closed, 0);
        final receipt = {'answerGroupId': 'saved-answer', 'totalTokens': 10};
        wire.add(
          utf8.encode(
            'data: ${jsonEncode({'other': encodedReceipt ? jsonEncode(receipt) : receipt})}\n\n',
          ),
        );
        await done;
        expect(events.whereType<GenAiChatFinished>().single.reason, GenAiFinishReason.stop);
        expect(closed, 1);
        await wire.close();
      }
    },
  );

  test(
    'Azure cannot report success on missing receipts, malformed metadata or late errors',
    () async {
      for (final (tail, kind) in [
        ('', GenAiFailureKind.interrupted),
        ('data: {"code":500,"errMsg":"save failed"}\n\n', GenAiFailureKind.rejected),
        ('data: {"code":401}\n\n', GenAiFailureKind.authenticationRequired),
        ('data: {"other":"not-json"}\n\n', GenAiFailureKind.protocol),
        ('data: {"other":{}}\n\n', GenAiFailureKind.protocol),
        ('data: {"choices":[]}\n\n', GenAiFailureKind.protocol),
        ('data: {"choices":[{"delta":null}]}\n\n', GenAiFailureKind.protocol),
      ]) {
        final events = <GenAiChatEvent>[];
        var closed = false;
        final api = GenAiApiClient(
          transport: ScriptedTransport(
            (_) async => response(
              type: 'text/event-stream',
              text: '${sseChunk(text: 'OK', finish: 'stop')}data: [DONE]\n\n$tail',
              close: () => closed = true,
            ),
          ),
        );
        await expectLater(
          api.streamChat(azureRequest, 'token', GenAiCancellation()).forEach(events.add),
          throwsA(failure(kind)),
        );
        expect(events.whereType<GenAiTextDelta>().single.text, 'OK');
        expect(events.whereType<GenAiChatFinished>(), isEmpty);
        expect(closed, isTrue);
      }
    },
  );

  test('DONE is terminal, but bare EOF and malformed data are failures', () async {
    final transport = ScriptedTransport(
      (_) async => response(type: 'text/event-stream', text: 'data: [DONE]\n\n'),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    expect(
      (await api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList()).single,
      isA<GenAiChatFinished>(),
    );
    for (final text in [sseChunk(text: 'partial'), 'data: [DONE]']) {
      transport.handle = (_) async => response(type: 'text/event-stream', text: text);
      await expectLater(
        api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList(),
        throwsA(failure(GenAiFailureKind.interrupted)),
      );
    }
    transport.handle = (_) async => response(type: 'text/event-stream', text: 'data: not-json\n\n');
    await expectLater(
      api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList(),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
  });

  test('HTTP and stream errors are sanitized; errors are never silently skipped', () async {
    final transport = ScriptedTransport(
      (_) async => response(status: 401, text: 'token/password/private text'),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    await expectLater(
      api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList(),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    transport.handle = (_) async =>
        response(json: {'success': false, 'code': 401, 'message': 'secret'});
    await expectLater(
      api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList(),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    transport.handle = (_) async =>
        response(type: 'text/event-stream', text: 'event: error\ndata: secret\n\n');
    await expectLater(
      api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList(),
      throwsA(failure(GenAiFailureKind.rejected)),
    );
    for (final (code, kind) in [
      (500, GenAiFailureKind.rejected),
      (401, GenAiFailureKind.authenticationRequired),
    ]) {
      transport.handle = (_) async => response(
        type: 'text/event-stream',
        text: 'data: {"code":$code,"errMsg":"secret gateway failure"}\n\n',
      );
      await expectLater(
        api.streamChat(chatRequest(), 'token', GenAiCancellation()).toList(),
        throwsA(failure(kind)),
      );
    }
    expect(const GenAiFailure(GenAiFailureKind.rejected).toString(), isNot(contains('secret')));
  });

  test('rejects insecure API origins, malformed tokens and oversized JSON', () async {
    final transport = ScriptedTransport((_) async => profileResponse());
    expect(
      () => GenAiApiClient(transport: transport, apiBase: Uri.parse('http://example.com/htk/')),
      throwsArgumentError,
    );
    final api = GenAiApiClient(transport: transport, maxJsonBytes: 10);
    await expectLater(
      api.verifyToken('token\r\nleak', GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(transport.requests, isEmpty);
    await expectLater(
      api.verifyToken('token', GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.protocol)),
    );
  });

  test('uploadVisionImage targets pic host with token and decodes uploaded image', () async {
    final transport = ScriptedTransport(
      (_) async => response(
        json: {
          'success': true,
          'code': 200,
          'result': {'url': 'temp/photo.png', 'width': 1024, 'height': 768},
        },
      ),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    final uploaded = await api.uploadVisionImage(
      'token',
      fileName: 'photo.png',
      bytes: [1, 2, 3],
      cancellation: GenAiCancellation(),
    );
    expect(uploaded.url, 'temp/photo.png');
    expect(uploaded.width, 1024);
    expect(uploaded.height, 768);
    final req = transport.requests.single;
    expect(req.uri.host, 'genaipic.shanghaitech.edu.cn');
    expect(req.uri.path, '/sys/common/upload');
    expect(req.headers['token'], '2ea38f293adb4abca21132feba61eaa3');
    final body = utf8.decode(req.bodyBytes!);
    expect(body, contains('name="biz"'));
    expect(body, contains('temp'));
    expect(body, contains('name="uploadType"'));
    expect(body, contains('local'));
  });

  test('convertTextToSpeech sends json and streams audio bytes', () async {
    final transport = ScriptedTransport(
      (_) async => response(type: 'audio/wav', bytes: Stream.value([10, 20, 30, 40])),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    final wavBytes = await api.convertTextToSpeech(
      'token',
      text: '你好上科大',
      cancellation: GenAiCancellation(),
    );
    expect(wavBytes, [10, 20, 30, 40]);
    final req = transport.requests.single;
    expect(req.uri.path, '/htk/chat/convert2wav');
    expect(jsonDecode(req.body!), {
      'text': '你好上科大',
      'speed': 1,
      'language': 'ZH',
      'speaker_id': 'ZH',
    });
  });

  test('recognizeAudio sends multipart audio and decodes transcription', () async {
    final transport = ScriptedTransport(
      (_) async => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'transcription': jsonEncode({
              'transcription': [
                {'text': '语音识别结果'},
              ],
            }),
          },
        },
      ),
    );
    final api = GenAiApiClient(transport: transport, signer: const GenAiRequestSigner('fixture'));
    final text = await api.recognizeAudio(
      'token',
      fileName: 'speech.wav',
      bytes: [0, 1, 2],
      cancellation: GenAiCancellation(),
    );
    expect(text, '语音识别结果');
    final req = transport.requests.single;
    expect(req.uri.path, '/htk/chat/recognize');
    expect(req.headers['Content-Type'], contains('multipart/form-data; boundary='));
  });
}
