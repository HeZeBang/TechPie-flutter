import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/application/genai_conversation_store.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_context_record.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';

import '../support/fakes.dart';

const policy = GenAiContextPolicy(
  contextTokens: 40000,
  latestTokens: 5000,
  safetyTokens: 2000,
  outputTokens: 2048,
  triggerTokens: 16000,
  targetTokens: 13000,
  summaryChunkTokens: 7000,
  memoryTokens: 4000,
  recentMessages: 4,
);

void main() {
  test('ordinary and agent chat share bounded context and restore full archives plus checkpoints',
      () async {
    var summaryCalls = 0;
    final summaryRelease = Completer<void>();
    final compacting = Completer<void>();
    var toolExecutions = 0;
    var oversizedReceipt = false;
    final cleanupIds = <String>[];
    final normalRequests = <Map<String, dynamic>>[];
    final transport = ScriptedTransport((r) async {
      if (r.uri.path.endsWith('/delete/groupId')) {
        cleanupIds.add(r.uri.queryParameters['id']!);
        return response(json: {'success': true, 'code': 200});
      }
      if (r.uri.path.endsWith('/list')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'records': [
                {
                  'aiName': 'Kimi',
                  'aiType': 'Kimi-k3',
                  'rootAiType': 'xinference',
                  'payType': 'FREE',
                }
              ],
            },
          },
        );
      }
      if (r.method != 'POST') return profileResponse();
      final body = jsonDecode(r.body!) as Map<String, dynamic>;
      if (isGenAiContextExtraction(body['chatInfo'] as String)) {
        summaryCalls++;
        await r.cancellation.race(summaryRelease.future);
        expect(
          body['chatGroupId'],
          'long-history',
        );
        final records = jsonDecode(
          ((body['messages'] as List).last as Map)['content'] as String,
        ) as List;
        return response(
          type: 'text/event-stream',
          text: sseChunk(
            text: jsonEncode({
              'items': [
                for (final record in records.take(12))
                  {
                    'source': record['source'],
                    'kind': 'constraint',
                    'quote': (record['text'] as String).split('\n').first,
                  },
              ],
            }),
            finish: 'stop',
          ),
        );
      }
      normalRequests.add(body);
      if (body['chatInfo'] == 'agent followup') {
        final system = ((body['messages'] as List).first as Map)['content'] as String;
        final nonce = RegExp(r'CURRENT_CALL_NONCE: ([^\n]+)').firstMatch(system)!.group(1)!;
        return response(
          type: 'text/event-stream',
          text: sseChunk(
            text:
                '<techpie-agent-call version="2" nonce="$nonce">\n{"call_id":"read-1","name":"read_data","arguments":{}}\n</techpie-agent-call>',
            finish: 'stop',
          ),
        );
      }
      return response(
        type: 'text/event-stream',
        text: sseChunk(text: 'Verified answer.', finish: 'stop'),
      );
    });
    final api = GenAiApiClient(transport: transport);
    final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    addTearDown(sessions.dispose);
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'synthetic'));
    final store = MemoryGenAiConversationStore();
    final scope = jsonEncode([ownerA.storageId, null]);
    const id = 'long-history';
    final originalTurns = [
      for (var i = 0; i < 12; i++)
        GenAiConversationTurn(
          'Constraint $i: keep exact ID K-$i.\n${'historical input ' * 55}',
        )
          ..answer = 'Answer $i\n${'historical output ' * 55}'
          ..phase = GenAiChatPhase.completed,
    ];
    originalTurns.first.attachedFileIds = ['doc'];
    originalTurns.first.attachedFileContents = {'doc': 'Exact source: B-37'};
    await store.write(
      scope,
      GenAiConversationArchive(
        id: id,
        title: 'Long history',
        updatedAt: DateTime.now(),
        turns: originalTurns,
        agentEnabled: false,
        netSearchEnabled: false,
        thinkingEnabled: false,
        modelAiType: 'Kimi-k3',
        modelRootAiType: 'xinference',
        mutations: const {'version': 1, 'effects': <String, Object?>{}},
      ),
    );
    GenAiWorkspaceController makeWorkspace() {
      final repo = GenAiRepository(
        api: api,
        sessions: sessions,
        contextCompactor: GenAiContextCompactor(policy: policy),
      );
      final chat = GenAiChatService(repo);
      addTearDown(chat.dispose);
      final workspace = GenAiWorkspaceController(
        sessions: sessions,
        repository: repo,
        chat: chat,
        conversationStore: store,
      );
      workspace.configureAgent(
        runner: GenAiAgentRunner(
          streamChat: repo.streamChat,
          tools: GenAiAgentToolRegistry([
            GenAiAgentTool(
              name: 'read_data',
              description: 'Read synthetic data',
              parameters: const {
                'type': 'object',
                'properties': <String, Object?>{},
                'additionalProperties': false,
              },
              prepare: (_, context) async => GenAiAgentPreparedTool(
                execute: () async {
                  context.checkActive();
                  toolExecutions++;
                  return oversizedReceipt ? {'body': '课' * 1900} : {'value': 42};
                },
              ),
            ),
          ]),
        ),
      );
      return workspace;
    }

    final workspace = makeWorkspace();
    await workspace.reloadModels();
    expect(await workspace.openConversation(id, GenAiCancellation()), isTrue);
    final updates = <GenAiContextUsage>[];
    workspace.addListener(() {
      final usage = workspace.contextUsage;
      if (usage == null) return;
      updates.add(usage);
      if (usage.stage == GenAiContextStage.compacting && !compacting.isCompleted) {
        compacting.complete();
      }
    });
    final normal = workspace.send('normal followup');
    await compacting.future;
    expect(normalRequests, isEmpty);
    expect(workspace.contextUsage!.completedChunks, 0);
    summaryRelease.complete();
    await normal;
    expect(workspace.contextUsage!.stage, GenAiContextStage.ready);
    expect(workspace.contextUsage!.compacted, isTrue);
    expect(workspace.turns.last.phase, GenAiChatPhase.completed);
    expect(workspace.turns.last.contextCompacted, isTrue);
    expect(workspace.turns.length, 13);
    expect(workspace.turns.first.prompt, originalTurns.first.prompt);
    expect(summaryCalls, greaterThan(0));
    expect(
      cleanupIds,
      isEmpty,
      reason: 'Compaction cannot delete the original remote chat',
    );
    workspace.setAgentEnabled(true);
    updates.clear();
    await workspace.send('agent followup');
    expect(
      updates.any((value) => value.stage == GenAiContextStage.compacting),
      isTrue,
    );
    expect(workspace.contextUsage!.stage, GenAiContextStage.ready);
    expect(workspace.contextUsage!.compacted, isTrue);
    expect(workspace.turns.last.phase, GenAiChatPhase.completed);
    expect(workspace.turns.last.contextCompacted, isTrue);
    expect(toolExecutions, 1);
    await workspace.flushConversations();
    final saved = (await store.read(scope, id))!;
    expect(saved.contextMemory, isNotEmpty);
    expect(
      saved.restoreTurns().first.attachedFileContents,
      {'doc': 'Exact source: B-37'},
    );
    expect(
      saved.restoreTurns().map((turn) => turn.prompt).join(),
      contains(originalTurns[4].prompt),
    );
    workspace.dispose();
    final reopened = makeWorkspace();
    addTearDown(reopened.dispose);
    await reopened.reloadModels();
    expect(await reopened.openConversation(id, GenAiCancellation()), isTrue);
    expect(reopened.turns.length, 14);
    expect(reopened.turns.last.contextCompacted, isTrue);
    expect(
      reopened.contextUsage,
      isNull,
      reason: 'Archived turns cannot restore ephemeral live progress',
    );
    await reopened.send('continue after reopening');
    expect(reopened.turns.last.phase, GenAiChatPhase.completed);
    expect(toolExecutions, 1, reason: 'Restored tool history is inert');
    for (final body in normalRequests) {
      expect(body['fileIds'], ['doc']);
      expect(
        jsonEncode(body['messages']),
        contains('techpie_context_memory_v1'),
      );
      expect((body['messages'] as List).length, lessThan(24));
    }

    // A receipt fits the runner's character cap but exceeds chatInfo's byte
    // budget. Never hide it in transient messages and lose remote provenance.
    oversizedReceipt = true;
    final before = normalRequests.length;
    await reopened.send('agent followup');
    expect(
      normalRequests.length,
      before + 1,
      reason: 'The tool continuation must fail before its POST',
    );
    expect(reopened.turns.last.failure?.kind, GenAiFailureKind.messageTooLarge);
    expect(toolExecutions, 2);
    await reopened.flushConversations();
    final failed = (await store.read(scope, id))!.restoreTurns().last;
    expect(failed.agentEvents['read-1']!.result!['ok'], isTrue);
    expect(
      (failed.agentEvents['read-1']!.result!['result']! as Map)['body'],
      '课' * 1900,
    );
    expect(failed.agentTranscript.last.result, isNotNull);
  });

  test('fresh instances recover source receipts and skip same-chat compaction and repair rows',
      () async {
    const nonce = 'remoteProtocolNonce123';
    final receipt = {
      'call_id': 'read-099',
      'name': 'read_data',
      'ok': true,
      'result': {'record': 'off-2-099', 'sample': 688, 'temperature': 18},
    };
    final remote = <Map<String, Object?>>[
      for (var i = 0; i < 12; i++)
        {
          'question': 'Original user record $i. ${'source detail ' * 100}',
          'answer': 'Historical answer $i. ${'generated prose ' * 25}',
          'aiType': 'Kimi-k3',
        },
      {
        'question': 'Read record off-2-099.',
        'answer': '<|open|>tools<|sep|><|open|>call tool=read_data',
      },
      {
        'question': encodeGenAiAgentResult(
          {
            'call_id': null,
            'name': null,
            'ok': false,
            'error': {
              'code': 'unsupported_tool_format',
              'message': 'Repair only; no tool executed',
            },
          },
          nonce: nonce,
        ),
        'answer': encodeGenAiAgentCall(
          GenAiAgentToolCall(
            id: 'read-099',
            name: 'read_data',
            arguments: const {},
          ),
          nonce: nonce,
        ),
      },
      {
        'question': genAiContextExtractionPrompt('a' * 64),
        'answer': '{"items":[]}',
      },
      {
        'question': encodeGenAiAgentResult(receipt, nonce: nonce),
        'answer': 'The sample is 696.',
      },
    ];
    var deletions = 0;
    final actual = <Map<String, dynamic>>[];
    final transport = ScriptedTransport((r) async {
      if (r.uri.path.endsWith('/delete/groupId')) {
        deletions++;
        return response(json: {'success': true, 'code': 200});
      }
      if (r.uri.path.endsWith('/getByChatGroupId')) {
        return response(
          json: {'success': true, 'code': 200, 'result': remote.toList()},
        );
      }
      if (r.uri.path.endsWith('/listByContentGroup')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': [
              {
                'chatGroupId': 'remote-only',
                'question': remote.last['question'],
              },
              {
                'chatGroupId': 'tpctx-${'a' * 24}',
                'question': 'old extraction',
              },
            ],
          },
        );
      }
      if (r.uri.path.endsWith('/list')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {
              'records': [
                {
                  'aiName': 'Kimi',
                  'aiType': 'Kimi-k3',
                  'rootAiType': 'xinference',
                  'payType': 'FREE',
                },
              ],
            },
          },
        );
      }
      if (r.method != 'POST') return profileResponse();
      final body = jsonDecode(r.body!) as Map<String, dynamic>;
      expect(body['chatGroupId'], 'remote-only');
      final messages = body['messages'] as List;
      String answer;
      if (isGenAiContextExtraction(body['chatInfo'] as String)) {
        final records = jsonDecode((messages.last as Map)['content'] as String) as List;
        answer = jsonEncode({
          'items': [
            for (final dynamic record in records.take(12))
              {
                'source': (record as Map)['source'],
                'kind': 'fact',
                'quote': (record['text'] as String).split('.').first,
              },
          ],
        });
      } else {
        actual.add(body);
        final text = jsonEncode(messages);
        expect(text, contains('read-099'));
        expect(text, contains('688'));
        expect(text, contains('techpie_previous_answer_v1'));
        expect(text, contains('techpie_context_memory_v1'));
        answer = 'sample 688; temperature 18';
      }
      remote.add({
        'question': body['chatInfo'],
        'answer': answer,
        'aiType': 'Kimi-k3',
      });
      return response(
        type: 'text/event-stream',
        text: sseChunk(text: answer, finish: 'stop'),
      );
    });
    for (final tools in [false, true]) {
      final api = GenAiApiClient(transport: transport);
      final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
      await sessions.setOwner(ownerA);
      await sessions.connect(const GenAiCredential(token: 'synthetic'));
      final repo = GenAiRepository(
        api: api,
        sessions: sessions,
        contextCompactor: GenAiContextCompactor(policy: policy),
      );
      final chat = GenAiChatService(repo);
      final workspace = GenAiWorkspaceController(
        sessions: sessions,
        repository: repo,
        chat: chat,
        conversationStore: MemoryGenAiConversationStore(),
      );
      workspace.configureAgent(
        runner: GenAiAgentRunner(
          streamChat: repo.streamChat,
          tools: GenAiAgentToolRegistry(const []),
        ),
      );
      await workspace.reloadModels();
      expect(
        await workspace.openConversation('remote-only', GenAiCancellation()),
        isTrue,
      );
      expect(workspace.turns.length, tools ? 14 : 13);
      final restored = workspace.turns[12];
      expect(restored.prompt, 'Read record off-2-099.');
      expect(restored.agentEvents.values.single.result, receipt);
      expect(restored.agentEvents.values.single.prepared, isNull);
      expect(restored.agentTranscript, isEmpty);
      expect(
        workspace.turns.any((t) => isGenAiContextExtraction(t.prompt)),
        isFalse,
      );
      workspace.setAgentEnabled(tools);
      await workspace.send('Recall off-2-099; do not call tools.');
      expect(workspace.turns.last.phase, GenAiChatPhase.completed);
      expect(workspace.turns.last.answer, 'sample 688; temperature 18');
      final listed = await repo.listConversations(GenAiCancellation());
      expect(listed.records.last.title, '上下文整理（旧版辅助会话）');
      await workspace.flushConversations();
      workspace.dispose();
      chat.dispose();
      sessions.dispose();
      // Everything except the upstream append-only rows is discarded here.
    }
    expect(actual, hasLength(2));
    expect(deletions, 0);
    expect(
      remote.where((r) => isGenAiContextExtraction(r['question']! as String)),
      isNotEmpty,
    );
  });

  test('account change while summarizing cannot dispatch the actual generation or save memory',
      () async {
    final started = Completer<void>();
    final gate = Completer<void>();
    var generations = 0;
    final transport = ScriptedTransport((r) async {
      if (r.method != 'POST') return profileResponse();
      final body = jsonDecode(r.body!) as Map;
      if (isGenAiContextExtraction(body['chatInfo'] as String)) {
        started.complete();
        await r.cancellation.race(gate.future);
        return response(
          type: 'text/event-stream',
          text: sseChunk(text: '{"items":[]}', finish: 'stop'),
        );
      }
      generations++;
      return response(
        type: 'text/event-stream',
        text: sseChunk(text: 'Must not reach', finish: 'stop'),
      );
    });
    final api = GenAiApiClient(transport: transport);
    final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    addTearDown(sessions.dispose);
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'synthetic'));
    final repository = GenAiRepository(
      api: api,
      sessions: sessions,
      contextCompactor: GenAiContextCompactor(policy: policy),
    );
    final chat = GenAiChatService(repository);
    addTearDown(chat.dispose);
    final progressVisible = Completer<void>();
    final updates = <GenAiContextUsage>[];
    chat.addListener(() {
      final usage = chat.contextUsage;
      if (usage == null) return;
      updates.add(usage);
      if (usage.stage == GenAiContextStage.compacting && !progressVisible.isCompleted) {
        progressVisible.complete();
      }
    });
    final pending = chat.send(
      GenAiChatRequest(
        chatGroupId: 'race',
        prompt: 'continue',
        aiType: 'Kimi-k3',
        rootAiType: 'xinference',
        history: [
          for (var i = 0; i < 30; i++)
            GenAiMessage(
              role: i.isEven ? GenAiRole.user : GenAiRole.assistant,
              content: '$i ${'source ' * 150}',
            ),
        ],
      ),
    );
    await started.future;
    await progressVisible.future;
    expect(chat.contextUsage!.stage, GenAiContextStage.compacting);
    await sessions.setOwner(ownerB);
    gate.complete();
    await pending;
    expect(chat.contextUsage, isNull);
    expect(
      updates.any((value) => value.stage == GenAiContextStage.ready),
      isFalse,
    );
    expect(generations, 0);
    expect(chat.answer, isEmpty);
    expect(repository.contextSnapshot('race'), isEmpty);
  });
}
