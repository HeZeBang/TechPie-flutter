import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';

void main() {
  test('restored reasoning is kept out of assistant history content', () {
    final turn = GenAiSavedTurn.fromJson({
      'question': 'test',
      'answer': '<think>private reasoning</think>Final answer',
    });
    expect(turn.answer, 'Final answer');
    expect(turn.reasoning, 'private reasoning');
  });

  test(
      'signer matches a fixed independent vector with Unicode and numeric query data',
      () {
    final headers = const GenAiRequestSigner('synthetic-salt').headers(
      Uri.parse('https://example.test/api?pageNo=1'),
      {'question': '你好', 'count': 1, 'stream': false},
      DateTime(2026, 10, 19, 9, 8, 7),
    );
    expect(headers['X-Sign'], '0B5F0BA4D046AE5E55593B9651F2E431');
    expect(headers['X-TIMESTAMP'], '20261019090807');
  });

  test('new conversation IDs follow the official image client format', () {
    final id = GenAiWorkspaceController.createGroupId();
    expect(id, hasLength(21));
    expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{21}$')));
  });

  test('history pagination scopes requests to the verified platform user',
      () async {
    final transport = ScriptedTransport((r) async {
      expect(
        r.uri.queryParameters,
        containsPair('userId', 'verified-platform-user'),
      );
      expect(r.uri.queryParameters, containsPair('question', '测试'));
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              {'chatGroupId': 'group', 'question': '测试会话'},
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
    expect(result.records.single.id, 'group');
    expect(result.hasMore, isTrue);
  });

  test(
      'image generation is a single synchronous JSON request and checks CDN URLs',
      () async {
    final transport = ScriptedTransport((r) async {
      final body = jsonDecode(r.body!) as Map<String, dynamic>;
      expect(body['count'], '1');
      expect(body['quality'], 'low');
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
    final api = GenAiApiClient(transport: transport);
    final result = await api.generateImage(
      'token',
      GenAiImageRequest(
        prompt: 'blue pie',
        groupId: 'group',
        model: const GenAiModel(
          name: 'Image',
          aiType: 'image',
          rootAiType: 'fixture',
          status: 2,
        ),
      ),
      GenAiCancellation(),
    );
    expect(
      result.single.toString(),
      'https://genaipic.shanghaitech.edu.cn/sys/common/static/images/test.png',
    );
    expect(
      genAiImageUri('/sys/common/static/openai/20261019/test.png').toString(),
      'https://genaipic.shanghaitech.edu.cn/sys/common/static/openai/20261019/test.png',
    );
    for (final bad in [
      'https://evil.test/secret.png',
      '//evil.test/x',
      '../x',
      'file:///x',
      '',
    ]) {
      expect(
        () => genAiImageUri(bad),
        throwsA(failure(GenAiFailureKind.protocol)),
      );
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

  test(
      'signed image body matches the actual wire signature without numeric coercion by the server',
      () async {
    final transport = ScriptedTransport((r) async {
      final wire = jsonDecode(r.body!) as Map<String, dynamic>;
      expect(wire['count'], '1');
      expect(wire['imageBase64'], isNull);
      expect(wire['imageBase64List'], isNull);
      final keys = wire.keys.toList()..sort();
      final canonical = jsonEncode({for (final key in keys) key: wire[key]});
      final expected = md5
          .convert(utf8.encode('${canonical}synthetic-salt'))
          .toString()
          .toUpperCase();
      if (r.headers['X-Sign'] != expected) {
        return response(json: {'success': false, 'code': 500, 'result': null});
      }
      return response(
        json: {
          'data': [
            {'url': 'images/signed.png'},
          ],
        },
      );
    });
    final api = GenAiApiClient(
      transport: transport,
      signer: const GenAiRequestSigner('synthetic-salt'),
    );
    final image = await api.generateImage(
      'token',
      GenAiImageRequest(
        prompt: 'blue pie',
        groupId: 'group',
        model: const GenAiModel(
          name: 'Image',
          aiType: 'image',
          rootAiType: 'fixture',
          status: 2,
        ),
      ),
      GenAiCancellation(),
    );
    expect(image.single.path, endsWith('images/signed.png'));
    expect(transport.requests, hasLength(1));
  });

  test(
      'usage sends signed requests but never retains API keys from the summary',
      () async {
    final transport = ScriptedTransport((r) async {
      expect(r.headers['X-Sign'], matches(RegExp(r'^[0-9A-F]{32}$')));
      expect(r.headers['X-TIMESTAMP'], '20261019090807');
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'free': {'total': 35, 'used': 0.1, 'remain': 34.9},
            'keys': [
              {'appKey': 'must-be-discarded'},
            ],
            'projects': <Object>[],
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
    expect(summary.quotas.single.remaining, 34.9);
    expect(summary.quotas.single.name, '免费额度');
  });

  test(
      'account changes cancel a history request before accepting its late response',
      () async {
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
    final assertion =
        expectLater(result, throwsA(failure(GenAiFailureKind.accountChanged)));
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

  test(
      'saved conversations resume with the same group and separate image models',
      () async {
    final demo = await GenAiDemo.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    expect(demo.workspace.models.every((m) => !m.isImage), isTrue);
    expect(demo.workspace.imageModels.single.aiType, 'demo-image');
    await demo.workspace.send('first');
    final original = demo.workspace.groupId;
    demo.workspace.newConversation();
    final page =
        await demo.workspace.repository.listConversations(GenAiCancellation());
    expect(page.records.single.id, original);
    await demo.workspace.openConversation(original, GenAiCancellation());
    expect(demo.workspace.turns.single.prompt, 'first');
    expect(demo.workspace.groupId, original);
    await demo.workspace.send('follow up');
    expect(demo.workspace.turns, hasLength(2));
    await demo.workspace.repository
        .deleteConversation(original, GenAiCancellation());
    expect(
      (await demo.workspace.repository.listConversations(GenAiCancellation()))
          .records,
      isEmpty,
    );
  });

  test(
      'deleteConversation sends GET and deleteImage sends DELETE with query params',
      () async {
    final calls = <Map<String, dynamic>>[];
    final transport = ScriptedTransport((r) async {
      calls.add({
        'method': r.method,
        'path': r.uri.path,
        'query': r.uri.queryParameters,
        'headers': r.headers,
        'body': r.body,
      });
      return response(
        json: {
          'success': true,
          'code': 200,
          'message': '删除成功',
          'result': null,
        },
      );
    });
    final api = GenAiApiClient(transport: transport);

    await api.deleteConversation(
      'test-token',
      'group-123',
      GenAiCancellation(),
    );
    expect(calls, hasLength(1));
    expect(calls[0]['method'], 'GET');
    expect(calls[0]['path'], '/htk/ai/history/delete/groupId');
    expect(calls[0]['query']['id'], 'group-123');
    expect(calls[0]['query']['_t'], isNotEmpty);
    expect(calls[0]['headers']['X-Access-Token'], 'test-token');
    expect(calls[0]['headers']['tenant-id'], '0');
    expect(calls[0]['body'], isNull);

    await api.deleteImage(
      'test-token',
      'img-456',
      GenAiCancellation(),
    );
    expect(calls, hasLength(2));
    expect(calls[1]['method'], 'DELETE');
    expect(calls[1]['path'], '/htk/ai-image-history/delete');
    expect(calls[1]['query']['id'], 'img-456');
    expect(calls[1]['query']['_t'], isNotEmpty);
    expect(calls[1]['headers']['X-Access-Token'], 'test-token');
    expect(calls[1]['headers']['tenant-id'], '0');
    expect(calls[1]['body'], isNull);
  });

  test('GenAiImageRequest supports expanded aspect ratio and size presets', () {
    const model = GenAiModel(
      name: 'Image',
      aiType: 'GPT-Image-2',
      rootAiType: 'azure',
      status: 2,
    );
    for (final size in [
      '1024x1024',
      '1024x768',
      '768x1024',
      '1024x688',
      '1136x640',
      '2048x2048',
      '3840x2160',
    ]) {
      final req = GenAiImageRequest(
        prompt: 'test',
        groupId: 'g',
        model: model,
        size: size,
      );
      expect(req.size, size);
      expect(req.toJson()['size'], size);
      expect(req.toJson()['count'], '1');
    }

    expect(
      () => GenAiImageRequest(
        prompt: 'test',
        groupId: 'g',
        model: model,
        size: '999x999',
      ),
      throwsArgumentError,
    );
  });
}
