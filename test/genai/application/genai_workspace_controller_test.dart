import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';
import '../support/journal_server.dart';
import '../support/workspace_server.dart';

void main() {
  test('explicit IDS connection surfaces reauthentication instead of failing silently', () async {
    final demo = await TestGenAiWorkspace.create(connected: false);
    addTearDown(demo.dispose);
    await demo.workspace.restore();
    expect(demo.workspace.loginFailure, isNull);
    await demo.workspace.restore(reportAuthenticationRequired: true);
    expect(demo.workspace.loginFailure?.kind, GenAiFailureKind.authenticationRequired);
  });
  late ScriptedTransport transport;
  late GenAiSessionService sessions;
  late GenAiWorkspaceController workspace;
  late Map<String, List<Map<String, Object?>>> saved;

  GenAiResponse models({bool paidOnly = false}) => response(
    json: {
      'success': true,
      'code': 200,
      'result': {
        'records': [
          if (!paidOnly)
            {'aiName': 'Free', 'aiType': 'free', 'rootAiType': 'fixture', 'payType': 'FREE'},
          {'aiName': 'Paid', 'aiType': 'paid', 'rootAiType': 'fixture', 'payType': 'PAID'},
        ],
      },
    },
  );

  setUp(() async {
    final server = JournalServer()..onGenerate = (_) => 'answer';
    saved = server.rows;
    transport = server.transport;
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path.endsWith('/list') || r.uri.path.endsWith('/list/V2')) return models();
      return original(r);
    };
    final client = await JournalClient.create(server);
    sessions = client.sessions;
    workspace = client.workspace;
    addTearDown(client.dispose);
  });

  test('sync adopts the server completion instead of replaying a local interruption', () async {
    await workspace.send('Saved server answer');
    final interrupted = workspace.turns.single;
    interrupted.phase = GenAiChatPhase.interrupted;
    interrupted.answer = 'partial';
    await workspace.retrySaveConversations();
    expect(workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(workspace.turns.single.answer, 'answer');
    await workspace.send('Follow-up');
    final body = jsonDecode(transport.requests.lastWhere((r) => r.method == 'POST').body!) as Map;
    final record = decodeGenAiRemoteRecord(body['chatInfo'] as String)!;
    expect(record['interrupted'], isNull);
    expect(jsonEncode(body['messages']), contains('answer'));
  });

  test(
    'image-heavy plain chat uses bounded vision without deleting archived attachments',
    () async {
      await workspace.send('Image archive');
      final group = workspace.groupId;
      final row = saved[group]!.single;
      final record = decodeGenAiRemoteRecord(row['question'] as String)!;
      final turn = Map<String, Object?>.from(record['turn'] as Map);
      turn['images'] = List.generate(
        65,
        (i) => 'https://genaipic.shanghaitech.edu.cn/sys/common/static/$i.png',
      );
      record['turn'] = turn;
      row['question'] = encodeGenAiRemoteRecord(record);
      await workspace.openConversation(group, GenAiCancellation());
      await workspace.send('Describe the latest');
      expect(workspace.turns.last.phase, GenAiChatPhase.completed);
      expect(workspace.turns.first.attachedImageUrls, hasLength(65));
      final body = jsonDecode(transport.requests.lastWhere((r) => r.method == 'POST').body!);
      final vision = (body['messages'] as List)
          .expand((m) => m['content'] is List ? m['content'] as List : const [])
          .where((p) => p['type'] == 'image_url');
      expect(vision, hasLength(8));
      await workspace.openConversation(group, GenAiCancellation());
      expect(workspace.turns.first.attachedImageUrls, hasLength(65));
    },
  );

  test(
    'edit deletes the suffix, preserves attachments, and survives server-only reopening',
    () async {
      await workspace.send('keep');
      await workspace.send('replace');
      await workspace.send('discard');
      final group = workspace.groupId;
      final target = workspace.turns[1].id;
      // Simulate attachments saved with the original turn (no re-upload on edit).
      final row = saved[group]![1];
      final record = decodeGenAiRemoteRecord(row['question']! as String)!;
      final source = Map<String, Object?>.from(record['turn']! as Map);
      source['files'] = [
        {'id': 'file-1', 'name': 'notes.txt', 'content': 'source facts'},
      ];
      source['images'] = ['https://genaipic.shanghaitech.edu.cn/sys/common/static/test.png'];
      record['turn'] = source;
      row['question'] = encodeGenAiRemoteRecord(record);
      await workspace.openConversation(group, GenAiCancellation());
      await workspace.changeTurn(target, replacement: 'corrected');
      expect(workspace.turns.map((t) => t.prompt), ['keep', 'corrected']);
      final edited = workspace.turns.last;
      expect(edited.attachedFileContents, {'file-1': 'source facts'});
      expect(edited.attachedImageUrls, hasLength(1));
      final request = jsonDecode(transport.requests.lastWhere((r) => r.method == 'POST').body!);
      expect(jsonEncode(request['messages']), isNot(contains('discard')));
      expect(request['fileIds'], contains('file-1'));
      workspace.newConversation();
      await workspace.openConversation(group, GenAiCancellation());
      expect(workspace.turns.map((t) => t.prompt), ['keep', 'corrected']);
      expect(workspace.turns.last.attachedFileContents, {'file-1': 'source facts'});
      await workspace.changeTurn(workspace.turns.first.id, keepTurn: true);
      expect(workspace.turns.single.prompt, 'keep');
      await workspace.changeTurn(workspace.turns.single.id);
      expect(workspace.turns, isEmpty);
      expect(saved[group], isEmpty);
      await workspace.send('fresh');
      expect(workspace.groupId, group);
      expect(workspace.turns.single.prompt, 'fresh');
    },
  );

  test(
    'stopped streaming edit accepts late output but rejects changed requests and prior turns',
    () async {
      await workspace.send('keep');
      final group = workspace.groupId;
      final original = transport.handle;
      final stream = StreamController<List<int>>();
      final partial = Completer<void>();
      late Map<String, dynamic> request;
      workspace.addListener(() {
        if (!partial.isCompleted && workspace.turns.last.answer == 'partial') partial.complete();
      });
      transport.handle = (r) async {
        if (r.method != 'POST') return original(r);
        request = jsonDecode(r.body!) as Map<String, dynamic>;
        stream.add(utf8.encode(sseChunk(text: 'partial')));
        return response(type: 'text/event-stream', bytes: stream.stream);
      };
      final sending = workspace.send('replace stopped answer');
      await partial.future;
      workspace.stop();
      await stream.close();
      await sending;
      transport.handle = original;
      final target = workspace.turns.last.id;
      expect(workspace.turns.last.phase, GenAiChatPhase.cancelled);

      // Cancellation may return before the school commits its row.
      await workspace.retrySaveConversations();
      expect(workspace.archiveFailure?.kind, GenAiFailureKind.historyChanged);
      saved[group]!.add({
        'id': 'late-record',
        'question': request['chatInfo'],
        'answer': 'partial and completed on server',
        'aiType': request['aiType'],
      });
      await workspace.retrySaveConversations();
      expect(workspace.archiveFailure, isNull);
      expect(workspace.turns.last.answer, 'partial and completed on server');

      // Changes outside the stopped output are still real edit conflicts.
      saved[group]!.first['answer'] = 'changed prior answer';
      await expectLater(
        workspace.changeTurn(target, replacement: 'corrected'),
        throwsA(failure(GenAiFailureKind.historyChanged)),
      );
      saved[group]!.first['answer'] = 'answer';
      final question = saved[group]!.last['question'];
      final changed = decodeGenAiRemoteRecord(question! as String)!;
      changed['input'] = 'changed by another device';
      saved[group]!.last['question'] = encodeGenAiRemoteRecord(changed);
      await expectLater(
        workspace.changeTurn(target, replacement: 'corrected'),
        throwsA(failure(GenAiFailureKind.historyChanged)),
      );
      saved[group]!.last['question'] = question;
      expect(transport.requests.where((r) => r.uri.path.endsWith('/delete/batch')), isEmpty);
      // The server completes AFTER sync: no repeated check-sync loop is needed.
      saved[group]!.last['answer'] = 'partial and even later server completion';
      await workspace.changeTurn(target, replacement: 'corrected');
      expect(workspace.turns.map((t) => t.prompt), ['keep', 'corrected']);
      expect(workspace.turns.last.answer, 'answer');
      workspace.newConversation();
      await workspace.openConversation(group, GenAiCancellation());
      expect(workspace.turns.map((t) => t.prompt), ['keep', 'corrected']);
      expect(workspace.turns.last.phase, GenAiChatPhase.completed);
    },
  );

  for (final checkSync in [true, false]) {
    test('uncertain deletion recovers through ${checkSync ? 'check sync' : 'reopening'}', () async {
      await workspace.send('keep');
      await workspace.send('remove');
      final group = workspace.groupId;
      final original = transport.handle;
      transport.handle = (r) async {
        if (r.uri.path.endsWith('/delete/batch')) {
          await original(r); // The server committed, but the response was lost.
          throw const GenAiFailure(GenAiFailureKind.transport);
        }
        return original(r);
      };
      await expectLater(
        workspace.changeTurn(workspace.turns.last.id, replacement: 'edit'),
        throwsA(failure(GenAiFailureKind.transport)),
      );
      final posts = transport.requests.where((r) => r.method == 'POST').length;
      await workspace.send('must wait');
      expect(transport.requests.where((r) => r.method == 'POST'), hasLength(posts));
      expect(workspace.archiveFailure?.kind, GenAiFailureKind.historyChanged);

      // A failed recovery must not clear the safety gate or discard local turns.
      transport.handle = (r) async {
        if (r.uri.path.endsWith('/getByChatGroupId')) {
          throw const GenAiFailure(GenAiFailureKind.transport);
        }
        return original(r);
      };
      await workspace.retrySaveConversations();
      expect(workspace.turns.map((t) => t.prompt), ['keep', 'remove']);
      expect(workspace.archiveFailure, isNotNull);
      await workspace.send('still must wait');
      expect(transport.requests.where((r) => r.method == 'POST'), hasLength(posts));

      transport.handle = original;
      if (checkSync) {
        await workspace.retrySaveConversations();
      } else {
        expect(await workspace.openConversation(group, GenAiCancellation()), isTrue);
      }
      expect(workspace.groupId, group);
      expect(workspace.archiveFailure, isNull);
      expect(workspace.turns.single.prompt, 'keep');
      expect(transport.requests.where((r) => r.uri.path.endsWith('/delete/batch')), hasLength(1));
      expect(transport.requests.where((r) => r.method == 'POST'), hasLength(posts));
      await workspace.send('continue');
      expect(workspace.turns.map((t) => t.prompt), ['keep', 'continue']);
      final request = jsonDecode(transport.requests.lastWhere((r) => r.method == 'POST').body!);
      expect(jsonEncode(request['messages']), isNot(contains('remove')));
    });
  }

  test(
    'concurrent server changes and account switching cannot delete or resend stale turns',
    () async {
      await workspace.send('first');
      await workspace.send('second');
      final group = workspace.groupId;
      saved[group]!.last['answer'] = 'changed elsewhere';
      await expectLater(
        workspace.changeTurn(workspace.turns.last.id),
        throwsA(failure(GenAiFailureKind.historyChanged)),
      );
      expect(transport.requests.where((r) => r.uri.path.endsWith('/delete/batch')), isEmpty);
      await workspace.openConversation(group, GenAiCancellation());
      final original = transport.handle;
      final gate = Completer<void>();
      final started = Completer<void>();
      transport.handle = (r) async {
        if (r.uri.path.endsWith('/delete/batch')) {
          started.complete();
          await gate.future;
        }
        return original(r);
      };
      final editing = workspace.changeTurn(workspace.turns.last.id, replacement: 'do not send');
      final failed = expectLater(editing, throwsA(isA<GenAiFailure>()));
      await started.future;
      final posts = transport.requests.where((r) => r.method == 'POST').length;
      await sessions.setOwner(ownerB);
      gate.complete();
      await failed;
      expect(workspace.turns, isEmpty);
      expect(transport.requests.where((r) => r.method == 'POST'), hasLength(posts));
    },
  );

  test('history restores catalog routing without restoring thinking preference', () async {
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path.endsWith('/list') || r.uri.path.endsWith('/list/V2')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'records': [
                {
                  'aiName': 'Free',
                  'aiType': 'free',
                  'rootAiType': 'current-router',
                  'payType': 'FREE',
                  'enableDeepThink': 1,
                },
              ],
            },
          },
        );
      }
      return original(r);
    };
    await workspace.reloadModels();
    workspace.setThinking(true);
    await workspace.send('remember');
    final group = workspace.groupId;
    final body = jsonDecode(transport.requests.lastWhere((r) => r.method == 'POST').body!);
    expect(body['thinking'], true);
    expect(body['rootAiType'], 'current-router');
    final record = decodeGenAiRemoteRecord(body['chatInfo'] as String)!;
    expect(record.containsKey('thinking'), false);
    expect(record.containsKey('rootAiType'), false);
    // A legacy stored toggle must not override the user's current preference.
    record['thinking'] = true;
    saved[group]!.single['question'] =
        '<techpie-record version="2">\n${jsonEncode(record)}\n</techpie-record>';
    workspace.setThinking(false);
    await workspace.openConversation(group, GenAiCancellation());
    expect(workspace.thinkingEnabled, false);
    expect(workspace.selectedModel?.rootAiType, 'current-router');
    workspace.setThinking(true);
    await workspace.openConversation(group, GenAiCancellation());
    expect(workspace.thinkingEnabled, true);
  });

  test(
    'initial catalog chooses a free model and refresh preserves an explicit selection',
    () async {
      expect(workspace.selectedModel?.aiType, 'free');
      expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
      final paid = workspace.models.singleWhere((model) => model.aiType == 'paid');
      workspace.selectModel(paid);
      await workspace.reloadModels();
      expect(workspace.selectedModel?.aiType, paid.aiType);
      expect(workspace.selectedModel?.rootAiType, paid.rootAiType);
    },
  );

  test('follow-up and retry send completed prior turns in the same group', () async {
    await workspace.send('first');
    final group = workspace.groupId;
    await workspace.send('second');
    await workspace.retryTurn(1);
    final posts = transport.requests.where((r) => r.method == 'POST').toList();
    expect(posts, hasLength(3));
    for (final post in posts.skip(1)) {
      final body = jsonDecode(post.body!) as Map;
      expect(body['chatGroupId'], group);
      expect(decodeGenAiRemoteRecord(body['chatInfo'] as String)?['input'], 'second');
      expect((body['messages'] as List).skip(1), [
        {'role': 'user', 'content': 'first'},
        {'role': 'assistant', 'content': 'answer'},
      ]);
    }
    expect(workspace.turns.map((turn) => turn.prompt), ['first', 'second']);
    expect(workspace.turns.map((turn) => turn.phase), everyElement(GenAiChatPhase.completed));
  });

  test('older interrupted turns stay visible and cannot truncate later exchanges', () async {
    final original = transport.handle;
    transport.handle = (r) async => r.method == 'POST'
        ? response(
            type: 'text/event-stream',
            text: sseChunk(text: 'partial'),
          )
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
    expect(jsonDecode(transport.requests.last.body!)['chatGroupId'], isNot(before));
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
    transport.handle = (r) async =>
        (r.uri.path.endsWith('/list') || r.uri.path.endsWith('/list/V2'))
        ? models(paidOnly: true)
        : original(r);
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
    expect(turn.attachedImageBytesList.firstOrNull, isNull);
    expect(turn.attachedImageUrls, hasLength(2));
    final urls = turn.attachedImageUrls;
    await workspace.send('What differs between them?');
    expect(
      visionImageLabels(jsonDecode(transport.requests.last.body!) as Map<String, dynamic>),
      urls,
    );
    await workspace.retryTurn(1);
    final payload = jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(payload['chatGroupId'], 'saved-vision');
    expect(visionImageLabels(payload), urls);
    expect(payload['imageUrl'], isNull);
    expect(urls.every((url) => url.startsWith('https://genaipic.shanghaitech.edu.cn/')), isTrue);
    expect(workspace.turns.first.attachedImageUrls, urls);
    workspace.newConversation();
    await workspace.send('Unrelated task');
    expect(jsonDecode(transport.requests.last.body!)['imageUrls'], isNull);
  });

  test('demo upload send and history reopen preserves multiple attachments', () async {
    final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
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

    // Send from the first visible upload notification, before addImageAttachment returns.
    Future<void>? sendFuture;
    void sendWhenUploading() {
      if (workspace.hasPendingUploads) sendFuture ??= workspace.send('分析此图');
    }

    workspace.addListener(sendWhenUploading);
    final imageBytes = [1, 2, 3, 4];
    final upload = workspace.addImageAttachment('pending.png', imageBytes);
    workspace.removeListener(sendWhenUploading);
    await Future<void>.delayed(Duration.zero);
    expect(sendFuture, isNotNull);
    expect(workspace.turns, isEmpty);

    uploadCompleter.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'url': 'temp/pending.png'},
        },
      ),
    );
    await Future.wait([upload, sendFuture!]);

    expect(workspace.hasPendingUploads, isFalse);
    expect(workspace.attachments, isEmpty);
    expect(workspace.turns.length, 1);
    final turn = workspace.turns.first;
    expect(turn.attachedImageBytesList.firstOrNull, equals(imageBytes));
    expect(turn.attachedImageUrls.firstOrNull, contains('temp/pending.png'));
    final json = jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    expect(visionImageLabels(json), [turn.attachedImageUrls.firstOrNull]);
    expect(json['chatInfo'], contains(turn.attachedImageUrls.firstOrNull!));
  });

  test('a document picked during the pre-send history check joins that follow-up', () async {
    await workspace.send('First message');
    final history = Completer<void>();
    final uploaded = Completer<GenAiResponse>();
    final original = transport.handle;
    transport.handle = (r) async {
      if (r.uri.path.endsWith('/getByChatGroupId')) await history.future;
      if (r.uri.path.endsWith('/upload/chat/file')) return uploaded.future;
      return original(r);
    };

    final send = workspace.send('Use the attached notes');
    final upload = workspace.addDocumentAttachment('notes.txt', utf8.encode('42'));
    history.complete();
    await Future<void>.delayed(Duration.zero);
    expect(workspace.turns, hasLength(1));

    uploaded.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'fileId': 'notes-id', 'content': '42'},
        },
      ),
    );
    await Future.wait([send, upload]);
    final file = workspace.turns.last.files.single;
    expect((file.id, file.name, file.content), ('notes-id', 'notes.txt', '42'));
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
    expect(workspace.attachments.first.imageUrl, contains('temp/recovered.png'));

    await workspace.send('重试成功后可以正常发送');
    expect(workspace.attachments, isEmpty);
    expect(workspace.turns.length, 1);
    final turn = workspace.turns.first;
    expect(turn.attachedImageBytesList.firstOrNull, equals(imageBytes));
    expect(turn.attachedImageUrls.firstOrNull, contains('temp/recovered.png'));
  });
}
