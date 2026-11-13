import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

void main() {
  const imageModel = GenAiModel(name: 'Image', aiType: 'image', rootAiType: 'fixture', status: 2);

  test('remote protocol titles become readable without hiding normal titles', () {
    for (final frame in ['call', 'result', 'history']) {
      expect(
        GenAiConversationSummary.fromJson({
          'chatGroupId': 'conversation',
          'question': '  <techpie-agent-$frame version="2">private tool payload',
        }).title,
        '校园工具对话',
      );
    }
    for (final title in [
      '我的课表',
      'Explain <techpie-agent-result>',
      '```xml\n<techpie-agent-result>',
      '<techpie-agent-result-example>',
    ]) {
      expect(
        GenAiConversationSummary.fromJson({'chatGroupId': 'conversation', 'question': title}).title,
        title,
      );
    }
  });

  test('malformed server rows remain explicit gaps in their original positions', () async {
    final api = GenAiApiClient(
      apiBase: Uri.parse('http://127.0.0.1:18768/htk/'),
      transport: ScriptedTransport(
        (_) async => response(
          json: {
            'success': true,
            'code': 200,
            'result': [
              {'question': 'Before', 'answer': 'First', 'imageUrl': 'temp/red.png'},
              null,
              {'question': 42, 'answer': 'Malformed'},
              {'id': 'metadata-without-message'},
              {'question': 'After', 'answer': 'Last'},
            ],
          },
        ),
      ),
    );
    final rows = await api.loadConversation('token', 'group', GenAiCancellation());
    expect(rows.map((row) => row.isHistoryGap), [false, true, true, true, false]);
    expect(rows.first.answer, 'First');
    final image = rows.first.imageUrls.single;
    expect(image, 'https://genaipic.shanghaitech.edu.cn/sys/common/static/temp/red.png');
    expect(
      api.imageDisplayUri(image).toString(),
      'http://127.0.0.1:18768/sys/common/static/temp/red.png',
    );
    expect(rows.last.answer, 'Last');
    expect(
      rows
          .where((row) => row.isHistoryGap)
          .every((row) => row.prompt.isEmpty && row.answer.isEmpty),
      isTrue,
    );
  });

  test('generated and saved images stay canonical across preview origin changes', () async {
    final transport = ScriptedTransport(
      (request) async => response(
        json: request.uri.path.endsWith('ai-image-history/list')
            ? {
                'success': true,
                'code': 200,
                'result': {
                  'records': [
                    {
                      'id': 'image',
                      'question': 'Synthetic picture',
                      'images': [
                        {'imageUrl': 'test/picture.png'},
                      ],
                    },
                  ],
                  'total': 1,
                },
              }
            : {
                'data': [
                  {'url': 'test/picture.png'},
                ],
              },
      ),
    );
    final first = GenAiApiClient(
      transport: transport,
      apiBase: Uri.parse('http://127.0.0.1:18768/htk/'),
    );
    final generated = await first.generateImage(
      'token',
      GenAiImageRequest(
        prompt: 'Synthetic picture',
        outputFormat: 'jpeg',
        outputCompression: 65,
        groupId: 'group',
        model: imageModel,
      ),
      GenAiCancellation(),
    );
    final request = jsonDecode(transport.requests.single.body!) as Map<String, dynamic>;
    expect(request.containsKey('title'), isFalse);
    expect(request['quality'], 'low');
    expect(request['outputCompression'], 65);
    final saved = await first.listImages('token', GenAiCancellation());
    const canonical = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/test/picture.png';
    expect(generated.single.toString(), canonical);
    expect(saved.records.single.images.single.toString(), canonical);
    final production = GenAiApiClient(transport: transport);
    expect(production.imageDisplayUri(canonical).toString(), canonical);
    final restarted = GenAiApiClient(
      transport: transport,
      apiBase: Uri.parse('http://127.0.0.1:28768/htk/'),
    );
    expect(
      restarted.imageDisplayUri(generated.single.toString()).toString(),
      'http://127.0.0.1:28768/sys/common/static/test/picture.png',
    );
  });

  test('image metadata survives round trips and remains optional for legacy or malformed rows', () {
    const row = {
      'id': 'image',
      'question': 'Prompt',
      'images': [
        {'imageUrl': 'test/picture.png'},
      ],
    };
    for (final metadata in <Map<String, Object?>>[
      {},
      {
        'title': 42,
        'quality': ['high'],
      },
    ]) {
      final saved = GenAiImageRecord.fromJson({...row, ...metadata}).toJson();
      expect(saved.containsKey('title'), isFalse);
      expect(saved.containsKey('quality'), isFalse);
      final restored = GenAiImageRecord.fromJson(saved);
      expect(restored.title, isNull);
      expect(restored.quality, isNull);
    }
    final current = GenAiImageRecord.fromJson({...row, 'title': '  Sunrise  ', 'quality': 'high'});
    final restored = GenAiImageRecord.fromJson(current.toJson());
    expect(restored.title, 'Sunrise');
    expect(restored.quality, 'high');
    expect(restored.id, 'image');
    expect(restored.prompt, 'Prompt');
    expect(restored.images.single, current.images.single);
  });

  test('reasoning extraction preserves literal think tags in prose and tool JSON', () {
    const examples = [
      'Example: <think>literal markup</think> remains visible.',
      '```xml\n<think>literal code</think>\n```',
      '<techpie-agent-call version="2" nonce="historicalNonce123456">\n'
          '{"call_id":"image","name":"generate_image","arguments":{"prompt":"draw <think>literal</think>"}}\n'
          '</techpie-agent-call>',
    ];
    for (final example in examples) {
      final restored = GenAiSavedTurn.fromJson({'question': 'Show tags', 'answer': example});
      expect(restored.answer, example);
      expect(restored.reasoning, isEmpty);
      final withReasoning = GenAiSavedTurn.fromJson({
        'question': 'Show tags',
        'answer': '<think>private reasoning</think>$example',
      });
      expect(withReasoning.answer, example);
      expect(withReasoning.reasoning, 'private reasoning');
    }
  });

  test('saved vision turns decode legacy and current image fields safely', () {
    const cdn = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/';
    final legacy = GenAiSavedTurn.fromJson({
      'question': 'Describe both',
      'answer': 'Two images',
      'imageUrl':
          ' temp/a.png, https://genaipic.shanghaitech.edu.cn//sys/common/static/temp/b.png, temp/a.png ',
    });
    expect(legacy.imageUrls, ['${cdn}temp/a.png', '${cdn}temp/b.png']);
    expect(() => legacy.imageUrls.add('x'), throwsUnsupportedError);
    final modern = GenAiSavedTurn.fromJson({
      'question': 'Saved question',
      'answer': 'Saved answer',
      'imageUrls': [null, 42, 'https://evil.test/a.png', 'temp/c.png', ''],
      'imageUrl': 'temp/legacy.png',
    });
    expect(modern.imageUrls, ['${cdn}temp/c.png']);
    expect(modern.answer, 'Saved answer');
    for (final value in [
      null,
      3,
      <Object?>[],
      ['https://evil.test/x'],
    ]) {
      final turn = GenAiSavedTurn.fromJson({
        'question': 'text survives',
        'imageUrls': value,
        'imageUrl': 'temp/fallback.png',
      });
      expect(turn.imageUrls, ['${cdn}temp/fallback.png']);
    }
    expect(GenAiSavedTurn.fromJson({'question': 'old text'}).imageUrls, isEmpty);
    expect(
      GenAiSavedTurn.fromJson({
        'answer': 'still readable',
        'imageUrl': 'https://evil.test/x, data:image/png;base64, file:///x',
      }).answer,
      'still readable',
    );
  });

  test('signer matches a fixed independent vector with Unicode and numeric query data', () {
    final headers = const GenAiRequestSigner('synthetic-salt').headers(
      Uri.parse('https://example.test/api?pageNo=1'),
      {'question': '你好', 'count': 1, 'stream': false},
      DateTime(2026, 10, 19, 9, 8, 7),
    );
    expect(headers['X-Sign'], '0B5F0BA4D046AE5E55593B9651F2E431');
    expect(headers['X-TIMESTAMP'], '20261019090807');
  });

  test('history pagination scopes requests to the verified user and skips corrupt rows', () async {
    final transport = ScriptedTransport((r) async {
      expect(r.uri.queryParameters, containsPair('userId', 'verified-platform-user'));
      expect(r.uri.queryParameters, containsPair('question', '测试'));
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              {'chatGroupId': 'first', 'question': '测试会话'},
              {'chatGroupId': '', 'question': 'Empty id'},
              {'question': 'Missing id'},
              {'chatGroupId': 'second', 'question': 'Another conversation'},
            ],
            'total': 21,
          },
        },
      );
    });
    final api = GenAiApiClient(transport: transport);
    final result = await api.listConversations(
      'token',
      'verified-platform-user',
      GenAiCancellation(),
      query: '测试',
    );
    expect(result.records.map((row) => row.id), ['first', 'second']);
    expect(result.hasMore, isTrue);
  });

  test('image generation signs the exact synchronous wire body and checks CDN URLs', () async {
    final transport = ScriptedTransport((r) async {
      final body = jsonDecode(r.body!) as Map<String, dynamic>;
      expect(body['count'], '1');
      expect(body['quality'], 'medium');
      expect(body['title'], 'Blue pie');
      final keys = body.keys.toList()..sort();
      final canonical = jsonEncode({for (final key in keys) key: body[key]});
      final signature = md5
          .convert(utf8.encode('${canonical}synthetic-salt'))
          .toString()
          .toUpperCase();
      expect(r.headers['X-Sign'], signature);
      expect(body['outputFormat'], 'jpeg');
      expect(body['outputCompression'], '65');
      expect(body['aiSecType'], '1');
      expect(body.containsKey('stream'), isFalse);
      expect(r.headers['Accept'], 'application/json, text/plain, */*');
      return response(
        json: {
          'success': true,
          'data': [
            {'url': 'images/test.png'},
          ],
        },
      );
    });
    final api = GenAiApiClient(
      transport: transport,
      signer: const GenAiRequestSigner('synthetic-salt'),
    );
    final result = await api.generateImage(
      'token',
      GenAiImageRequest(
        prompt: 'blue pie',
        title: '  Blue pie  ',
        quality: 'medium',
        outputFormat: 'jpeg',
        outputCompression: 65,
        groupId: 'group',
        model: imageModel,
      ),
      GenAiCancellation(),
    );
    expect(transport.requests, hasLength(1));
    expect(
      result.single.toString(),
      'https://genaipic.shanghaitech.edu.cn/sys/common/static/images/test.png',
    );
    expect(
      genAiImageUri('/sys/common/static/openai/20261019/test.png').toString(),
      'https://genaipic.shanghaitech.edu.cn/sys/common/static/openai/20261019/test.png',
    );
    for (final bad in ['https://evil.test/secret.png', '//evil.test/x', '../x', 'file:///x', '']) {
      expect(() => genAiImageUri(bad), throwsA(failure(GenAiFailureKind.protocol)));
    }
  });

  test('token expiration envelope throws authenticationRequired', () {
    expect(
      () => genAiEnvelope({
        'success': false,
        'code': 500,
        'message': 'Token失效，请重新登录',
        'result': null,
      }),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
  });

  test('signed usage responses retain valid quotas and flag unreadable rows', () async {
    final transport = ScriptedTransport((r) async {
      expect(r.headers['X-Sign'], matches(RegExp(r'^[0-9A-F]{32}$')));
      expect(r.headers['X-TIMESTAMP'], '20261019090807');
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'free': {'total': '100', 'used': '1.5', 'remain': '98.5'},
            'recharge': {'total': null},
            'keys': [
              {'appKey': 'must-be-discarded'},
            ],
            'projects': [
              null,
              {'name': 'Project', 'total': 10, 'used': 2, 'remain': 8},
            ],
          },
        },
      );
    });
    final api = GenAiApiClient(
      transport: transport,
      signer: const GenAiRequestSigner('fixture'),
      now: () => DateTime(2026, 10, 19, 9, 8, 7),
    );
    final summary = await api.usageSummary('token', GenAiCancellation());
    expect(summary.quotas.map((q) => q.remaining), [98.5, 8]);
    expect(summary.quotas.first.name, '免费额度');
    expect(summary.hasUnavailableQuotas, isTrue);
  });

  test('account changes cancel a history request before accepting its late response', () async {
    final gate = Completer<GenAiResponse>();
    final started = Completer<void>();
    final transport = ScriptedTransport((r) {
      if (r.uri.path.contains('/user/info/')) {
        return Future.value(profileResponse());
      }
      started.complete();
      return gate.future;
    });
    final api = GenAiApiClient(transport: transport);
    final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    addTearDown(sessions.dispose);
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'token'));
    final repository = GenAiRepository(api: api, sessions: sessions);
    final cancellation = GenAiCancellation();
    final result = repository.listConversations(cancellation);
    final assertion = expectLater(result, throwsA(failure(GenAiFailureKind.accountChanged)));
    await started.future;
    await sessions.setOwner(ownerB);
    await assertion;
    gate.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'records': <Object>[], 'total': 0},
        },
      ),
    );
    expect(cancellation.isCancelled, isTrue);
  });

  test('saved conversations resume with the same group and separate image models', () async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    expect(demo.workspace.models.every((m) => !m.isImage), isTrue);
    expect(demo.workspace.imageModels.single.aiType, 'test-image');
    await demo.workspace.send('first');
    final original = demo.workspace.groupId;
    demo.workspace.newConversation();
    final page = await demo.workspace.repository.listConversations(GenAiCancellation());
    expect(page.records.single.id, original);
    await demo.workspace.openConversation(original, GenAiCancellation());
    expect(demo.workspace.turns.single.prompt, 'first');
    expect(demo.workspace.groupId, original);
    await demo.workspace.send('follow up');
    expect(demo.workspace.turns, hasLength(2));
    await demo.workspace.repository.deleteConversation(original, GenAiCancellation());
    expect(
      (await demo.workspace.repository.listConversations(GenAiCancellation())).records,
      isEmpty,
    );
  });

  test('deleteConversation sends GET and deleteImage sends DELETE with query params', () async {
    final transport = ScriptedTransport(
      (_) async => response(json: {'success': true, 'code': 200}),
    );
    final api = GenAiApiClient(transport: transport);
    await api.deleteConversation('test-token', 'group-123', GenAiCancellation());
    await api.deleteImage('test-token', 'img-456', GenAiCancellation());

    expect(transport.requests.map((r) => (r.method, r.uri.path, r.uri.queryParameters['id'])), [
      ('GET', '/htk/ai/history/delete/groupId', 'group-123'),
      ('DELETE', '/htk/ai-image-history/delete', 'img-456'),
    ]);
    for (final request in transport.requests) {
      expect(request.uri.queryParameters['_t'], isNotEmpty);
      expect(request.headers['X-Access-Token'], 'test-token');
      expect(request.headers['tenant-id'], '0');
      expect(request.body, isNull);
    }
  });
}
