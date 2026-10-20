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
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';

void main() {
  test(
      'explicit IDS connection surfaces reauthentication instead of failing silently',
      () async {
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
    transport = ScriptedTransport(
      (r) async => r.uri.path.endsWith('/list')
          ? models()
          : r.method == 'POST'
              ? response(
                  type: 'text/event-stream',
                  text: sseChunk(text: 'answer', finish: 'stop'),
                )
              : profileResponse(),
    );
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

  test(
      'refresh preserves an explicitly selected model when it is still available',
      () async {
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

  test(
      'multi-turn chat preserves group id and sends only completed prior turns',
      () async {
    await workspace.send('first');
    await workspace.send('second');
    final posts = transport.requests.where((r) => r.method == 'POST').toList();
    final first = jsonDecode(posts.first.body!) as Map<String, dynamic>;
    final second = jsonDecode(posts.last.body!) as Map<String, dynamic>;
    expect(first['chatGroupId'], second['chatGroupId']);
    expect(second['chatInfo'], 'second');
    expect(second['messages'], [
      {'role': 'user', 'content': 'first'},
      {'role': 'assistant', 'content': 'answer'},
    ]);
    expect(
      workspace.turns.map((t) => t.phase),
      everyElement(GenAiChatPhase.completed),
    );
  });

  test(
      'an interrupted response stays visible but is excluded from future context',
      () async {
    final original = transport.handle;
    transport.handle = (r) async => r.method == 'POST'
        ? response(type: 'text/event-stream', text: sseChunk(text: 'partial'))
        : original(r);
    await workspace.send('interrupted');
    expect(workspace.turns.single.answer, 'partial');
    expect(workspace.turns.single.phase, GenAiChatPhase.interrupted);
    transport.handle = original;
    await workspace.send('next');
    expect(jsonDecode(transport.requests.last.body!)['messages'], isEmpty);
  });

  test(
      'stop permits a new request without overwriting its state with old callbacks',
      () async {
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

  test('new conversation clears local history and rotates the server group id',
      () async {
    await workspace.send('old conversation');
    final before = jsonDecode(transport.requests.last.body!)['chatGroupId'];
    workspace.newConversation();
    expect(workspace.turns, isEmpty);
    await workspace.send('new conversation');
    expect(
      jsonDecode(transport.requests.last.body!)['chatGroupId'],
      isNot(before),
    );
    expect(jsonDecode(transport.requests.last.body!)['messages'], isEmpty);
  });

  test('switching accounts removes messages and model selection', () async {
    await workspace.send('private message');
    await sessions.setOwner(ownerB);
    expect(workspace.turns, isEmpty);
    expect(workspace.models, isEmpty);
    expect(workspace.selectedModel, isNull);
  });

  test('paid-only catalog requires explicit selection before a request can run',
      () async {
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

  test(
      'attaching image and sending populates turn bytes and sends imageUrl and imageUrls',
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

  test('send awaits in-flight image upload and does not drop attachment',
      () async {
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
    final json =
        jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(json['imageUrl'], contains('temp/pending.png'));
    expect(json['imageUrls'], isNotEmpty);
  });

  test(
      'send rejects sending when an attachment upload failed and retry recovers',
      () async {
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

  test('retryTurn and retryLastTurn regenerate response and truncate history',
      () async {
    await workspace.send('turn 1');
    await workspace.send('turn 2');
    await workspace.send('turn 3');
    expect(workspace.turns.length, 3);

    // Retrying turn 1 (index 1) should truncate turn 2 and turn 3, and resend turn 2
    await workspace.retryTurn(1);
    expect(workspace.turns.length, 2);
    expect(workspace.turns[0].prompt, 'turn 1');
    expect(workspace.turns[1].prompt, 'turn 2');
    final lastReq =
        jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(lastReq['chatInfo'], 'turn 2');
    expect(lastReq['messages'], [
      {'role': 'user', 'content': 'turn 1'},
      {'role': 'assistant', 'content': 'answer'},
    ]);

    // Retrying last turn resends turn 2
    await workspace.retryLastTurn();
    expect(workspace.turns.length, 2);
    expect(workspace.turns[1].prompt, 'turn 2');
  });

  test('editAndResend updates user prompt and resends truncated conversation',
      () async {
    await workspace.send('original prompt 1');
    await workspace.send('original prompt 2');
    expect(workspace.turns.length, 2);

    await workspace.editAndResend(1, 'edited prompt 2');
    expect(workspace.turns.length, 2);
    expect(workspace.turns[0].prompt, 'original prompt 1');
    expect(workspace.turns[1].prompt, 'edited prompt 2');

    final lastReq =
        jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(lastReq['chatInfo'], 'edited prompt 2');
    expect(lastReq['messages'], [
      {'role': 'user', 'content': 'original prompt 1'},
      {'role': 'assistant', 'content': 'answer'},
    ]);
  });

  test('deleteTurn and revertLastTurn remove messages from active conversation',
      () async {
    await workspace.send('message 1');
    await workspace.send('message 2');
    await workspace.send('message 3');
    expect(workspace.turns.length, 3);

    // Delete message at index 1
    workspace.deleteTurn(1);
    expect(workspace.turns.length, 2);
    expect(workspace.turns[0].prompt, 'message 1');
    expect(workspace.turns[1].prompt, 'message 3');

    // Revert last turn removes message 3
    workspace.revertLastTurn();
    expect(workspace.turns.length, 1);
    expect(workspace.turns[0].prompt, 'message 1');

    // Revert last turn on remaining turn removes it and resets groupId for a new conversation
    final initialGroupId = workspace.groupId;
    workspace.revertLastTurn();
    expect(workspace.turns, isEmpty);
    expect(workspace.groupId, isNot(equals(initialGroupId)));

    // Sending another message now targets the new conversation group
    await workspace.send('new fresh topic');
    expect(workspace.turns.length, 1);
    expect(workspace.turns.first.prompt, 'new fresh topic');
    final req =
        jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(req['chatGroupId'], equals(workspace.groupId));
    expect(req['chatGroupId'], isNot(equals(initialGroupId)));
    expect(req['messages'], isEmpty);
  });

  test(
      'reverting only message after loading conversation from history creates new conversation on next send',
      () async {
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path == '/htk/ai/history/getByChatGroupId') {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': [
              {
                'chatGroupId': 'historical-group-123',
                'question': 'only message in history',
                'answer': 'historical answer',
                'aiType': 'free',
              },
            ],
          },
        );
      }
      return original(r);
    };

    await workspace.openConversation(
      'historical-group-123',
      GenAiCancellation(),
    );
    expect(workspace.groupId, 'historical-group-123');
    expect(workspace.turns.length, 1);

    // Revert the only message
    workspace.revertLastTurn();
    expect(workspace.turns, isEmpty);
    expect(workspace.groupId, isNot(equals('historical-group-123')));

    // Sending another message creates a new conversation
    await workspace.send('brand new question');
    expect(workspace.turns.length, 1);
    final req =
        jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(req['chatGroupId'], isNot(equals('historical-group-123')));
    expect(req['chatGroupId'], equals(workspace.groupId));
    expect(req['messages'], isEmpty);
  });
}
