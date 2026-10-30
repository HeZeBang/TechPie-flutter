import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
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
  test('fresh agent retrieves full compacted sources, and deletion revokes old references',
      () async {
    final server = JournalServer();
    final first = await JournalClient.create(server, policy: policy);
    addTearDown(first.dispose);
    final original = 'archive-key-573: ${'ordinary source ' * 500} exact-value=5837';
    for (var i = 0; i < 10; i++) {
      await first.workspace.send(i == 2 ? original : 'Record $i.\n${'source evidence ' * 700}');
    }
    expect(server.summaries, greaterThan(0));
    final group = first.workspace.groupId;
    final fresh = await JournalClient.create(server, policy: policy);
    addTearDown(fresh.dispose);
    await fresh.workspace.openConversation(group, GenAiCancellation());
    fresh.workspace.setAgentEnabled(true);
    String? recordId;
    var stage = 0;
    server.onGenerate = (body) {
      final nonce = server.nonce(body);
      if (stage++ == 0) {
        expect(body['messages'].toString(), contains('record_id'));
        return encodeGenAiCompactCall(
          'search_conversation',
          {'query': 'archive-key-573'},
          nonce: nonce,
        );
      }
      final receipt = decodeGenAiAgentRecord(server.input(body))!.result!;
      expect(receipt['ok'], true);
      final result = receipt['result'] as Map;
      if (stage == 2) {
        final match = (result['matches'] as List).first as Map;
        recordId = match['record_id'] as String;
        return encodeGenAiCompactCall(
          'read_conversation_records',
          {
            'record_id': recordId,
            'offset': original.length - 100,
          },
          nonce: nonce,
        );
      }
      expect(result['text'], endsWith('exact-value=5837'));
      return server.finalAnswer(body, '5837');
    };
    await fresh.workspace.send('Find the exact original value from the archived record.');
    expect(fresh.workspace.turns.last.phase, GenAiChatPhase.completed);
    expect(fresh.workspace.turns.last.answer, '5837');
    expect(stage, 3);
    final reopened = await JournalClient.create(server, policy: policy);
    addTearDown(reopened.dispose);
    await reopened.workspace.openConversation(group, GenAiCancellation());
    expect(reopened.workspace.turns.last.agentEvents, hasLength(2));
    // Removing that source suffix must also remove access from a fresh instance.
    server.onGenerate = (_) => 'Replacement';
    await reopened.workspace.changeTurn(reopened.workspace.turns[2].id, replacement: 'new record');
    final edited = await JournalClient.create(server, policy: policy);
    addTearDown(edited.dispose);
    await edited.workspace.openConversation(group, GenAiCancellation());
    edited.workspace.setAgentEnabled(true);
    var calls = 0;
    server.onGenerate = (body) {
      if (calls++ == 0) {
        return encodeGenAiCompactCall(
          'read_conversation_records',
          {'record_id': recordId},
          nonce: server.nonce(body),
        );
      }
      final receipt = decodeGenAiAgentRecord(server.input(body))!.result!;
      expect((receipt['error'] as Map)['code'], 'record_not_found');
      return server.finalAnswer(body, 'Record removed');
    };
    await edited.workspace.send('Try the old reference.');
    expect(edited.workspace.turns.last.answer, 'Record removed');
  });

  test('editing compacted history removes discarded evidence from fresh-client context', () async {
    final server = JournalServer();
    final client = await JournalClient.create(server, policy: policy);
    addTearDown(client.dispose);
    for (var i = 0; i < 10; i++) {
      await client.workspace.send(
        '${i < 2 ? 'keep' : 'REMOVED-SECRET'} $i.\n${'source evidence ' * 700}',
      );
    }
    expect(server.summaries, greaterThan(0));
    final group = client.workspace.groupId;
    await client.workspace.changeTurn(client.workspace.turns[2].id, replacement: 'replacement');
    expect(client.workspace.turns, hasLength(3));
    expect(server.rows[group].toString(), isNot(contains('REMOVED-SECRET')));
    for (final agent in [false, true]) {
      final fresh = await JournalClient.create(server, policy: policy);
      addTearDown(fresh.dispose);
      await fresh.workspace.openConversation(group, GenAiCancellation());
      fresh.workspace.setAgentEnabled(agent);
      server.onGenerate = (body) {
        expect(body.toString(), isNot(contains('REMOVED-SECRET')));
        expect(body['messages'].toString(), contains('keep'));
        return agent ? server.finalAnswer(body, 'kept facts') : 'kept facts';
      };
      await fresh.workspace.send('What is retained?');
      expect(fresh.workspace.turns.last.phase, GenAiChatPhase.completed);
    }
  });

  test('compaction piggybacks on real exchanges and survives fresh clients in both modes',
      () async {
    final server = JournalServer();
    final a = await JournalClient.create(server, policy: policy);
    addTearDown(a.dispose);
    for (var i = 0; i < 10; i++) {
      await a.workspace.send('Record $i: original number 5837.\n${'source evidence ' * 700}');
      expect(a.workspace.turns.last.phase, GenAiChatPhase.completed);
      expect(
        decodeGenAiRemoteRecord(server.generations.last['chatInfo'] as String)!['contextUsage'],
        a.workspace.contextUsage!.toRecord(),
      );
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
      final requestsBeforeOpen = server.generations.length;
      final savedUsage =
          decodeGenAiRemoteRecord(server.generations.last['chatInfo'] as String)!['contextUsage'];
      await fresh.workspace.openConversation(a.workspace.groupId, GenAiCancellation());
      expect(fresh.workspace.contextUsage?.toRecord(), savedUsage);
      expect(fresh.workspace.contextUsage?.stage, GenAiContextStage.ready);
      expect(server.generations.length, requestsBeforeOpen);
      expect(fresh.workspace.turns.length, greaterThanOrEqualTo(10));
      fresh.workspace.setAgentEnabled(agent);
      server.onGenerate = (body) => agent
          ? server.finalAnswer(body, 'The original number is 5837.')
          : 'The original number is 5837.';
      await fresh.workspace.send('Recall the original number.');
      expect(fresh.workspace.turns.last.phase, GenAiChatPhase.completed);
      expect(server.generations.last['messages'].toString(), contains('5837'));
      expect(server.summaries, calls);
      final liveUsage = fresh.workspace.contextUsage!.toRecord();
      final reopened = await JournalClient.create(server, policy: policy);
      addTearDown(reopened.dispose);
      await reopened.workspace.openConversation(a.workspace.groupId, GenAiCancellation());
      expect(reopened.workspace.contextUsage?.toRecord(), liveUsage);
      expect(reopened.workspace.agentEnabled, agent);
      expect(server.generations.length, requestsBeforeOpen + 1);
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
