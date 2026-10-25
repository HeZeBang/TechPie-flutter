import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_store.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';

import '../support/fakes.dart';

Stream<GenAiChatEvent> _answer(String text) async* {
  yield GenAiTextDelta(text);
  yield const GenAiChatFinished(GenAiFinishReason.stop);
}

String _call(String id, GenAiChatRequest request) => encodeGenAiAgentCall(
      GenAiAgentToolCall(id: id, name: 'campus_action', arguments: const {}),
      nonce: genAiAgentNonceFromSystem(request.history.first.content)!,
    );

String _search(String id, String query, GenAiChatRequest request) => encodeGenAiAgentCall(
      GenAiAgentToolCall(
        id: id,
        name: 'web_search',
        arguments: {'query': query},
      ),
      nonce: genAiAgentNonceFromSystem(request.history.first.content)!,
    );

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100 && !predicate(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Expected controller state was not reached',
  );
}

class _ArchiveStore implements GenAiConversationStore {
  final memory = MemoryGenAiConversationStore();
  final writes = <(String, GenAiConversationArchive)>[];
  bool failWrites = false;
  bool failDeletes = false;
  bool failBeginDeletion = false;
  bool failAfterBeginDeletion = false;
  Completer<void>? readGate;
  Completer<void>? readStarted;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  bool failNextWriteAfterGate = false;
  Completer<void>? deletedGate;
  Completer<void>? deletedStarted;

  @override
  Future<GenAiConversationArchive?> read(String scope, String id) async {
    final value = await memory.read(scope, id);
    if (readStarted?.isCompleted == false) readStarted!.complete();
    await readGate?.future;
    return value;
  }

  @override
  Future<void> write(String scope, GenAiConversationArchive archive) async {
    if (failWrites) throw const GenAiFailure(GenAiFailureKind.storage);
    writes.add((scope, archive));
    final failAfterGate = failNextWriteAfterGate;
    failNextWriteAfterGate = false;
    if (writeStarted?.isCompleted == false) writeStarted!.complete();
    await writeGate?.future;
    if (failAfterGate) throw const GenAiFailure(GenAiFailureKind.storage);
    await memory.write(scope, archive);
  }

  @override
  Future<List<GenAiConversationSummary>> list(String scope) => memory.list(scope);
  @override
  Future<Set<String>> deletedIds(String scope) async {
    final value = await memory.deletedIds(scope);
    if (deletedStarted?.isCompleted == false) deletedStarted!.complete();
    await deletedGate?.future;
    return value;
  }

  @override
  Future<void> beginDeletion(String scope, String id) async {
    if (failBeginDeletion) throw const GenAiFailure(GenAiFailureKind.storage);
    await memory.beginDeletion(scope, id);
    if (failAfterBeginDeletion) {
      throw const GenAiFailure(GenAiFailureKind.storage);
    }
  }

  @override
  Future<void> rollbackDeletion(String scope, String id) => memory.rollbackDeletion(scope, id);
  @override
  Future<Set<String>> pendingDeletionIds(String scope) => memory.pendingDeletionIds(scope);

  @override
  Future<void> delete(String scope, String id) {
    if (failDeletes) throw const GenAiFailure(GenAiFailureKind.storage);
    return memory.delete(scope, id);
  }
}

void main() {
  late ScriptedTransport transport;
  late GenAiSessionService sessions;
  late GenAiChatService chat;
  late GenAiWorkspaceController workspace;
  late ValueNotifier<int> scope;
  late _ArchiveStore archives;

  setUp(() async {
    transport = ScriptedTransport((request) async {
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
      if (request.uri.path.endsWith('/listByContentGroup')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {'records': <Object?>[], 'total': 0},
          },
        );
      }
      if (request.uri.path == '/sys/common/upload') {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {'url': 'temp/fixture.png'},
          },
        );
      }
      if (request.uri.path.endsWith('/chat/upload/chat/file')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'fileId': 'fixture-document',
              'fileName': 'reference.txt',
              'content': 'Synthetic document evidence',
            },
          },
        );
      }
      if (request.uri.path.endsWith('/net/search')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'links': [
                {
                  'num': 1,
                  'title': 'Campus source',
                  'link': 'https://example.com/campus',
                  'snippet': 'Synthetic campus evidence',
                },
              ],
            },
          },
        );
      }
      if (request.method == 'POST') {
        return response(
          type: 'text/event-stream',
          text: sseChunk(text: 'normal answer', finish: 'stop'),
        );
      }
      return profileResponse();
    });
    final api = GenAiApiClient(
      transport: transport,
      signer: const GenAiRequestSigner('synthetic-salt'),
    );
    sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'fixture'));
    final repository = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repository);
    archives = _ArchiveStore();
    workspace = GenAiWorkspaceController(
      conversationStore: archives,
      sessions: sessions,
      repository: repository,
      chat: chat,
    );
    scope = ValueNotifier(1);
    await workspace.reloadModels();
  });

  tearDown(() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    scope.dispose();
  });

  void install(
    GenAiAgentChatStream stream, {
    Future<Object?> Function()? execute,
    bool approval = false,
    GenAiAgentLimits limits = const GenAiAgentLimits(),
  }) {
    workspace.configureAgent(
      runner: GenAiAgentRunner(
        streamChat: stream,
        limits: limits,
        tools: GenAiAgentToolRegistry([
          GenAiAgentTool(
            name: 'campus_action',
            description: 'Synthetic campus action',
            parameters: const {
              'type': 'object',
              'properties': <String, Object?>{},
            },
            prepare: (_, context) async => GenAiAgentPreparedTool(
              requiresApproval: approval,
              summary: 'Synthetic action',
              effectKey: 'same-action',
              execute: () async {
                context.checkActive();
                return execute == null ? {'value': 42} : execute();
              },
            ),
          ),
        ]),
      ),
      scope: () => scope.value,
      scopeChanges: scope,
    );
  }

  test('agent and chat share group, model and context across mode switches', () async {
    final requests = <GenAiChatRequest>[];
    install((request, _) {
      requests.add(request);
      return _answer(
        requests.length == 1 ? _call('read', request) : 'agent answer',
      );
    });
    await workspace.send('normal first');
    final group = workspace.groupId;
    workspace.setAgentEnabled(true);
    await workspace.send('use campus tool');
    expect(workspace.turns.length, 2);
    expect(workspace.turns.last.isAgent, isTrue);
    expect(workspace.turns.last.agentEvents['read']?.result?['ok'], isTrue);
    expect(requests.first.chatGroupId, group);
    final agentMessages = requests.first.toJson()['messages']! as List;
    expect((agentMessages.first as Map)['role'], 'system');
    expect(
      (agentMessages.first as Map)['content'],
      contains('campus_tools: true'),
    );
    expect(
      agentMessages.where((m) => (m as Map)['role'] == 'system'),
      hasLength(1),
    );
    expect(requests.first.aiType, workspace.selectedModel!.aiType);
    expect(
      requests.first.history.map((m) => m.content),
      contains('normal first'),
    );
    workspace.setAgentEnabled(false);
    await workspace.send('normal followup');
    final post = transport.requests.last;
    final body = jsonDecode(post.body!) as Map<String, dynamic>;
    expect(
      body['messages'],
      contains(equals({'role': 'assistant', 'content': 'agent answer'})),
    );
    expect(
      body['messages'].toString(),
      contains('techpie-agent-history'),
      reason: 'Inert tool receipts remain source evidence when tools are disabled',
    );
    final normalMessages = body['messages'] as List;
    expect((normalMessages.first as Map)['role'], 'system');
    expect(
      (normalMessages.first as Map)['content'],
      contains('campus_tools: false'),
    );
    expect(
      normalMessages.where((m) => (m as Map)['role'] == 'system'),
      hasLength(1),
    );
    workspace.setAgentEnabled(true);
    await workspace.send('agent followup');
    expect(
      requests.last.history.map((m) => m.content),
      contains('normal followup'),
    );
    expect(
      requests.last.history.any((m) => m.content.contains('techpie-agent-history')),
      isTrue,
    );
    expect(workspace.groupId, group);
  });

  test('agent archives store per-turn evidence and recover legacy checkpoints and gaps', () async {
    final requests = <GenAiChatRequest>[];
    install((request, _) {
      requests.add(request);
      return _answer(requests.length == 1 ? _call('archive-read', request) : 'Recorded.');
    });
    workspace.setAgentEnabled(true);
    final id = workspace.groupId;
    var halfSize = 0;
    for (var i = 0; i < 20; i++) {
      await workspace.send('Original source $i: ${'x' * 2000}');
      if (i == 0) {
        // This first cumulative checkpoint is the format of older archives.
        workspace.turns.first.agentTranscriptIsDelta = false;
      }
      await workspace.flushConversations();
      if (i == 9) halfSize = archives.writes.last.$2.encode().length;
    }
    final saved = archives.writes.last.$2;
    final archiveScope = archives.writes.last.$1;
    expect(saved.encode().length, lessThan(halfSize * 2.2));
    expect(
      saved.restoreTurns().fold<int>(0, (n, turn) => n + turn.agentTranscript.length),
      42, // Twenty exchanges and one typed tool call/result pair.
    );
    final legacyJson = jsonDecode(saved.encode()) as Map<String, dynamic>;
    ((legacyJson['turns'] as List).first as Map).remove('agentTranscriptIsDelta');
    await archives.memory.write(archiveScope, GenAiConversationArchive.fromJson(legacyJson));
    workspace.newConversation();
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    await workspace.send('Recall the original records');
    final history = requests.last.history.skip(1).map((m) => m.content).join();
    expect(history, contains('Original source 0:'));
    expect(history, contains('Original source 19:'));
    expect(history, contains('archive-read'));
    expect(history, contains('42'));
    await workspace.retryTurn(workspace.turns.length - 1);
    expect(requests.last.history.skip(1).map((m) => m.content).join(), history);

    // Recovery must not join evidence across a missing-history boundary.
    final afterGap = GenAiConversationArchive(
      id: id,
      title: saved.title,
      updatedAt: DateTime.now(),
      turns: [
        ...saved.restoreTurns(),
        GenAiConversationTurn('Missing history', isHistoryGap: true),
        GenAiConversationTurn('Only after the gap')
          ..answer = 'Understood.'
          ..phase = GenAiChatPhase.completed,
      ],
      agentEnabled: true,
      netSearchEnabled: false,
      thinkingEnabled: false,
      modelAiType: saved.modelAiType,
      modelRootAiType: saved.modelRootAiType,
      mutations: saved.mutations,
    );
    workspace.newConversation();
    await workspace.flushConversations();
    await archives.memory.write(archiveScope, afterGap);
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    await workspace.send('Continue after the gap');
    final gapHistory = requests.last.history.map((m) => m.content).join();
    expect(gapHistory, contains('Only after the gap'));
    expect(gapHistory, isNot(contains('Original source')));
    expect(gapHistory, isNot(contains('archive-read')));
  });

  test('documents survive normal followups, mode switches, reopen and retry without leaking',
      () async {
    final agentRequests = <GenAiChatRequest>[];
    install((request, _) {
      agentRequests.add(request);
      return _answer('agent answer');
    });
    var uploads = 0;
    final original = transport.handle;
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/chat/upload/chat/file')) {
        uploads++;
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'fileId': 'doc-$uploads',
              'fileName': 'reference.txt',
              'content': 'Synthetic document evidence',
            },
          },
        );
      }
      return original(request);
    };
    Map<String, dynamic> lastChat() =>
        jsonDecode(transport.requests.last.body!) as Map<String, dynamic>;
    await workspace.addDocumentAttachment('notes.md', utf8.encode('# Context'));
    expect(workspace.attachments.single.name, 'notes.md');
    await workspace.send('Summarize');
    await workspace.send('What are the details?');
    expect(lastChat()['fileIds'], ['doc-1']);
    expect(lastChat().containsKey('fileIDs'), isFalse);
    expect(
      (lastChat()['messages'] as List).first['content'],
      contains('documents: true'),
    );
    await workspace.addDocumentAttachment('data.csv', utf8.encode('a,b\n1,2'));
    await workspace.send('Compare both documents');
    expect(lastChat()['fileIds'], ['doc-1', 'doc-2']);
    workspace.setAgentEnabled(true);
    await workspace.send('Use tools with both documents');
    expect(agentRequests.last.fileIds, ['doc-1', 'doc-2']);
    workspace.setAgentEnabled(false);
    final id = workspace.groupId;
    await workspace.flushConversations();
    workspace.newConversation();
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    workspace.setAgentEnabled(false);
    await workspace.send('Continue after reopening');
    expect(lastChat()['fileIds'], ['doc-1', 'doc-2']);
    final beforeRetry = transport.requests.length;
    await workspace.retryTurn(1);
    expect(transport.requests, hasLength(beforeRetry));
    await workspace.retryTurn(workspace.turns.length - 1);
    expect(lastChat()['fileIds'], ['doc-1', 'doc-2']);
    expect(uploads, 2, reason: 'Followups reuse IDs without uploading again');
    workspace.newConversation();
    await workspace.send('Unrelated question');
    expect(lastChat().containsKey('fileIds'), isFalse);
    expect(
      (lastChat()['messages'] as List).first['content'],
      contains('documents: false'),
    );
  });

  test('invalid document errors remain actionable and prevent sending', () async {
    final before = transport.requests.length;
    await workspace.addDocumentAttachment('slides.pptx', [1, 2, 3]);
    expect(workspace.attachments.single.error, contains('不支持此格式'));
    expect(transport.requests.length, before);
    await workspace.send('Read this');
    expect(workspace.turns, isEmpty);
    expect(transport.requests.length, before);
  });

  test('agent/search coexist with uploaded attachments', () async {
    install((_, __) => _answer('done'));
    workspace.setNetSearch(true);
    final revision = workspace.conversationRevision;
    workspace.setAgentEnabled(true);
    expect(workspace.netSearchEnabled, isTrue);
    expect(workspace.conversationRevision, greaterThan(revision));
    await workspace.addImageAttachment('reference.png', [1]);
    expect(workspace.attachments, hasLength(1));
    workspace.setNetSearch(false);
    expect(workspace.agentEnabled, isTrue);
    workspace.setNetSearch(true);
    expect(workspace.agentEnabled, isTrue);
    workspace.setAgentEnabled(false);
    await workspace.addImageAttachment('kept.png', [1]);
    expect(workspace.attachments, hasLength(2));
    workspace.setAgentEnabled(true);
    expect(workspace.agentEnabled, isTrue);
    expect(workspace.attachments, hasLength(2));
  });

  test('combined modes ground tool follow-ups and restore all settings', () async {
    final original = transport.handle;
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/list')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'records': [
                {
                  'aiName': 'DeepSeek',
                  'aiType': 'deepseek-pro',
                  'rootAiType': 'fixture',
                  'payType': 'FREE',
                },
              ],
            },
          },
        );
      }
      return original(request);
    };
    await workspace.reloadModels();
    final requests = <GenAiChatRequest>[];
    install((request, _) async* {
      requests.add(request);
      yield const GenAiReasoningDelta('Reasoning stays separate.');
      yield* _answer(
        switch (requests.length) {
          1 => _search('search-1', 'campus public resources', request),
          2 => _search('search-2', 'campus library public hours', request),
          3 => _call('combined-read', request),
          _ => 'Grounded final',
        },
      );
    });
    workspace.setNetSearch(true);
    workspace.setThinking(true);
    workspace.setAgentEnabled(true);
    await workspace.addDocumentAttachment(
      'reference.txt',
      utf8.encode('Synthetic document content'),
    );
    await workspace.addImageAttachment('reference.png', [1, 2, 3]);
    expect(workspace.attachments.every((a) => a.error == null), isTrue);
    await workspace.send('Check my campus question');
    for (final request in requests) {
      final messages = request.toJson()['messages']! as List;
      expect((messages.first as Map)['role'], 'system');
      final system = (messages.first as Map)['content'] as String;
      for (final capability in [
        'campus_tools',
        'thinking',
        'web_search',
        'documents',
        'images',
      ]) {
        expect(system, contains('$capability: true'));
      }
      expect(
        messages.where((m) => (m as Map)['role'] == 'system'),
        hasLength(1),
      );
      expect(request.fileIds, ['fixture-document']);
      expect(request.imageUrls, hasLength(1));
      expect(request.imageUrls.single, contains('fixture.png'));
    }
    expect(requests.map((r) => r.thinking), [true, true, true, true]);
    expect(requests.every((r) => !r.netGo), isTrue);
    expect(
      requests.last.history.any((m) => m.content.contains('Synthetic campus evidence')),
      isTrue,
    );
    expect(
      requests.last.history.any((m) => m.content.contains('Reasoning stays separate.')),
      isFalse,
    );
    final searches = transport.requests.where((r) => r.uri.path.endsWith('/net/search')).toList();
    expect(searches, hasLength(2));
    expect(
      (jsonDecode(searches.first.body!) as Map)['chatInfo'],
      'campus public resources',
    );
    expect(
      (jsonDecode(searches.last.body!) as Map)['chatInfo'],
      'campus library public hours',
    );
    for (final search in searches) {
      final body = jsonDecode(search.body!) as Map<String, dynamic>;
      expect(body['messages'], isEmpty);
      expect(
        body.containsKey('imageUrls') || body.containsKey('fileIds'),
        isFalse,
      );
    }
    final turn = workspace.turns.single;
    expect(turn.citations.map((c) => c.num), [1, 2]);
    expect(turn.reasoning, contains('Reasoning stays separate.'));
    expect(turn.isAgentThinking, isFalse);
    expect(turn.isSearching, isFalse);
    final id = workspace.groupId;
    await workspace.flushConversations();
    workspace.newConversation();
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    expect(
      workspace.agentEnabled && workspace.netSearchEnabled && workspace.thinkingEnabled,
      isTrue,
    );
    expect(workspace.turns.single.citations, hasLength(2));
    expect(workspace.turns.single.reasoning, turn.reasoning);
    expect(turn.agentActivity.map((e) => e.call?.name ?? e.kind.name), [
      'reasoningDelta',
      'web_search',
      'reasoningDelta',
      'web_search',
      'reasoningDelta',
      'campus_action',
      'reasoningDelta',
    ]);
    expect(
      workspace.turns.single.toArchiveJson()['agentActivity'],
      turn.toArchiveJson()['agentActivity'],
    );
    expect(workspace.turns.single.attachedFileIds, ['fixture-document']);
    await workspace.send('Follow up on those attachments');
    expect(requests.last.fileIds, ['fixture-document']);
    expect(requests.last.imageUrls, hasLength(1));
    workspace.newConversation();
    await workspace.send('Unrelated new conversation');
    expect(requests.last.fileIds, isEmpty);
    expect(requests.last.imageUrls, isEmpty);
    expect(requests.last.history.first.content, contains('documents: false'));
    expect(requests.last.history.first.content, contains('images: false'));
    workspace.setNetSearch(false);
    workspace.setThinking(false);
    await workspace.send('No search or deep thinking now');
    expect(requests.last.history.first.content, contains('web_search: false'));
    expect(requests.last.history.first.content, contains('thinking: false'));
    expect(requests.last.thinking, isFalse);
  });

  for (final interrupt in ['stop', 'new-chat', 'account']) {
    test('agent search cannot continue model after $interrupt', () async {
      final release = Completer<void>();
      final original = transport.handle;
      transport.handle = (request) async {
        if (request.uri.path.endsWith('/net/search')) await release.future;
        return original(request);
      };
      var modelCalls = 0;
      install((request, _) {
        modelCalls++;
        return _answer(_search('delayed', 'public campus info', request));
      });
      workspace.setAgentEnabled(true);
      workspace.setNetSearch(true);
      final pending = workspace.send('delayed search');
      await _until(
        () => transport.requests.any((r) => r.uri.path.endsWith('/net/search')),
      );
      if (interrupt == 'stop') {
        workspace.stop();
      } else if (interrupt == 'new-chat') {
        workspace.newConversation();
      } else {
        await sessions.setOwner(ownerB);
      }
      release.complete();
      await pending;
      expect(modelCalls, 1);
      expect(
        workspace.turns.every((t) => !t.isSearching && !t.isAgentThinking),
        isTrue,
      );
      expect(workspace.sending, isFalse);
    });
  }

  test('agent receives structured search failure and can explain it', () async {
    final original = transport.handle;
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/net/search')) {
        throw const GenAiFailure(GenAiFailureKind.transport);
      }
      return original(request);
    };
    var modelCalls = 0;
    install((request, _) {
      modelCalls++;
      if (modelCalls == 1) {
        return _answer(_search('failed', 'public info', request));
      }
      expect(request.prompt, contains('service_unavailable'));
      return _answer('Search failed; no external information was verified.');
    });
    workspace.setAgentEnabled(true);
    workspace.setNetSearch(true);
    await workspace.send('search fails');
    expect(modelCalls, 2);
    expect(workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(
      workspace.turns.single.agentEvents['failed']?.result?['ok'],
      isFalse,
    );
    expect(workspace.turns.single.citations, isEmpty);
    expect(workspace.turns.single.isSearching, isFalse);
  });

  test('disabled search is neither advertised nor executable', () async {
    var calls = 0;
    install((request, _) {
      final catalog = request.history.first.content.split('AVAILABLE_TOOLS:').last;
      expect(catalog, isNot(contains('web_search')));
      calls++;
      if (calls == 1) {
        return _answer(_search('forbidden', 'public info', request));
      }
      expect(request.prompt, contains('unknown_tool'));
      return _answer('Search is disabled.');
    });
    workspace.setAgentEnabled(true);
    await workspace.send('Find public information');
    expect(
      transport.requests.where((r) => r.uri.path.endsWith('/net/search')),
      isEmpty,
    );
    expect(workspace.turns.single.agentEvents, isEmpty);
    expect(workspace.turns.single.answer, 'Search is disabled.');
  });

  test('normal chat notifications cannot overwrite an active agent turn', () async {
    final gate = Completer<void>();
    install((_, cancellation) async* {
      await cancellation.race(gate.future);
      yield* _answer('agent final');
    });
    workspace.setAgentEnabled(true);
    final send = workspace.send('agent question');
    await _until(() => workspace.sending);
    await chat.send(
      GenAiChatRequest(
        chatGroupId: 'unrelated',
        prompt: 'unrelated',
        aiType: 'free',
        rootAiType: 'fixture',
      ),
    );
    expect(workspace.turns.single.answer, isEmpty);
    gate.complete();
    await send;
    expect(workspace.turns.single.answer, 'agent final');
  });

  for (final action in ['scope', 'new', 'exit', 'disconnect']) {
    test('$action cancels pending approval before dispatch', () async {
      var executed = 0;
      install(
        (request, _) => _answer(_call('mutation', request)),
        approval: true,
        execute: () async {
          executed++;
          return 'done';
        },
      );
      workspace.setAgentEnabled(true);
      final send = workspace.send('perform action');
      await _until(() => workspace.pendingAgentApproval != null);
      switch (action) {
        case 'scope':
          scope.value++;
        case 'new':
          workspace.newConversation();
        case 'exit':
          workspace.cancelAgentForPageExit();
        case 'disconnect':
          await workspace.disconnect();
      }
      workspace.resolveAgentApproval(true);
      await send;
      expect(executed, 0);
      expect(workspace.pendingAgentApproval, isNull);
      expect(workspace.sending, isFalse);
      if (action == 'exit') {
        expect(workspace.turns.single.phase, GenAiChatPhase.cancelled);
      } else {
        expect(workspace.turns, isEmpty);
      }
    });
  }

  for (final action in ['stop', 'new', 'scope']) {
    test('$action clears agent compaction progress before a new request', () async {
      const pendingUsage = GenAiContextUsage(
        stage: GenAiContextStage.compacting,
        estimatedInputUnits: 12000,
        allowedInputUnits: 18000,
        originalInputUnits: 12000,
        totalChunks: 3,
      );
      const readyUsage = GenAiContextUsage(
        stage: GenAiContextStage.ready,
        estimatedInputUnits: 300,
        allowedInputUnits: 18000,
        originalInputUnits: 300,
      );
      final release = Completer<void>();
      install((request, _) async* {
        if (request.prompt == 'old') {
          yield const GenAiContextUsageChanged(pendingUsage);
          // Deliberately finish after cancellation to exercise stale progress.
          await release.future;
          yield const GenAiContextUsageChanged(pendingUsage);
        } else {
          yield const GenAiContextUsageChanged(readyUsage);
        }
        yield* _answer('done');
      });
      workspace.setAgentEnabled(true);
      final old = workspace.send('old');
      await _until(() => workspace.contextUsage == pendingUsage);
      switch (action) {
        case 'stop':
          workspace.stop();
        case 'new':
          workspace.newConversation();
        case 'scope':
          scope.value++;
      }
      expect(workspace.contextUsage, isNull);
      await old;
      await workspace.send('next');
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(workspace.contextUsage, readyUsage);
      expect(workspace.turns.last.answer, 'done');
      expect(workspace.turns.last.phase, GenAiChatPhase.completed);
    });
  }

  test('stop and immediate followup retain unknown outcome and reuse ledger', () async {
    var executed = 0;
    final dispatched = Completer<void>();
    final release = Completer<Object?>();
    final requests = <GenAiChatRequest>[];
    install(
      (request, _) {
        requests.add(request);
        return _answer(
          requests.length <= 2 ? _call('mutation-${requests.length}', request) : 'checked',
        );
      },
      approval: true,
      execute: () {
        executed++;
        dispatched.complete();
        return release.future;
      },
    );
    workspace.setAgentEnabled(true);
    final first = workspace.send('perform action');
    await _until(() => workspace.pendingAgentApproval != null);
    workspace.resolveAgentApproval(true);
    await dispatched.future;
    workspace.stop();
    final followup = workspace.send('continue');
    await first;
    await followup;
    expect(executed, 1);
    expect(workspace.pendingAgentApproval, isNull);
    expect(
      requests[1].history.any((m) => m.content.contains('outcome_unknown')),
      isTrue,
    );
    expect(
      requests[1].history.map((m) => m.content),
      contains('perform action'),
    );
    expect(workspace.turns.last.answer, 'checked');
    release.complete('late success');
    await Future<void>.delayed(Duration.zero);
    expect(workspace.turns.last.answer, 'checked');
  });

  test('agent retry exposes search without forcing a search', () async {
    var calls = 0;
    install((_, __) {
      calls++;
      return _answer('agent $calls');
    });
    workspace.setAgentEnabled(true);
    await workspace.send('question');
    workspace.setNetSearch(true);
    await workspace.retryTurn(0);
    expect(workspace.turns.single.isAgent, isTrue);
    expect(workspace.turns.single.isSearching, isFalse);
    expect(workspace.turns.single.answer, 'agent 2');
    expect(
      transport.requests.where((r) => r.uri.path.endsWith('/search')),
      isEmpty,
    );
  });

  test('agent timeout becomes a failed turn instead of a stuck spinner', () async {
    final pending = StreamController<GenAiChatEvent>();
    addTearDown(pending.close);
    install(
      (_, __) => pending.stream,
      limits: const GenAiAgentLimits(runTimeout: Duration(milliseconds: 10)),
    );
    workspace.setAgentEnabled(true);
    await workspace.send('slow request');
    expect(workspace.turns.single.phase, GenAiChatPhase.failed);
    expect(workspace.turns.single.failure?.kind, GenAiFailureKind.timeout);
    expect(workspace.sending, isFalse);
  });

  test('typed sessions reopen across controller restart with title, tools and mode', () async {
    final requests = <GenAiChatRequest>[];
    install((request, _) {
      requests.add(request);
      return _answer(
        requests.length == 1 ? _call('read', request) : 'tool answer',
      );
    });
    workspace.setAgentEnabled(true);
    await workspace.send('original user question');
    final id = workspace.groupId;
    await workspace.renameConversation(id, 'My campus session');
    final before = await workspace.conversationForExport(id, GenAiCancellation());
    workspace.newConversation();
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.title, 'My campus session');
    expect(workspace.turns.single.prompt, 'original user question');
    expect(workspace.turns.single.agentEvents['read']!.result!['ok'], isTrue);
    expect(workspace.agentEnabled, isTrue);
    expect(
      transport.requests.where((r) => r.uri.path.endsWith('/getByChatGroupId')),
      isEmpty,
    );
    workspace.dispose();
    final repository = GenAiRepository(
      api: GenAiApiClient(transport: transport),
      sessions: sessions,
    );
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
      conversationStore: archives,
    );
    await workspace.reloadModels();
    install((request, _) {
      requests.add(request);
      return _answer('continued');
    });
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.pendingAgentApproval, isNull);
    expect(workspace.sending, isFalse);
    expect(workspace.turns.single.isAgent, isTrue);
    expect(workspace.selectedModel?.aiType, before.modelAiType);
    await workspace.send('continue');
    expect(
      requests.last.history.any((m) => m.content.contains('techpie-agent-history')),
      isTrue,
    );
    expect(
      requests.last.history.map((m) => m.content),
      contains('original user question'),
    );
    expect(
      (await workspace.listConversations(GenAiCancellation())).records.single.title,
      'My campus session',
    );
  });

  test('durable approved result survives restart without another action or approval', () async {
    var executed = 0;
    var modelTurns = 0;
    install(
      (request, _) => _answer((++modelTurns).isEven ? 'done' : _call('action', request)),
      approval: true,
      execute: () async {
        executed++;
        return {'url': 'https://example.test/generated.png'};
      },
    );
    workspace.setAgentEnabled(true);
    final send = workspace.send('generate');
    await _until(() => workspace.pendingAgentApproval != null);
    workspace.resolveAgentApproval(true);
    await send;
    final id = workspace.groupId;
    await workspace.flushConversations();
    final checkpoint = archives.writes.map((pair) => pair.$2).firstWhere(
          (record) => (record.mutations['effects']! as Map)
              .values
              .any((value) => (value as Map)['ok'] == true),
        );
    expect(
      checkpoint.restoreTurns().single.agentEvents['action']!.result!['ok'],
      isTrue,
    );
    expect(checkpoint.restoreTurns().single.phase, GenAiChatPhase.cancelled);
    workspace.dispose();
    final repository = GenAiRepository(
      api: GenAiApiClient(transport: transport),
      sessions: sessions,
    );
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
      conversationStore: archives,
    );
    await workspace.reloadModels();
    modelTurns = 0;
    install(
      (request, _) => _answer(
        (++modelTurns).isEven ? 'already done' : _call('retry-action', request),
      ),
      approval: true,
      execute: () async {
        executed++;
        return 'unexpected';
      },
    );
    await workspace.openConversation(id, GenAiCancellation());
    await workspace.send('generate again');
    expect(executed, 1);
    expect(workspace.pendingAgentApproval, isNull);
    expect(workspace.turns.last.answer, 'already done');
  });

  test('pending approval archives restore cancelled and need fresh approval', () async {
    var executions = 0;
    install(
      (request, _) => _answer(_call('pending', request)),
      approval: true,
      execute: () async {
        executions++;
        return 'done';
      },
    );
    workspace.setAgentEnabled(true);
    final send = workspace.send('pending action');
    await _until(() => workspace.pendingAgentApproval != null);
    final id = workspace.groupId;
    final oldApproval = workspace.pendingAgentApproval!;
    await workspace.flushConversations();
    workspace.newConversation();
    await send;
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.pendingAgentApproval, isNull);
    expect(workspace.turns.single.phase, GenAiChatPhase.cancelled);
    expect(executions, 0);
    final retry = workspace.send('try now');
    await _until(() => workspace.pendingAgentApproval != null);
    final currentApproval = workspace.pendingAgentApproval;
    workspace.resolveAgentApproval(true, expected: oldApproval);
    expect(workspace.pendingAgentApproval, same(currentApproval));
    expect(executions, 0);
    workspace.stop();
    await retry;
    expect(executions, 0);
  });

  test('durable checkpoint failure blocks mutation dispatch and exposes storage error', () async {
    var executions = 0;
    install(
      (request, _) => _answer(_call('action', request)),
      approval: true,
      execute: () async {
        executions++;
        return 'unexpected';
      },
    );
    workspace.setAgentEnabled(true);
    final send = workspace.send('action');
    await _until(() => workspace.pendingAgentApproval != null);
    archives.failWrites = true;
    workspace.resolveAgentApproval(true);
    await send;
    expect(executions, 0);
    expect(workspace.turns.single.failure?.kind, GenAiFailureKind.storage);
    expect(workspace.archiveFailure?.kind, GenAiFailureKind.storage);
    expect(workspace.pendingAgentApproval, isNull);
  });

  test('late archive open cannot replace a new chat and scopes isolate history', () async {
    install((_, __) => _answer('done'));
    await workspace.send('private');
    final id = workspace.groupId;
    await workspace.flushConversations();
    workspace.newConversation();
    archives.readGate = Completer<void>();
    archives.readStarted = Completer<void>();
    final open = workspace.openConversation(id, GenAiCancellation());
    await archives.readStarted!.future;
    workspace.newConversation();
    final next = workspace.groupId;
    archives.readGate!.complete();
    expect(await open, isFalse);
    archives.readGate = null;
    expect(workspace.groupId, next);
    expect(workspace.turns, isEmpty);
    scope.value++;
    expect(
      (await workspace.listConversations(GenAiCancellation())).records,
      isEmpty,
    );
    scope.value--;
    expect(
      (await workspace.listConversations(GenAiCancellation())).records.single.id,
      id,
    );
  });

  test('successful deletion prevents old writers and stale opens resurrecting session', () async {
    install((_, __) => _answer('done'));
    await workspace.send('remove me');
    final id = workspace.groupId;
    await workspace.flushConversations();
    final old = archives.writes.last;
    await workspace.deleteConversation(id, GenAiCancellation());
    await archives.write(old.$1, old.$2);
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.turns, isEmpty);
    expect(
      (await workspace.listConversations(GenAiCancellation())).records,
      isEmpty,
    );
    expect(await archives.read(old.$1, id), isNull);
  });

  test('failed remote deletion retains local session for recovery', () async {
    install((_, __) => _answer('done'));
    await workspace.send('keep on failure');
    final id = workspace.groupId;
    await workspace.flushConversations();
    final original = transport.handle;
    transport.handle = (request) {
      if (request.uri.path.endsWith('/delete/groupId')) {
        throw const GenAiFailure(GenAiFailureKind.rejected, statusCode: 403);
      }
      return original(request);
    };
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    final kept = await workspace.conversationForExport(id, GenAiCancellation());
    expect(kept.restoreTurns().single.prompt, 'keep on failure');
  });

  test('storage recovery retries failed saves and local history remains available offline',
      () async {
    install((_, __) => _answer('done'));
    await workspace.send('survives outage');
    final id = workspace.groupId;
    archives.failWrites = true;
    workspace.setThinking(true);
    await expectLater(
      workspace.flushConversations(),
      throwsA(isA<GenAiFailure>()),
    );
    expect(workspace.archiveFailure, isNotNull);
    archives.failWrites = false;
    await workspace.retrySaveConversations();
    expect(workspace.archiveFailure, isNull);
    workspace.newConversation();
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.turns.single.prompt, 'survives outage');
    final original = transport.handle;
    transport.handle = (request) {
      if (request.uri.path.endsWith('/listByContentGroup')) {
        throw const GenAiFailure(GenAiFailureKind.transport);
      }
      return original(request);
    };
    expect(
      (await workspace.listConversations(GenAiCancellation())).records.single.id,
      id,
    );
  });

  test('account switch while save is queued cannot send deletion through the new account',
      () async {
    install((_, __) => _answer('done'));
    await workspace.send('old account session');
    final id = workspace.groupId;
    archives.writeGate = Completer<void>();
    archives.writeStarted = Completer<void>();
    workspace.setThinking(true);
    final flush = workspace.flushConversations();
    await archives.writeStarted!.future;
    final old = archives.writes.last;
    final deletion = workspace.deleteConversation(id, GenAiCancellation());
    final rejected = expectLater(
      deletion,
      throwsA(
        isA<GenAiFailure>().having(
          (failure) => failure.kind,
          'kind',
          GenAiFailureKind.accountChanged,
        ),
      ),
    );
    scope.value++;
    archives.writeGate!.complete();
    await flush;
    await rejected;
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      isEmpty,
    );
    expect(await archives.read(old.$1, id), isNotNull);
  });

  for (final action in ['export', 'rename']) {
    test('$action cannot fetch server history after a binding switch during local read', () async {
      install((_, __) => _answer('done'));
      archives.readGate = Completer<void>();
      archives.readStarted = Completer<void>();
      final future = action == 'export'
          ? workspace.conversationForExport('remote-id', GenAiCancellation())
          : workspace.renameConversation('remote-id', 'title');
      final rejected = expectLater(
        future,
        throwsA(
          isA<GenAiFailure>().having(
            (failure) => failure.kind,
            'kind',
            GenAiFailureKind.accountChanged,
          ),
        ),
      );
      await archives.readStarted!.future;
      scope.value++;
      archives.readGate!.complete();
      await rejected;
      expect(
        transport.requests.where(
          (request) => request.uri.path.endsWith('/getByChatGroupId'),
        ),
        isEmpty,
      );
    });
  }

  test('failed older save cannot retry over a newer successful archive', () async {
    install((_, __) => _answer('done'));
    await workspace.send('first');
    final id = workspace.groupId;
    archives.writeGate = Completer<void>();
    archives.writeStarted = Completer<void>();
    archives.failNextWriteAfterGate = true;
    workspace.setThinking(true);
    final firstSave = workspace.flushConversations().catchError((Object _) {});
    await archives.writeStarted!.future;
    final secondSend = workspace.send('second');
    await _until(() => workspace.turns.length == 2 && !workspace.sending);
    final nextSave = workspace.flushConversations();
    archives.writeGate!.complete();
    await firstSave;
    await secondSend;
    await nextSave;
    await workspace.flushConversations();
    await workspace.openConversation(id, GenAiCancellation());
    expect(workspace.turns.map((turn) => turn.prompt), ['first', 'second']);
    expect(workspace.archiveFailure, isNull);
  });

  test('rename waiting on storage preserves a later durable action receipt', () async {
    var calls = 0;
    install(
      (request, _) => _answer(
        ++calls == 1 ? _call('rename-action', request) : 'generated',
      ),
      approval: true,
    );
    await workspace.send('normal first');
    final id = workspace.groupId;
    await workspace.flushConversations();
    archives.deletedGate = Completer<void>();
    archives.deletedStarted = Completer<void>();
    final rename = workspace.renameConversation(id, 'renamed safely');
    await archives.deletedStarted!.future;
    workspace.setAgentEnabled(true);
    final send = workspace.send('generate');
    await _until(() => workspace.pendingAgentApproval != null);
    workspace.resolveAgentApproval(true);
    await send;
    final checkpointIndex = archives.writes.lastIndexWhere(
      (pair) => (pair.$2.mutations['effects']! as Map)
          .values
          .any((value) => (value as Map)['ok'] == true),
    );
    expect(checkpointIndex, greaterThanOrEqualTo(0));
    archives.deletedGate!.complete();
    await rename;
    await workspace.flushConversations();
    for (final pair in archives.writes.skip(checkpointIndex)) {
      expect(
        (pair.$2.mutations['effects']! as Map).values.any((value) => (value as Map)['ok'] == true),
        isTrue,
      );
    }
    expect(workspace.title, 'renamed safely');
    expect(workspace.turns, hasLength(2));
  });

  test('deleting current session rotates group before another message can be sent', () async {
    install((_, __) => _answer('done'));
    await workspace.send('delete this session');
    final oldId = workspace.groupId;
    final original = transport.handle;
    final deleteStarted = Completer<void>();
    final releaseDelete = Completer<void>();
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/delete/groupId')) {
        deleteStarted.complete();
        await releaseDelete.future;
      }
      return original(request);
    };
    final deletion = workspace.deleteConversation(oldId, GenAiCancellation());
    await deleteStarted.future;
    final nextId = workspace.groupId;
    expect(nextId, isNot(oldId));
    await workspace.send('keep this new message');
    releaseDelete.complete();
    await deletion;
    expect(workspace.groupId, nextId);
    expect(workspace.turns.single.prompt, 'keep this new message');
    final posts = transport.requests.where((request) => request.method == 'POST').toList();
    expect(jsonDecode(posts.last.body!)['chatGroupId'], nextId);
    expect(
      (await workspace.listConversations(GenAiCancellation())).records.single.id,
      nextId,
    );
  });

  test('slow server listing cannot return a concurrently deleted local session', () async {
    install((_, __) => _answer('done'));
    await workspace.send('old list entry');
    final id = workspace.groupId;
    final original = transport.handle;
    final listStarted = Completer<void>();
    final releaseList = Completer<void>();
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/listByContentGroup')) {
        listStarted.complete();
        await releaseList.future;
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'records': [
                {'chatGroupId': id, 'question': 'stale remote title'},
              ],
              'total': 1,
            },
          },
        );
      }
      return original(request);
    };
    final listing = workspace.listConversations(GenAiCancellation());
    await listStarted.future;
    await workspace.deleteConversation(id, GenAiCancellation());
    releaseList.complete();
    expect((await listing).records, isEmpty);
  });

  test('slow server listing uses the latest local rename instead of stale metadata', () async {
    install((_, __) => _answer('done'));
    await workspace.send('original title');
    final id = workspace.groupId;
    final original = transport.handle;
    final listStarted = Completer<void>();
    final releaseList = Completer<void>();
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/listByContentGroup')) {
        listStarted.complete();
        await releaseList.future;
      }
      return original(request);
    };
    final listing = workspace.listConversations(GenAiCancellation());
    await listStarted.future;
    await workspace.renameConversation(id, 'updated local title');
    releaseList.complete();
    expect((await listing).records.single.title, 'updated local title');
  });

  test('confirmed remote deletion retries only failed local cleanup', () async {
    install((_, __) => _answer('done'));
    await workspace.send('delete with local failure');
    final id = workspace.groupId;
    archives.failDeletes = true;
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    expect(workspace.groupId, isNot(id));
    expect(workspace.turns, isEmpty);
    expect(workspace.archiveFailure?.kind, GenAiFailureKind.storage);
    await workspace.send('new session remains usable');
    archives.failDeletes = false;
    await workspace.retrySaveConversations();
    expect(workspace.archiveFailure, isNull);
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      hasLength(1),
    );
    expect(
      (await workspace.listConversations(GenAiCancellation())).records.single.id,
      workspace.groupId,
    );
    expect(await workspace.openConversation(id, GenAiCancellation()), isFalse);
    expect(workspace.turns.single.prompt, 'new session remains usable');
  });

  test('failed current-session deletion restores the latest unsaved settings in archive', () async {
    install((_, __) => _answer('done'));
    await workspace.send('recover latest settings');
    final id = workspace.groupId;
    workspace.setThinking(true);
    final original = transport.handle;
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/delete/groupId')) {
        throw const GenAiFailure(GenAiFailureKind.rejected, statusCode: 403);
      }
      return original(request);
    };
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    expect(workspace.groupId, isNot(id));
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    expect(workspace.thinkingEnabled, isTrue);
    expect(workspace.turns.single.prompt, 'recover latest settings');
  });

  test(
      'ambiguous deletion survives restart and explicit read-only reconciliation restores existing history',
      () async {
    install((_, __) => _answer('done'));
    await workspace.send('uncertain delete');
    final id = workspace.groupId;
    final original = transport.handle;
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/delete/groupId')) {
        throw const GenAiFailure(GenAiFailureKind.transport);
      }
      if (request.uri.path.endsWith('/getByChatGroupId')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': [
              {
                'question': 'uncertain delete',
                'answer': 'normal answer',
                'aiType': 'free',
              }
            ],
          },
        );
      }
      return original(request);
    };
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    expect(workspace.uncertainDeletionCount, 1);
    workspace.dispose();
    final repository = GenAiRepository(
      api: GenAiApiClient(transport: transport),
      sessions: sessions,
    );
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
      conversationStore: archives,
    );
    await workspace.reloadModels();
    install((_, __) => _answer('done'));
    expect(
      (await workspace.listConversations(GenAiCancellation())).records,
      isEmpty,
    );
    expect(workspace.uncertainDeletionCount, 1);
    await workspace.retrySaveConversations();
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      hasLength(1),
    );
    await workspace.reconcilePendingDeletions(GenAiCancellation());
    expect(workspace.uncertainDeletionCount, 0);
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    expect(workspace.turns.single.prompt, 'uncertain delete');
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      hasLength(1),
    );
  });

  test('read-only reconciliation finalizes absence without repeating remote deletion', () async {
    install((_, __) => _answer('done'));
    await workspace.send('already deleted remotely');
    final id = workspace.groupId;
    final original = transport.handle;
    transport.handle = (request) async {
      if (request.uri.path.endsWith('/delete/groupId')) {
        throw const GenAiFailure(GenAiFailureKind.timeout);
      }
      if (request.uri.path.endsWith('/getByChatGroupId')) {
        return response(
          json: {'success': true, 'code': 200, 'result': <Object?>[]},
        );
      }
      return original(request);
    };
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    await workspace.reconcilePendingDeletions(GenAiCancellation());
    expect(workspace.uncertainDeletionCount, 0);
    expect(await workspace.openConversation(id, GenAiCancellation()), isFalse);
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      hasLength(1),
    );
  });

  test('failed durable deletion intent prevents remote DELETE dispatch', () async {
    install((_, __) => _answer('done'));
    await workspace.send('keep when journal unavailable');
    final id = workspace.groupId;
    archives.failBeginDeletion = true;
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      isEmpty,
    );
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    expect(workspace.turns.single.prompt, 'keep when journal unavailable');
  });

  test('partially persisted deletion intent rolls back before any remote effect', () async {
    install((_, __) => _answer('done'));
    await workspace.send('keep after journal partial failure');
    final id = workspace.groupId;
    final storageScope = archives.writes.last.$1;
    archives.failAfterBeginDeletion = true;
    await expectLater(
      workspace.deleteConversation(id, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    expect(
      transport.requests.where((request) => request.uri.path.endsWith('/delete/groupId')),
      isEmpty,
    );
    expect(await archives.pendingDeletionIds(storageScope), isEmpty);
    expect(workspace.uncertainDeletionCount, 0);
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    expect(workspace.turns.single.prompt, 'keep after journal partial failure');
  });

  test('new conversation cancels stale upload and no longer blocks the next send', () async {
    install((_, __) => _answer('agent answer'));
    final original = transport.handle;
    final uploadStarted = Completer<void>();
    final gate = Completer<void>();
    transport.handle = (request) async {
      if (request.uri.path == '/sys/common/upload') {
        uploadStarted.complete();
        await request.cancellation.race(gate.future);
      }
      return original(request);
    };
    final upload = workspace.addImageAttachment('stale.png', [1]);
    await uploadStarted.future;
    workspace.newConversation();
    expect(workspace.hasPendingUploads, isFalse);
    expect(workspace.attachments, isEmpty);
    workspace.setAgentEnabled(true);
    expect(workspace.agentEnabled, isTrue);
    await workspace.send('new conversation proceeds');
    await upload;
    expect(workspace.turns.single.answer, 'agent answer');
    gate.complete();
  });

  test('history gap blocks retry and resets both chat and agent context', () async {
    final requests = <GenAiChatRequest>[];
    install((request, _) {
      requests.add(request);
      return _answer('agent answer');
    });
    await workspace.send('seed');
    final pair = archives.writes.last;
    final id = workspace.groupId;
    final snapshot = GenAiConversationArchive(
      id: id,
      title: 'gap',
      updatedAt: DateTime.now(),
      turns: [
        GenAiConversationTurn('before gap')
          ..attachedFileIds = ['stale-document']
          ..attachedFileContents = {'stale-document': 'old source'}
          ..answer = 'old answer'
          ..phase = GenAiChatPhase.completed,
        GenAiConversationTurn('missing record', isHistoryGap: true)
          ..phase = GenAiChatPhase.interrupted,
        GenAiConversationTurn('after gap')
          ..attachedFileIds = ['current-document']
          ..attachedFileContents = {'current-document': 'new source'}
          ..answer = 'new answer'
          ..phase = GenAiChatPhase.completed,
      ],
      agentEnabled: false,
      netSearchEnabled: false,
      thinkingEnabled: false,
      modelAiType: 'free',
      modelRootAiType: 'fixture',
      mutations: const {'version': 1, 'effects': <String, Object?>{}},
    );
    workspace.newConversation();
    await workspace.flushConversations();
    await archives.write(pair.$1, snapshot);
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    final before = transport.requests.length;
    await workspace.retryTurn(1);
    expect(transport.requests.length, before);
    expect(workspace.turns, hasLength(3));
    await workspace.send('normal followup');
    final messages = jsonDecode(transport.requests.last.body!)['messages'] as List;
    expect(messages.toString(), isNot(contains('before gap')));
    expect(messages.toString(), contains('after gap'));
    expect(
      jsonDecode(transport.requests.last.body!)['fileIds'],
      ['current-document'],
    );
    workspace.setAgentEnabled(true);
    await workspace.send('agent followup');
    expect(requests.last.fileIds, ['current-document']);
    expect(
      requests.last.history.map((message) => message.content),
      isNot(contains('before gap')),
    );
    expect(
      requests.last.history.map((message) => message.content),
      contains('after gap'),
    );
  });
}
