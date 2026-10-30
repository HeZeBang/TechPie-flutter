import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';
import 'package:techpie/features/genai/presentation/genai_history_controller.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

void main() {
  late FakeGenAiServer backend;
  late ScriptedTransport transport;
  late GenAiSessionService sessions;
  late GenAiChatService chat;
  late GenAiWorkspaceController workspace;

  Future<GenAiResponse> forward(RecordedRequest request) => backend.send(
        method: request.method,
        uri: request.uri,
        cancellation: request.cancellation,
        headers: request.headers,
        body: request.body,
        bodyBytes: request.bodyBytes,
      );
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  int listRequests() => transport.requests
      .where((request) => request.uri.path.endsWith('/listByContentGroup'))
      .length;

  setUp(() async {
    backend = FakeGenAiServer(chunkDelay: Duration.zero);
    transport = ScriptedTransport(forward);
    final api = GenAiApiClient(transport: transport);
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
    final repository = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repository);
    workspace = GenAiWorkspaceController(sessions: sessions, repository: repository, chat: chat);
    await workspace.reloadModels();
  });

  tearDown(() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    backend.dispose();
  });

  GenAiResponse page() => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              for (var index = 0; index < 6; index++)
                {'chatGroupId': 'group-$index', 'question': 'Raw continuation $index'},
            ],
            'total': 6,
          },
        },
      );
  GenAiResponse detail(String id) => response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {
              'question': 'Logical title $id',
              'answer': 'Saved answer',
              'createTime': '2026-10-29T12:00:0${id.substring(id.length - 1)}Z',
            },
          ],
        },
      );

  test('history summaries use four concurrent reads and preserve logical titles and order',
      () async {
    final gates = <String, Completer<GenAiResponse>>{};
    var inFlight = 0;
    var maximumInFlight = 0;
    transport.handle = (request) {
      if (request.uri.path.endsWith('/listByContentGroup')) return Future.value(page());
      if (request.uri.path.endsWith('/getByChatGroupId')) {
        final id = request.uri.queryParameters['chatGroupId']!;
        final gate = Completer<GenAiResponse>();
        gates[id] = gate;
        inFlight++;
        if (inFlight > maximumInFlight) maximumInFlight = inFlight;
        return gate.future.whenComplete(() => inFlight--);
      }
      return forward(request);
    };
    final pending = workspace.listConversations(GenAiCancellation());
    await settle();
    expect(gates, hasLength(4));
    // Finishing one request starts the next without waiting for its siblings.
    gates['group-2']!.complete(detail('group-2'));
    await settle();
    expect(gates, hasLength(5));
    gates['group-0']!.complete(detail('group-0'));
    await settle();
    expect(gates, hasLength(6));
    for (final entry in gates.entries) {
      if (!entry.value.isCompleted) entry.value.complete(detail(entry.key));
    }
    final result = await pending;
    expect(maximumInFlight, 4);
    expect(
      result.records.map((item) => item.id),
      ['group-5', 'group-4', 'group-3', 'group-2', 'group-1', 'group-0'],
    );
    expect(
      result.records.map((item) => item.title),
      result.records.map((item) => 'Logical title ${item.id}'),
    );
  });

  for (final accountChanged in [false, true]) {
    test('${accountChanged ? 'account change' : 'cancellation'} stops queued history reads',
        () async {
      final gates = <Completer<GenAiResponse>>[];
      transport.handle = (request) {
        if (request.uri.path.endsWith('/listByContentGroup')) return Future.value(page());
        if (request.uri.path.endsWith('/getByChatGroupId')) {
          final gate = Completer<GenAiResponse>();
          gates.add(gate);
          return gate.future;
        }
        return forward(request);
      };
      final cancellation = GenAiCancellation();
      final expected = expectLater(
        workspace.listConversations(cancellation),
        throwsA(
          failure(accountChanged ? GenAiFailureKind.accountChanged : GenAiFailureKind.cancelled),
        ),
      );
      await settle();
      expect(gates, hasLength(4));
      if (accountChanged) {
        await sessions.setOwner(ownerB);
      } else {
        cancellation.cancel();
      }
      await expected;
      for (final gate in gates) {
        gate.complete(detail('group-0'));
      }
      await settle();
      expect(gates, hasLength(4));
    });
  }

  test('navigation and pre-send reads do not refresh history; settled retries do', () async {
    final history = GenAiHistoryController(workspace);
    addTearDown(history.dispose);
    await settle();
    expect(listRequests(), 1);
    final countsAtPost = <int>[];
    transport.handle = (request) {
      if (request.method == 'POST') countsAtPost.add(listRequests());
      return forward(request);
    };
    await workspace.send('First message');
    await settle();
    expect(listRequests(), 2);
    final id = workspace.groupId;
    workspace.newConversation();
    await workspace.openConversation(id, GenAiCancellation());
    await settle();
    expect(listRequests(), 2);
    await workspace.send('Follow-up');
    await settle();
    expect(listRequests(), 3);
    await workspace.retryTurn(1);
    await settle();
    expect(workspace.turns, hasLength(2));
    expect(listRequests(), 4);
    expect(countsAtPost, [1, 2, 3]);

    final wire = StreamController<List<int>>();
    transport.handle = (request) async => request.method == 'POST'
        ? response(type: 'text/event-stream', bytes: wire.stream)
        : forward(request);
    final stopped = workspace.send('Stop this reply');
    await settle();
    expect(listRequests(), 4);
    workspace.stop();
    await wire.close();
    await stopped;
    await settle();
    expect(listRequests(), 5);
  });

  test('refresh retains the immutable visible list and failure until explicit retry', () async {
    await workspace.send('Saved conversation');
    final history = GenAiHistoryController(workspace);
    addTearDown(history.dispose);
    await settle();
    final visible = history.conversations;
    expect(visible, hasLength(1));
    expect(history.conversations, same(visible));
    expect(() => visible.clear(), throwsUnsupportedError);
    final gate = Completer<GenAiResponse>();
    transport.handle = (request) =>
        request.uri.path.endsWith('/listByContentGroup') ? gate.future : forward(request);
    final loading = history.load();
    expect(history.loading, isTrue);
    expect(history.conversations, same(visible));
    await settle();
    gate.completeError(const GenAiFailure(GenAiFailureKind.transport));
    await loading;
    expect(history.loading, isFalse);
    expect(history.conversations, same(visible));
    expect(history.failure?.kind, GenAiFailureKind.transport);
    final before = listRequests();
    workspace.newConversation();
    await settle();
    expect(listRequests(), before);
    expect(history.failure?.kind, GenAiFailureKind.transport);
    transport.handle = forward;
    await history.load();
    expect(history.failure, isNull);
    expect(history.conversations.single.id, visible.single.id);
  });
}
