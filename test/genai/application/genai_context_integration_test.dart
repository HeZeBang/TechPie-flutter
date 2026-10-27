import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_context_record.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';

import '../support/fakes.dart';
import '../support/journal_server.dart';

const policy = GenAiContextPolicy(
  contextTokens: 60000,
  latestTokens: 40000,
  safetyTokens: 2000,
  outputTokens: 2048,
  triggerTokens: 30000,
  targetTokens: 20000,
  summaryChunkTokens: 12000,
  memoryTokens: 6000,
  recentMessages: 4,
);

void main() {
  test('compaction piggybacks on real exchanges and survives fresh clients in both modes',
      () async {
    final server = JournalServer();
    final a = await JournalClient.create(server, policy: policy);
    addTearDown(a.dispose);
    for (var i = 0; i < 10; i++) {
      await a.workspace.send('Record $i: original number 5837.\n${'source evidence ' * 700}');
      expect(a.workspace.turns.last.phase, GenAiChatPhase.completed);
    }
    expect(server.summaries, greaterThan(0));
    expect(server.generations, hasLength(10));
    expect(server.rows.keys, [a.workspace.groupId]);
    expect(
      server.generations
          .any((r) => decodeGenAiRemoteRecord(r['chatInfo'] as String)!.containsKey('context')),
      true,
    );
    final calls = server.summaries;
    for (final agent in [false, true]) {
      final fresh = await JournalClient.create(server, policy: policy);
      addTearDown(fresh.dispose);
      await fresh.workspace.openConversation(a.workspace.groupId, GenAiCancellation());
      expect(fresh.workspace.turns.length, greaterThanOrEqualTo(10));
      fresh.workspace.setAgentEnabled(agent);
      server.onGenerate = (body) => agent
          ? server.finalAnswer(body, 'The original number is 5837.')
          : 'The original number is 5837.';
      await fresh.workspace.send('Recall the original number.');
      expect(fresh.workspace.turns.last.phase, GenAiChatPhase.completed);
      expect(server.generations.last['messages'].toString(), contains('5837'));
      expect(server.summaries, calls);
    }
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
              content: '$i ${'source ' * 500}',
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
