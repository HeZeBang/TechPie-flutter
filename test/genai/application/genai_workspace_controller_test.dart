import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';

void main() {
  test('explicit IDS connection surfaces reauthentication instead of failing silently', () async {
    final demo = await GenAiDemo.create(connected: false);
    addTearDown(demo.dispose);
    await demo.workspace.restore();
    expect(demo.workspace.loginFailure, isNull);
    await demo.workspace.restore(reportAuthenticationRequired: true);
    expect(
      demo.workspace.loginFailure?.kind,
      GenAiFailureKind.authenticationRequired,
    );
  });
  late ScriptedTransport transport;
  late GenAiSessionService sessions;
  late GenAiChatService chat;
  late GenAiWorkspaceController workspace;
  late Map<String, List<Map<String, Object?>>> saved;

  GenAiResponse models({bool paidOnly = false}) => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              if (!paidOnly)
                {
                  'aiName': 'Free',
                  'aiType': 'free',
                  'rootAiType': 'fixture',
                  'payType': 'FREE',
                },
              {
                'aiName': 'Paid',
                'aiType': 'paid',
                'rootAiType': 'fixture',
                'payType': 'PAID',
              },
            ],
          },
        },
      );

  setUp(() async {
    saved = {};
    transport = ScriptedTransport((r) async {
      if (r.uri.path.endsWith('/list')) return models();
      if (r.uri.path.endsWith('/getByChatGroupId')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': saved[r.uri.queryParameters['chatGroupId']] ?? <Object?>[],
          },
        );
      }
      if (r.method == 'POST') {
        final body = jsonDecode(r.body!) as Map<String, dynamic>;
        (saved[body['chatGroupId'] as String] ??= []).add({
          'question': body['chatInfo'],
          'answer': 'answer',
          'aiType': body['aiType'],
        });
        return response(type: 'text/event-stream', text: sseChunk(text: 'answer', finish: 'stop'));
      }
      return profileResponse();
    });
    final api = GenAiApiClient(transport: transport);
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'fixture'));
    chat = GenAiChatService(GenAiRepository(api: api, sessions: sessions));
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: GenAiRepository(api: api, sessions: sessions),
      chat: chat,
    );
    await workspace.reloadModels();
  });
  tearDown(() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
  });

  test('refresh preserves an explicitly selected model when it is still available', () async {
    final selected = workspace.models.last;
    workspace.selectModel(selected);
    await workspace.reloadModels();
    expect(workspace.selectedModel?.aiType, selected.aiType);
    expect(workspace.selectedModel?.rootAiType, selected.rootAiType);
  });

  test('loads catalog and chooses a free model without sending any prompt', () {
    expect(workspace.models.length, 2);
    expect(workspace.selectedModel?.aiType, 'free');
    expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  test('multi-turn chat preserves group id and sends only completed prior turns', () async {
    await workspace.send('first');
    await workspace.send('second');
    final posts = transport.requests.where((r) => r.method == 'POST').toList();
    final first = jsonDecode(posts.first.body!) as Map<String, dynamic>;
    final second = jsonDecode(posts.last.body!) as Map<String, dynamic>;
    expect(first['chatGroupId'], second['chatGroupId']);
    expect(decodeGenAiRemoteRecord(second['chatInfo'] as String)?['input'], 'second');
    expect((second['messages'] as List).skip(1).toList(), [
      {'role': 'user', 'content': 'first'},
      {'role': 'assistant', 'content': 'answer'},
    ]);
    expect(
      workspace.turns.map((t) => t.phase),
      everyElement(GenAiChatPhase.completed),
    );
  });

  test('older interrupted turns stay visible and cannot truncate later exchanges', () async {
    final original = transport.handle;
    transport.handle = (r) async => r.method == 'POST'
        ? response(type: 'text/event-stream', text: sseChunk(text: 'partial'))
        : original(r);
    await workspace.send('interrupted');
    expect(workspace.turns.single.answer, 'partial');
    expect(workspace.turns.single.phase, GenAiChatPhase.interrupted);
    transport.handle = original;
    await workspace.send('next');
    final messages = jsonDecode(transport.requests.last.body!)['messages'] as List;
    expect(messages, hasLength(1));
    expect((messages.single as Map)['role'], 'system');
    final requests = transport.requests.length;
    await workspace.retryTurn(0);
    expect(transport.requests, hasLength(requests));
    expect(workspace.turns.map((turn) => turn.prompt), ['interrupted', 'next']);
    final id = workspace.groupId;
    workspace.newConversation();
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.turns.map((turn) => turn.prompt), ['interrupted', 'next']);
    expect(workspace.turns.first.answer, 'partial');
  });

  test('stop permits a new request without overwriting its state with old callbacks', () async {
    final gate = Completer<GenAiResponse>();
    final started = Completer<void>();
    final original = transport.handle;
    transport.handle = (r) {
      if (r.method != 'POST') return original(r);
      started.complete();
      return r.cancellation.race(gate.future);
    };
    final old = workspace.send('old');
    await started.future;
    workspace.stop();
    transport.handle = original;
    await workspace.send('new');
    gate.complete(
      response(
        type: 'text/event-stream',
        text: sseChunk(text: 'stale', finish: 'stop'),
      ),
    );
    await old;
    expect(workspace.turns.last.prompt, 'new');
    expect(workspace.turns.last.answer, 'answer');
    expect(workspace.turns.first.phase, GenAiChatPhase.cancelled);
  });

  test('new conversation clears local history and rotates the server group id', () async {
    await workspace.send('old conversation');
    final before = jsonDecode(transport.requests.last.body!)['chatGroupId'];
    workspace.newConversation();
    expect(workspace.turns, isEmpty);
    await workspace.send('new conversation');
    expect(
      jsonDecode(transport.requests.last.body!)['chatGroupId'],
      isNot(before),
    );
    final messages = jsonDecode(transport.requests.last.body!)['messages'] as List;
    expect(messages, hasLength(1));
    expect((messages.single as Map)['role'], 'system');
  });

  test('switching accounts removes messages and model selection', () async {
    await workspace.send('private message');
    await sessions.setOwner(ownerB);
    expect(workspace.turns, isEmpty);
    expect(workspace.models, isEmpty);
    expect(workspace.selectedModel, isNull);
  });

  test('reopening an unavailable saved model cannot silently select a paid replacement', () async {
    await workspace.send('saved with the free model');
    final id = workspace.groupId;
    workspace.newConversation();
    final original = transport.handle;
    transport.handle =
        (r) async => r.uri.path.endsWith('/list') ? models(paidOnly: true) : original(r);
    await workspace.reloadModels();
    expect(workspace.selectedModel, isNull);
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    expect(workspace.turns.single.prompt, 'saved with the free model');
    expect(workspace.selectedModel, isNull);
    final requests = transport.requests.length;
    await workspace.send('requires explicit model selection');
    expect(transport.requests, hasLength(requests));
  });

  test('paid-only catalog requires explicit selection before a request can run', () async {
    transport.handle = (r) async => r.method == 'POST'
        ? response(
            type: 'text/event-stream',
            text: sseChunk(text: 'answer', finish: 'stop'),
          )
        : models(paidOnly: true);
    await workspace.reloadModels();
    expect(workspace.selectedModel, isNull);
    await workspace.send('must not run');
    expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
    workspace.selectModel(workspace.models.single);
    await workspace.send('explicit selection');
    expect(jsonDecode(transport.requests.last.body!)['aiType'], 'paid');
  });

  test('attaching image and sending populates turn bytes and sends imageUrl and imageUrls',
      () async {
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path == '/sys/common/upload') {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {'url': 'temp/test_image.png'},
          },
        );
      }
      return original(r);
    };

    final imageBytes = [137, 80, 78, 71, 13, 10, 26, 10];
    await workspace.addImageAttachment('photo.png', imageBytes);
    expect(workspace.attachments.length, 1);
    expect(
      workspace.attachments.first.imageUrl,
      contains('temp/test_image.png'),
    );
    expect(workspace.hasPendingUploads, isFalse);

    await workspace.send('请分析');
    expect(workspace.attachments, isEmpty);
    expect(workspace.turns.length, 1);
    final turn = workspace.turns.first;
    expect(turn.attachedImageBytes, equals(imageBytes));
    expect(turn.attachedImageUrl, contains('temp/test_image.png'));

    final post = transport.requests.last;
    final json = jsonDecode(post.body!) as Map<String, dynamic>;
    expect(json['imageUrl'], contains('temp/test_image.png'));
    expect(json['imageUrls'], equals([turn.attachedImageUrl]));
  });

  test('reopened vision chat carries canonical images into follow-ups and retries', () async {
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path.endsWith('/getByChatGroupId')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': [
              {
                'question': 'Describe both images',
                'answer': 'Red and blue',
                'aiType': 'free',
                'imageUrl': 'temp/red.png, temp/blue.png',
              },
              ...?saved['saved-vision'],
            ],
          },
        );
      }
      return original(r);
    };
    await workspace.openConversation('saved-vision', GenAiCancellation());
    final turn = workspace.turns.single;
    expect(turn.attachedImageBytes, isNull);
    expect(turn.attachedImageUrls, hasLength(2));
    expect(turn.attachedImageUrl, turn.attachedImageUrls.first);
    final urls = turn.attachedImageUrls;
    await workspace.send('What differs between them?');
    expect(
      jsonDecode(transport.requests.last.body!)['imageUrls'],
      urls,
    );
    await workspace.retryTurn(1);
    final payload = jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(payload['chatGroupId'], 'saved-vision');
    expect(payload['imageUrl'], urls.last);
    expect(payload['imageUrls'], urls);
    expect(
      urls.every(
        (url) => url.startsWith('https://genaipic.shanghaitech.edu.cn/'),
      ),
      isTrue,
    );
    expect(workspace.turns.first.attachedImageUrls, urls);
    workspace.newConversation();
    await workspace.send('Unrelated task');
    expect(jsonDecode(transport.requests.last.body!)['imageUrls'], isNull);
  });

  test('demo upload send and history reopen preserves multiple attachments', () async {
    final demo = await GenAiDemo.create(chunkDelay: Duration.zero);
    addTearDown(demo.dispose);
    await demo.workspace.reloadModels();
    await demo.workspace.addImageAttachment('red.png', [1, 2, 3]);
    await demo.workspace.addImageAttachment('blue.png', [4, 5, 6]);
    await demo.workspace.send('Describe these');
    final urls = demo.workspace.turns.single.attachedImageUrls;
    final id = demo.workspace.groupId;
    demo.workspace.newConversation();
    await demo.workspace.openConversation(id, GenAiCancellation());
    expect(demo.workspace.turns.single.attachedImageUrls, urls);
    expect(demo.workspace.turns.single.attachedImageBytesList, isEmpty);
  });

  test('send awaits in-flight image upload and does not drop attachment', () async {
    final uploadCompleter = Completer<GenAiResponse>();
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path == '/sys/common/upload') {
        return uploadCompleter.future;
      }
      return original(r);
    };

    final imageBytes = [1, 2, 3, 4];
    unawaited(workspace.addImageAttachment('pending.png', imageBytes));
    await Future<void>.delayed(Duration.zero);
    expect(workspace.hasPendingUploads, isTrue);

    final sendFuture = workspace.send('分析此图');

    uploadCompleter.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'url': 'temp/pending.png'},
        },
      ),
    );
    await sendFuture;

    expect(workspace.turns.length, 1);
    final turn = workspace.turns.first;
    expect(turn.attachedImageBytes, equals(imageBytes));
    expect(turn.attachedImageUrl, contains('temp/pending.png'));
    final json = jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(json['imageUrl'], contains('temp/pending.png'));
    expect(json['imageUrls'], isNotEmpty);
  });

  test('send rejects sending when an attachment upload failed and retry recovers', () async {
    var failUpload = true;
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path == '/sys/common/upload') {
        if (failUpload) {
          return response(
            status: 500,
            json: {'success': false, 'code': 500, 'message': 'Upload error'},
          );
        }
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {'url': 'temp/recovered.png'},
          },
        );
      }
      return original(r);
    };

    final imageBytes = [10, 20, 30, 40];
    await workspace.addImageAttachment('failed.png', imageBytes);
    expect(workspace.attachments.length, 1);
    expect(workspace.attachments.first.error, isNotNull);
    expect(workspace.attachments.first.imageUrl, isNull);
    expect(workspace.hasFailedUploads, isTrue);

    // Attempting to send while an upload has failed must be rejected
    await workspace.send('图片上传虽然网络失败但本地图片必须保留');
    expect(workspace.turns, isEmpty);
    expect(workspace.attachments.length, 1);
    expect(workspace.hasFailedUploads, isTrue);

    // Retrying with recovering backend resolves the error and allows sending
    failUpload = false;
    await workspace.retryAttachment(workspace.attachments.first.id);
    expect(workspace.hasFailedUploads, isFalse);
    expect(
      workspace.attachments.first.imageUrl,
      contains('temp/recovered.png'),
    );

    await workspace.send('重试成功后可以正常发送');
    expect(workspace.attachments, isEmpty);
    expect(workspace.turns.length, 1);
    final turn = workspace.turns.first;
    expect(turn.attachedImageBytes, equals(imageBytes));
    expect(turn.attachedImageUrl, contains('temp/recovered.png'));
  });

  test('retryTurn retries turn and resends conversation context', () async {
    await workspace.send('turn 1');
    await workspace.send('turn 2');
    expect(workspace.turns.length, 2);

    await workspace.retryTurn(1);
    expect(workspace.turns.length, 2);
    expect(workspace.turns[0].prompt, 'turn 1');
    expect(workspace.turns[1].prompt, 'turn 2');
    final lastReq = jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(decodeGenAiRemoteRecord(lastReq['chatInfo'] as String)?['input'], 'turn 2');
    expect((lastReq['messages'] as List).skip(1).toList(), [
      {'role': 'user', 'content': 'turn 1'},
      {'role': 'assistant', 'content': 'answer'},
    ]);
  });
}
