import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';

const policy = GenAiContextPolicy(
  contextTokens: 20000,
  latestTokens: 3000,
  safetyTokens: 1000,
  outputTokens: 1000,
  triggerTokens: 8000,
  targetTokens: 6000,
  summaryChunkTokens: 4000,
  memoryTokens: 2800,
  recentMessages: 4,
);

List<GenAiMessage> sourceHistory() => [
      const GenAiMessage(
        role: GenAiRole.system,
        content: 'Use only enabled tools. Never repeat an unknown action.',
      ),
      const GenAiMessage(
        role: GenAiRole.user,
        content: 'Plan my campus week. Never book a court without confirmation.',
      ),
      for (var i = 0; i < 12; i++) ...[
        GenAiMessage(
          role: GenAiRole.assistant,
          content: 'Observation $i. ${'irrelevant telemetry ' * 70}',
        ),
        GenAiMessage(
          role: GenAiRole.user,
          content: i == 2
              ? 'Budget: 49 CNY. Deadline: 2031-11-12 14:35 Asia/Shanghai. ${'detail ' * 100}'
              : i == 4
                  ? 'Correction: Budget is 73 CNY, not 49. Keep booking B-37 outcome UNKNOWN; do not retry. ${'detail ' * 100}'
                  : 'Question $i: ${'detail ' * 100}',
        ),
      ],
    ];

GenAiChatRequest request(
  List<GenAiMessage> history, {
  String prompt = 'What is my Budget, Deadline and booking outcome?',
  String? goal,
  List<String> files = const [],
  Map<String, String> documents = const {},
}) =>
    GenAiChatRequest(
      chatGroupId: 'test-conversation',
      aiType: 'Kimi-k3',
      rootAiType: 'xinference',
      prompt: prompt,
      history: history,
      contextGoal: goal,
      fileIds: files,
      documentContents: documents,
    );

Stream<GenAiChatEvent> summary(
  GenAiChatRequest request,
  GenAiCancellation c,
) async* {
  expect(request.thinking, isFalse);
  expect(request.toJson()['netGo'], isFalse);
  expect(request.fileIds, isEmpty);
  final records = jsonDecode(request.history.last.content) as List;
  yield GenAiTextDelta(
    jsonEncode({
      'items': [
        for (final record in records.take(16))
          {
            'source': record['source'],
            'kind': record['role'] == 'user' ? 'constraint' : 'fact',
            'quote':
                (record['text'] as String).split('detail').first.split('irrelevant').first.trim(),
          },
      ],
    }),
  );
  yield const GenAiChatFinished(GenAiFinishReason.stop);
}

void main() {
  test('compaction and receipt decoration preserve current task and live protocol control',
      () async {
    const control = {
      'current_task': 'Read the original budget',
      'current_nonce': 'active_nonce_0123456789',
    };
    final input = GenAiChatRequest(
      chatGroupId: 'long-agent-chat',
      prompt: 'Latest tool result',
      aiType: 'Kimi-k3',
      rootAiType: 'xinference',
      history: sourceHistory(),
      agentControl: control,
      record: const {'step_id': 'active_nonce_0123456789'},
    );
    final prepared =
        await GenAiContextCompactor(policy: policy).prepare(input, GenAiCancellation(), summary);
    expect(prepared.contextCompacted, true);
    expect(prepared.agentControl, control);
    final wire = prepared.withRecord({
      ...prepared.record,
      'context': {'boundary': 'saved'},
    }).toJson();
    expect(decodeGenAiRemoteRecord(wire['chatInfo']! as String)?['agent_control'], control);
    expect(prepared.history.first.content, contains('Never repeat an unknown action'));
    expect(wire['netGo'], false);
  });

  test('256k profile accepts a latest input well beyond 16k without compaction', () async {
    final compactor = GenAiContextCompactor();
    final input = request(const [], prompt: '原始记录。' * 8000);
    final result = await compactor.prepare(input, GenAiCancellation(), (_, __) async* {
      fail('An input within the context budget should not be summarized');
    });
    expect(result.prompt, input.prompt);
    expect(result.contextCompacted, false);
  });

  for (final tools in [false, true]) {
    test('checkpoint survives follow-ups and reopen without recompacting tools=$tools', () async {
      var compactor = GenAiContextCompactor(policy: policy);
      final history = sourceHistory();
      var calls = 0;
      Stream<GenAiChatEvent> tracked(GenAiChatRequest r, GenAiCancellation c) {
        calls++;
        return summary(r, c);
      }

      final first = await compactor.prepare(request(history), GenAiCancellation(), tracked);
      expect(first.contextCompacted, isTrue);
      final initialCalls = calls;
      for (var i = 0; i < 3; i++) {
        history.addAll([
          GenAiMessage(role: GenAiRole.user, content: 'Follow-up $i'),
          const GenAiMessage(role: GenAiRole.assistant, content: 'Short answer'),
          if (tools) ...[
            GenAiAgentHistoryEntry.call(
              GenAiAgentToolCall(
                id: 'time-$i',
                name: 'get_current_time',
                arguments: const {},
              ),
            ).message,
            GenAiAgentHistoryEntry.result({
              'call_id': 'time-$i',
              'name': 'get_current_time',
              'ok': true,
              'result': {'utc': '2031-11-12T05:18:00Z'},
            }).message,
          ],
        ]);
        if (i == 2) {
          compactor = GenAiContextCompactor(policy: policy)
            ..restore('test-conversation', compactor.snapshot('test-conversation'));
        }
        final updates = <GenAiContextUsage>[];
        final next = await compactor.prepare(
          request(history),
          GenAiCancellation(),
          tracked,
          onUsage: updates.add,
        );
        expect(next.contextCompacted, isFalse, reason: 'Follow-up $i must reuse the checkpoint');
        expect(updates.any((u) => u.stage == GenAiContextStage.compacting), isFalse);
        expect(calls, initialCalls);
        expect(next.history.map((m) => m.content).join(), contains('73 CNY'));
      }
      history.addAll([
        for (var i = 0; i < 8; i++) ...[
          GenAiMessage(role: GenAiRole.user, content: 'New material $i: ${'detail ' * 100}'),
          const GenAiMessage(role: GenAiRole.assistant, content: 'Noted'),
        ],
      ]);
      final advanced = await compactor.prepare(request(history), GenAiCancellation(), tracked);
      expect(advanced.contextCompacted, isTrue);
      expect(calls, greaterThan(initialCalls));
    });
  }

  test('failed extraction fallback is reused instead of retried on every follow-up', () async {
    final compactor = GenAiContextCompactor(policy: policy);
    final history = sourceHistory();
    var calls = 0;
    Stream<GenAiChatEvent> broken(GenAiChatRequest r, GenAiCancellation c) async* {
      calls++;
      throw const GenAiFailure(GenAiFailureKind.timeout);
    }

    await compactor.prepare(request(history), GenAiCancellation(), broken);
    history.add(const GenAiMessage(role: GenAiRole.user, content: 'And the deadline?'));
    final next = await compactor.prepare(request(history), GenAiCancellation(), broken);
    expect(calls, 1);
    expect(next.contextCompacted, isFalse, reason: 'Follow-up must reuse compacted history');
    expect(next.history.map((m) => m.content).join(), contains('2031-11-12'));
  });

  test('reports actual chunk progress before extraction and the enforced final budget', () async {
    final updates = <GenAiContextUsage>[];
    final started = Completer<void>();
    final release = Completer<void>();
    final prepared = GenAiContextCompactor(policy: policy).prepare(
      request(sourceHistory()),
      GenAiCancellation(),
      (r, c) async* {
        if (!started.isCompleted) started.complete();
        await release.future;
        yield* summary(r, c);
      },
      onUsage: updates.add,
    );
    await started.future;
    expect(updates.first.stage, GenAiContextStage.preparing);
    expect(updates.last.stage, GenAiContextStage.compacting);
    expect(updates.last.completedChunks, 0);
    expect(updates.last.totalChunks, greaterThan(0));
    release.complete();
    final result = await prepared;
    final ready = updates.last;
    expect(ready.stage, GenAiContextStage.ready);
    expect(ready.compacted, isTrue);
    expect(ready.completedChunks, ready.totalChunks);
    expect(
      updates
          .where((value) => value.stage == GenAiContextStage.compacting)
          .map((value) => value.completedChunks),
      List.generate(ready.totalChunks + 1, (index) => index),
    );
    expect(
      ready.estimatedInputUnits,
      GenAiContextCompactor.tokens(result.prompt) +
          32 +
          result.history.fold<int>(
            0,
            (sum, item) => sum + GenAiContextCompactor.messageTokens(item),
          ),
    );
    expect(ready.originalInputUnits, updates.first.estimatedInputUnits);
    expect(ready.estimatedInputUnits, lessThan(ready.originalInputUnits));
    expect(
      ready.allowedInputUnits,
      policy.contextTokens - policy.safetyTokens - policy.outputTokens,
    );
    expect(
      ready.estimatedInputUnits,
      lessThanOrEqualTo(ready.allowedInputUnits),
    );
  });

  test('ready estimates include CJK, deduplicated attachments and reserved output', () async {
    final updates = <GenAiContextUsage>[];
    await GenAiContextCompactor(policy: policy).prepare(
      GenAiChatRequest(
        chatGroupId: 'estimate',
        prompt: '中文',
        aiType: 'fixture',
        rootAiType: 'fixture',
        history: const [GenAiMessage(role: GenAiRole.user, content: '中')],
        fileIds: const ['doc', 'doc'],
        documentContents: const {'doc': '文档'},
        imageUrls: const ['image', 'image'],
        imageUrl: 'image',
        maxTokens: 1234,
      ),
      GenAiCancellation(),
      summary,
      onUsage: updates.add,
    );
    expect(
      updates.map((value) => value.stage),
      [GenAiContextStage.preparing, GenAiContextStage.ready],
    );
    expect(updates.last.estimatedInputUnits, 2 + 32 + 1 + 12 + 2 + 64 + 4096);
    expect(updates.last.allowedInputUnits, 20000 - 1000 - 1234);
    expect(updates.last.compacted, isFalse);
    expect(updates.last.totalChunks, 0);
  });

  test('compacts wire context, preserves exact corrections and leaves source history intact',
      () async {
    final history = sourceHistory();
    final before = jsonEncode(history.map((m) => m.toJson()).toList());
    final compactor = GenAiContextCompactor(policy: policy);
    final result = await compactor.prepare(request(history), GenAiCancellation(), summary);
    final text = result.history.map((m) => m.content).join('\n');
    expect(text, contains('73 CNY, not 49'));
    expect(text, contains('2031-11-12 14:35 Asia/Shanghai'));
    expect(text, contains('outcome UNKNOWN; do not retry'));
    expect(result.history.first.role, GenAiRole.system);
    expect(text, contains('Never book a court without confirmation'));
    expect(text, contains('techpie_context_memory_v1'));
    expect(
      result.history[result.history.length - 2].content,
      history.last.content,
    );
    expect(result.prompt, request(history).prompt);
    expect(
      GenAiContextCompactor.tokens(text) + GenAiContextCompactor.tokens(result.prompt),
      lessThan(19000),
    );
    expect(jsonEncode(history.map((m) => m.toJson()).toList()), before);
    expect(compactor.snapshot('test-conversation'), isNotEmpty);
  });

  test('source evidence outranks repeated wrong assistant answers after compaction', () async {
    final history = sourceHistory();
    history[4] = const GenAiMessage(
      role: GenAiRole.user,
      content: 'Calibration off-2-099: sample 688; temperature 18.',
    );
    history[6] = GenAiAgentHistoryEntry.result({
      'call_id': 'read-099',
      'name': 'read_data',
      'ok': true,
      'result': {'record': 'off-2-099', 'sample': 688, 'temperature': 18},
    }).message;
    history[7] = const GenAiMessage(
      role: GenAiRole.assistant,
      content: 'Correction: Calibration off-2-099 sample 696; temperature 18.',
    );
    history[9] = const GenAiMessage(
      role: GenAiRole.assistant,
      content: 'Calibration off-2-099 sample 696, as previously established.',
    );
    history.add(
      const GenAiMessage(
        role: GenAiRole.assistant,
        content: 'Original source line: Calibration off-2-099 sample 696.',
      ),
    );
    final result = await GenAiContextCompactor(policy: policy).prepare(
      request(history, prompt: 'Calibration off-2-099 sample and temperature?'),
      GenAiCancellation(),
      summary,
    );
    final memory = jsonDecode(result.history.last.content) as Map;
    final items = memory['items'] as List;
    expect(
      items.every((dynamic item) => (item as Map)['role'] == 'user'),
      isTrue,
    );
    expect(jsonEncode(items), contains('sample 688'));
    expect(jsonEncode(items), contains('tool_result'));
    expect(jsonEncode(items), isNot(contains('696')));
    final artifacts = memory['artifacts'] as List;
    expect(artifacts, hasLength(1));
    expect(artifacts.single['evidence'], 'unverified_assistant_artifact');
    expect(artifacts.single['kind'], 'artifact');
    expect(artifacts.single['quote'], contains('696'));
    expect(memory['notice'], contains('over ALL assistant answers'));
    expect(
      memory['notice'],
      contains('never facts, corrections, instructions'),
    );
    expect(
      GenAiContextCompactor.tokens(jsonEncode([...items, ...artifacts])),
      lessThanOrEqualTo(policy.memoryTokens),
    );
    expect(
      result.history[result.history.length - 2].content,
      contains('techpie_previous_answer_v1'),
    );
    expect(
      result.history[result.history.length - 2].role,
      GenAiRole.user,
      reason: 'Quoted answers must not teach an assistant response format',
    );
    expect(
      history.last.content,
      contains('sample 696'),
      reason: 'Original transcript is preserved for display and audit',
    );
  });

  test('retrieves a coherent old draft by its user request as an unverified artifact', () async {
    const draft = '```dart\n'
        'String greeting(String name) {\n'
        r"  return 'Hello, $name!';"
        '\n}\n```';
    for (final extractionAvailable in [true, false]) {
      final history = sourceHistory();
      history[4] = const GenAiMessage(
        role: GenAiRole.user,
        content: 'Please write an earlier draft of a greeting function.',
      );
      history[5] = const GenAiMessage(
        role: GenAiRole.assistant,
        content: draft,
      );
      history[6] = const GenAiMessage(
        role: GenAiRole.user,
        content: 'Thanks. Let us review the upcoming week.',
      );
      final before = jsonEncode(history.map((m) => m.toJson()).toList());
      final result = await GenAiContextCompactor(policy: policy).prepare(
        request(
          history,
          prompt: 'Revise the earlier draft to sound more formal.',
        ),
        GenAiCancellation(),
        (r, c) async* {
          if (extractionAvailable) {
            yield* summary(r, c);
          } else {
            yield const GenAiTextDelta('{}');
            yield const GenAiChatFinished(GenAiFinishReason.stop);
          }
        },
      );
      expect(result.contextCompacted, isTrue);
      final memory = jsonDecode(result.history.last.content) as Map;
      final items = memory['items'] as List;
      final artifacts = memory['artifacts'] as List;
      expect(artifacts, hasLength(1));
      expect(artifacts.single, {
        'source': 4, // Excludes the system row.
        'role': 'assistant',
        'kind': 'artifact',
        'evidence': 'unverified_assistant_artifact',
        'quote': draft,
        'partial': false,
      });
      expect(items.every((dynamic item) => item['role'] == 'user'), isTrue);
      expect(
        GenAiContextCompactor.tokens(jsonEncode([...items, ...artifacts])),
        lessThanOrEqualTo(policy.memoryTokens),
      );
      expect(jsonEncode(history.map((m) => m.toJson()).toList()), before);
    }
  });

  test('latest receipt index spans compacted evidence and retained tool pairs', () async {
    for (final succeeded in [true, false]) {
      final history = sourceHistory();
      history[6] = GenAiAgentHistoryEntry.result({
        'call_id': 'old',
        'name': 'get_current_time',
        'ok': true,
        'result': {'utc': '2031-11-12T05:17:00Z'},
      }).message;
      final call = GenAiAgentHistoryEntry.call(
        GenAiAgentToolCall(
          id: 'latest',
          name: 'get_current_time',
          arguments: const {},
        ),
      ).message;
      final receipt = GenAiAgentHistoryEntry.result({
        'call_id': 'latest',
        'name': 'get_current_time',
        'ok': succeeded,
        if (succeeded) 'result': {'utc': '2031-11-12T05:18:00Z'},
        if (!succeeded)
          'error': {
            'code': 'outcome_unknown',
            'message': 'Receipt unavailable',
          },
      }).message;
      history.addAll(
        [call, receipt],
      );
      final prepared = await GenAiContextCompactor(policy: policy).prepare(
        request(history, prompt: 'What is the latest get_current_time result?'),
        GenAiCancellation(),
        summary,
      );
      final memory = jsonDecode(prepared.history.last.content) as Map;
      final latest = (memory['items'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (item) => item['latestRecordedResultForTool'] == 'get_current_time',
          )
          .single;
      expect(latest['quote'], receipt.content);
      expect(latest['source'], history.length - 2); // Excludes the system row.
      expect(latest['partial'], isFalse);
      expect(memory['retainedSourceRange']['endExclusive'], history.length - 1);
      expect(memory['notice'], contains('not wire order'));
      expect(
        prepared.history.sublist(
          prepared.history.length - 3,
          prepared.history.length - 1,
        ),
        [call, receipt],
      );
      expect(
        GenAiContextCompactor.tokens(jsonEncode(memory['items'])),
        lessThanOrEqualTo(policy.memoryTokens),
      );
    }
  });

  test(
      'reopen reuses source-checked checkpoints; edits and model changes cannot reuse stale memory',
      () async {
    final history = sourceHistory();
    final first = GenAiContextCompactor(policy: policy);
    await first.prepare(request(history), GenAiCancellation(), summary);
    final checkpoint =
        jsonDecode(jsonEncode(first.snapshot('test-conversation'))) as Map<String, dynamic>;
    final restored = GenAiContextCompactor(policy: policy)
      ..restore('test-conversation', checkpoint);
    var calls = 0;
    Stream<GenAiChatEvent> tracked(GenAiChatRequest r, GenAiCancellation c) {
      calls++;
      return summary(r, c);
    }

    await restored.prepare(request(history), GenAiCancellation(), tracked);
    expect(calls, 0);
    final changed = [...history];
    changed[10] = const GenAiMessage(
      role: GenAiRole.user,
      content: 'Correction: Budget is 81 CNY.',
    );
    final result = await restored.prepare(request(changed), GenAiCancellation(), tracked);
    expect(calls, greaterThan(0));
    expect(result.history.map((m) => m.content).join(), contains('81 CNY'));
    calls = 0;
    await restored.prepare(
      GenAiChatRequest(
        chatGroupId: 'test-conversation',
        prompt: 'Budget?',
        aiType: 'different',
        rootAiType: 'xinference',
        history: history,
      ),
      GenAiCancellation(),
      tracked,
    );
    expect(calls, greaterThan(0));
  });

  test('invalid summaries fall back to verbatim retrieval without inventing facts', () async {
    final compactor = GenAiContextCompactor(policy: policy);
    var extractionCalls = 0;
    final result =
        await compactor.prepare(request(sourceHistory()), GenAiCancellation(), (r, c) async* {
      extractionCalls++;
      yield const GenAiTextDelta(
        '{"items":[{"source":1,"kind":"action","quote":"Booking succeeded; charge 999 CNY"}]}',
      );
      yield const GenAiChatFinished(GenAiFinishReason.stop);
    });
    final text = result.history.map((m) => m.content).join();
    expect(text, contains('outcome UNKNOWN'));
    expect(text, isNot(contains('charge 999')));
    expect(compactor.snapshot('test-conversation').keys, ['_boundary']);
    expect(extractionCalls, 1);
  });

  test('configured latest-input budget accounts for CJK without byte-token confusion', () async {
    final compactor = GenAiContextCompactor(policy: policy);
    await expectLater(
      compactor.prepare(
        request(const [], prompt: '中' * 3000),
        GenAiCancellation(),
        summary,
      ),
      throwsA(
        isA<GenAiFailure>().having((e) => e.kind, 'kind', GenAiFailureKind.messageTooLarge),
      ),
    );
    final history = [
      for (var i = 0; i < 4; i++)
        GenAiMessage(
          role: i.isEven ? GenAiRole.user : GenAiRole.assistant,
          content: 'a' * 1200,
        ),
    ];
    final result = await compactor.prepare(
      request(history, prompt: 'continue'),
      GenAiCancellation(),
      summary,
    );
    expect(result.history, history);
    expect(result.maxTokens, policy.outputTokens);
  });

  test('injected documents consume context; unknown archived content fails explicitly', () async {
    final compactor = GenAiContextCompactor(policy: policy);
    await expectLater(
      compactor.prepare(
        request(const [], files: ['old']),
        GenAiCancellation(),
        summary,
      ),
      throwsA(
        isA<GenAiFailure>().having(
          (e) => e.kind,
          'kind',
          GenAiFailureKind.attachmentContextUnknown,
        ),
      ),
    );
    await expectLater(
      compactor.prepare(
        request(const [], files: ['big'], documents: {'big': 'a' * 40000}),
        GenAiCancellation(),
        summary,
      ),
      throwsA(
        isA<GenAiFailure>().having((e) => e.kind, 'kind', GenAiFailureKind.contextTooLarge),
      ),
    );
    final result = await compactor.prepare(
      request(const [], files: ['small'], documents: {'small': 'hello'}),
      GenAiCancellation(),
      summary,
    );
    expect(result.toJson()['fileIds'], ['small']);
    expect(result.toJson().containsKey('documentContents'), isFalse);
    final largeButSafe = await compactor.prepare(
      request(const [], files: ['fits'], documents: {'fits': 'a' * 15000}),
      GenAiCancellation(),
      summary,
    );
    expect(largeButSafe.fileIds, ['fits']);
    expect(largeButSafe.contextCompacted, isFalse);
  });

  test('cancel or scope reset during summary cannot publish a checkpoint or continue', () async {
    for (final reset in [false, true]) {
      final compactor = GenAiContextCompactor(policy: policy);
      final operation = GenAiCancellation();
      final started = Completer<void>();
      final release = Completer<void>();
      final pending = compactor.prepare(request(sourceHistory()), operation, (r, c) async* {
        started.complete();
        await release.future;
        yield* summary(r, c);
      });
      final check = expectLater(pending, throwsA(isA<GenAiFailure>()));
      await started.future;
      if (reset) {
        compactor.clear();
      } else {
        operation.cancel();
      }
      release.complete();
      await check;
      expect(compactor.snapshot('test-conversation'), isEmpty);
    }
  });

  test('active goal and last tool exchange survive even when goal is older than the tail',
      () async {
    const goal = 'ACTIVE GOAL: locate my schedule; never make a booking';
    final history = sourceHistory();
    history[4] = const GenAiMessage(role: GenAiRole.user, content: goal);
    history.addAll(const [
      GenAiMessage(
        role: GenAiRole.assistant,
        content:
            '<techpie-agent-history version="2">{"kind":"call","value":{"call_id":"s-1","name":"get_semesters","arguments":{}}}</techpie-agent-history>',
      ),
      GenAiMessage(
        role: GenAiRole.user,
        content:
            '<techpie-agent-history version="2">{"kind":"result","value":{"call_id":"s-1","name":"get_semesters","ok":true,"result":{}}}</techpie-agent-history>',
      ),
    ]);
    final result = await GenAiContextCompactor(policy: policy).prepare(
      request(history, goal: goal, prompt: 'current result'),
      GenAiCancellation(),
      summary,
    );
    expect(result.history.any((m) => m.content == goal), isTrue);
    expect(
      result.history
          .sublist(result.history.length - 3, result.history.length - 1)
          .map((m) => m.content),
      history.sublist(history.length - 2).map((m) => m.content),
    );
  });
  test('oversized recent exchanges compact further without splitting the newest tool pair',
      () async {
    final call = GenAiAgentHistoryEntry.call(
      GenAiAgentToolCall(
        id: 'latest',
        name: 'get_semesters',
        arguments: const {},
      ),
    ).message;
    final result = GenAiAgentHistoryEntry.result({
      'call_id': 'latest',
      'name': 'get_semesters',
      'ok': true,
      'result': {'semester': '2026-fall'},
    }).message;
    final history = [
      ...sourceHistory(),
      GenAiMessage(
        role: GenAiRole.user,
        content: 'Large old exchange ${'x' * 15000}',
      ),
      GenAiMessage(
        role: GenAiRole.assistant,
        content: 'Large old answer ${'y' * 15000}',
      ),
      call,
      result,
    ];
    final prepared = await GenAiContextCompactor(policy: policy).prepare(
      request(history),
      GenAiCancellation(),
      summary,
    );
    expect(prepared.contextCompacted, isTrue);
    expect(
      prepared.history.sublist(
        prepared.history.length - 3,
        prepared.history.length - 1,
      ),
      [call, result],
    );
    expect(
      prepared.history.fold<int>(0, (n, m) => n + GenAiContextCompactor.messageTokens(m)),
      lessThan(18000),
    );
    expect(history.any((m) => m.content.length > 15000), isTrue);
  });

  test('exact record identifiers outrank generic words when retrieving omitted source details',
      () async {
    const query =
        'From the earlier Calibration off-2-077 record, what are the sample number and temperature? '
        'Also explain whether booking B-37 may be retried. Use the original records; '
        'if a value is missing say so. Do not search or use tools.';
    final history = sourceHistory();
    final records = List.generate(
      120,
      (i) => 'Calibration off-2-${i.toString().padLeft(3, '0')}: '
          'sample ${((i * 17 + 2) % 997).toString().padLeft(3, '0')}; '
          'temperature ${18 + i % 9}. Sensor observation archived for comparison, no action needed.',
    ).join('\n');
    final oldText =
        'Project courier code: LYRA-572. The archive room is Cobalt. Initial budget is 49 CNY.\n\n'
        'Synthetic calibration records:\n$records';
    history[4] = GenAiMessage(
      role: GenAiRole.user,
      content:
          '${oldText.substring(0, 13300)}\n\nReply only ACK-2; do not restate the facts. Do not call tools for this batch.',
    );
    for (final goal in <String?>[null, query]) {
      final result = await GenAiContextCompactor(policy: policy).prepare(
        request(
          history,
          prompt: goal == null ? query : 'Tool result: current time 12:34.',
          goal: goal,
        ),
        GenAiCancellation(),
        summary,
      );
      expect(
        result.history.map((m) => m.content).join(),
        contains('off-2-077: sample 314; temperature 23'),
      );
    }
  });
  test('repetitive query matches cannot crowd durable user facts out of memory', () async {
    final noise = List.generate(180, (i) => 'sensor_$i').join(' ');
    final history = sourceHistory();
    for (var i = 2; i < history.length - 4; i++) {
      history[i] = GenAiMessage(
        role: history[i].role,
        content:
            '${i == 5 ? 'Courier code: LYRA-572. Archive room: Cobalt. ${'Evidence provenance: original record; preserve every correction. ' * 8}' : 'Record $i.'} detail $noise ${i == 5 ? '' : noise}',
      );
    }
    final result = await GenAiContextCompactor(policy: policy).prepare(
      request(
        history,
        prompt: '$noise What are the courier code and archive room?',
      ),
      GenAiCancellation(),
      summary,
    );
    final memory = result.history.map((m) => m.content).join();
    expect(memory, contains('Courier code: LYRA-572. Archive room: Cobalt.'));
  });
}
