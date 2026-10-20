import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
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
}
