import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';
import '../support/fakes.dart';

void main() {
  late ScriptedTransport transport;
  late GenAiSessionService sessions;
  late GenAiWorkspaceController workspace;
  late GenAiChatService chat;
  late Completer<GenAiResponse> searchGate;
  late Completer<void> searchStarted;
  setUp(() async {
    searchGate = Completer<GenAiResponse>();
    searchStarted = Completer<void>();
    transport = ScriptedTransport((r) async {
      if (r.uri.path.endsWith('/net/search')) {
        if (!searchStarted.isCompleted) searchStarted.complete();
        return searchGate.future;
      }
      if (r.uri.path.endsWith('/aiModel/list')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'records': [
                {
                  'aiName': 'Free',
                  'aiType': 'free',
                  'rootAiType': 'fixture',
                  'payType': 'FREE',
                  'status': 1,
                }
              ],
            },
          },
        );
      }
      if (r.uri.path.contains('/user/info/')) {
        return profileResponse(
          r.headers['X-Access-Token'] == 'token-b'
              ? ownerB.studentId
              : ownerA.studentId,
        );
      }
      return response(
        type: 'text/event-stream',
        text: sseChunk(text: 'answer', finish: 'stop'),
      );
    });
    final api = GenAiApiClient(
      transport: transport,
      signer: const GenAiRequestSigner('synthetic'),
    );
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'token-a'));
    final repo = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repo);
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repo,
      chat: chat,
    );
    await workspace.reloadModels();
  });
  tearDown(() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
  });
  test('stop during web search prevents the chat POST', () async {
    workspace.setNetSearch(true);
    final sending = workspace.send('private prompt A');
    await searchStarted.future;
    workspace.stop();
    searchGate.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'links': <Object>[]},
        },
      ),
    );
    await sending;
    final posts = transport.requests
        .where((r) => r.uri.path.endsWith('/start/chat'))
        .toList();
    expect(posts, isEmpty);
    expect(workspace.turns.single.phase, GenAiChatPhase.cancelled);
    expect(workspace.turns.single.isSearching, isFalse);
  });
  test(
      'account switch during search never submits the old prompt with a new token',
      () async {
    workspace.setNetSearch(true);
    final sending = workspace.send('private prompt A');
    await searchStarted.future;
    final changing = sessions.setOwner(ownerB);
    final connecting =
        sessions.connect(const GenAiCredential(token: 'token-b'));
    await Future.wait([changing, connecting]);
    await sending;
    final posts = transport.requests
        .where((r) => r.uri.path.endsWith('/start/chat'))
        .toList();
    expect(posts, isEmpty);
    expect(workspace.turns, isEmpty);
    await workspace.reloadModels();
    workspace.setNetSearch(false);
    await workspace.send('new prompt B');
    final request = transport.requests.last;
    expect(request.headers['X-Access-Token'], 'token-b');
    expect(jsonDecode(request.body!)['chatInfo'], 'new prompt B');
    searchGate.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'links': <Object>[]},
        },
      ),
    );
  });
  test('delayed history loading cannot erase a newer conversation', () async {
    final gate = Completer<GenAiResponse>();
    final started = Completer<void>();
    final original = transport.handle;
    transport.handle = (r) {
      if (r.uri.path.endsWith('/getByChatGroupId')) {
        started.complete();
        return gate.future;
      }
      return original(r);
    };
    final opening =
        workspace.openConversation('history-A', GenAiCancellation());
    await started.future;
    workspace.newConversation();
    await workspace.send('new work');
    gate.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {
              'question': 'old history',
              'answer': 'old answer',
              'aiType': 'free',
            },
          ],
        },
      ),
    );
    await opening;
    expect(workspace.groupId, isNot('history-A'));
    expect(workspace.turns.single.prompt, 'new work');
  });

  test('new conversation during search prevents old chat from starting',
      () async {
    workspace.setNetSearch(true);
    final sending = workspace.send('old prompt');
    await searchStarted.future;
    workspace.newConversation();
    await sending;
    searchGate.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': {'links': <Object>[]},
        },
      ),
    );
    expect(
      transport.requests.where((r) => r.uri.path.endsWith('/start/chat')),
      isEmpty,
    );
    expect(workspace.turns, isEmpty);
  });

  test('only the latest history selection may update the workspace', () async {
    final first = Completer<GenAiResponse>();
    final second = Completer<GenAiResponse>();
    final original = transport.handle;
    transport.handle = (r) {
      if (r.uri.path.endsWith('/getByChatGroupId')) {
        return r.uri.queryParameters['chatGroupId'] == 'first'
            ? first.future
            : second.future;
      }
      return original(r);
    };
    final openingFirst =
        workspace.openConversation('first', GenAiCancellation());
    final openingSecond =
        workspace.openConversation('second', GenAiCancellation());
    await Future<void>.delayed(Duration.zero);
    second.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {'question': 'second', 'answer': 'answer', 'aiType': 'free'},
          ],
        },
      ),
    );
    await openingSecond;
    first.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {'question': 'first', 'answer': 'answer', 'aiType': 'free'},
          ],
        },
      ),
    );
    await openingFirst;
    expect(workspace.groupId, 'second');
    expect(workspace.turns.single.prompt, 'second');
  });
}
