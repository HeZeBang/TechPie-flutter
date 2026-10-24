import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_store.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';

import '../support/fakes.dart';

// A JSON-compatible context value measures deep snapshot construction, not
// merely store writes: batching only writes would still serialize every delta.
final class _SerializationProbe {
  int copies = 0;

  Map<String, Object?> toJson() {
    copies++;
    return {'value': 'original context'};
  }
}

final class _ArchiveStore implements GenAiConversationStore {
  final memory = MemoryGenAiConversationStore();
  final writes = <(String, GenAiConversationArchive)>[];

  @override
  Future<void> write(String scope, GenAiConversationArchive archive) async {
    writes.add((scope, archive));
    await memory.write(scope, archive);
  }

  @override
  Future<GenAiConversationArchive?> read(String scope, String id) =>
      memory.read(scope, id);
  @override
  Future<List<GenAiConversationSummary>> list(String scope) =>
      memory.list(scope);
  @override
  Future<Set<String>> deletedIds(String scope) => memory.deletedIds(scope);
  @override
  Future<Set<String>> pendingDeletionIds(String scope) =>
      memory.pendingDeletionIds(scope);
  @override
  Future<void> beginDeletion(String scope, String id) =>
      memory.beginDeletion(scope, id);
  @override
  Future<void> rollbackDeletion(String scope, String id) =>
      memory.rollbackDeletion(scope, id);
  @override
  Future<void> delete(String scope, String id) => memory.delete(scope, id);
}

void main() {
  late GenAiSessionService sessions;
  late GenAiRepository repository;
  late GenAiChatService chat;
  late GenAiWorkspaceController workspace;
  late _ArchiveStore archives;
  late StreamController<List<int>> stream;
  var disposed = false;

  Future<void> initialize() async {
    disposed = false;
    stream = StreamController<List<int>>();
    final transport = ScriptedTransport((request) async {
      if (request.uri.path.endsWith('/list')) {
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
                },
              ],
            },
          },
        );
      }
      if (request.method == 'POST') {
        return response(type: 'text/event-stream', bytes: stream.stream);
      }
      return profileResponse();
    });
    final api = GenAiApiClient(transport: transport);
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'fixture'));
    repository = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repository);
    archives = _ArchiveStore();
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
      conversationStore: archives,
    );
    await workspace.reloadModels();
  }

  void runBatchedTest(void Function(FakeAsync clock) body) {
    fakeAsync((clock) {
      // The controller's initial write future must use the same fake clock as
      // later stream notifications and archive timers.
      unawaited(initialize());
      clock.flushMicrotasks();
      try {
        body(clock);
      } finally {
        if (!disposed) workspace.dispose();
        chat.dispose();
        sessions.dispose();
        unawaited(stream.close());
        clock.flushMicrotasks();
      }
    });
  }

  test(
      'streaming batches deep snapshots and explicit flush captures new tokens',
      () {
    runBatchedTest((clock) {
      final probe = _SerializationProbe();
      repository.restoreContext(workspace.groupId, {'probe': probe});
      unawaited(workspace.send('stream a response'));
      clock.flushMicrotasks();
      for (var i = 0; i < 100; i++) {
        stream.add(utf8.encode(sseChunk(text: '$i ')));
      }
      clock.flushMicrotasks();
      final answer = List.generate(100, (i) => '$i ').join();
      expect(workspace.turns.single.answer, answer);
      expect(probe.copies, 0);
      expect(archives.writes, isEmpty);
      clock.elapse(const Duration(milliseconds: 99));
      expect(probe.copies, 0);
      clock.elapse(const Duration(milliseconds: 1));
      clock.flushMicrotasks();
      expect(probe.copies, 1);
      expect(archives.writes.single.$2.restoreTurns().single.answer, answer);

      stream.add(utf8.encode(sseChunk(text: 'latest')));
      clock.flushMicrotasks();
      expect(probe.copies, 1);
      unawaited(workspace.flushConversations());
      clock.flushMicrotasks();
      expect(probe.copies, 2);
      expect(archives.writes, hasLength(2));
      expect(
        archives.writes.last.$2.restoreTurns().single.answer,
        '${answer}latest',
      );
      clock.elapse(const Duration(milliseconds: 100));
      expect(probe.copies, 2);
    });
  });

  for (final boundary in ['conversation', 'account', 'dispose']) {
    test('$boundary change captures the dirty transcript before clearing it',
        () {
      runBatchedTest((clock) {
        final id = workspace.groupId;
        final scope = workspace.accountScope;
        unawaited(workspace.send('private prompt'));
        clock.flushMicrotasks();
        stream.add(utf8.encode(sseChunk(text: 'latest streamed text')));
        clock.flushMicrotasks();
        final turn = workspace.turns.single;
        expect(archives.writes, isEmpty);

        switch (boundary) {
          case 'conversation':
            workspace.newConversation();
          case 'account':
            unawaited(sessions.setOwner(ownerB));
          case 'dispose':
            workspace.dispose();
            disposed = true;
        }
        // Queued storage must hold an immutable snapshot from the boundary,
        // even though the mutable turn remains accessible to an old callback.
        turn.answer = 'late stale callback';
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 100));
        expect(archives.writes, hasLength(1));
        final (storedScope, archive) = archives.writes.single;
        expect(storedScope, scope);
        expect(archive.id, id);
        expect(archive.restoreTurns().single.prompt, 'private prompt');
        expect(archive.restoreTurns().single.answer, 'latest streamed text');
        expect(archive.restoreTurns().single.phase, GenAiChatPhase.cancelled);
      });
    });
  }
}
