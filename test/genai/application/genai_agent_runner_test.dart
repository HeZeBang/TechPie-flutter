import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

const objectSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{},
  'additionalProperties': false,
};

const testNonce = 'synthetic_nonce_0123456789';

GenAiAgentRunner testRunner({
  required GenAiAgentToolRegistry tools,
  required GenAiAgentChatStream streamChat,
  GenAiAgentLimits limits = const GenAiAgentLimits(),
}) =>
    GenAiAgentRunner(
      tools: tools,
      limits: limits,
      streamChat: (request, cancellation) =>
          streamChat(request, cancellation).map(
        (event) => event is GenAiTextDelta
            ? GenAiTextDelta(
                event.text.replaceAll(
                  testNonce,
                  genAiAgentNonceFromSystem(request.history.first.content)!,
                ),
              )
            : event,
      ),
    );

String call(
  String id, {
  String name = 'read_data',
  Map<String, Object?> args = const {},
}) =>
    encodeGenAiAgentCall(
      GenAiAgentToolCall(id: id, name: name, arguments: args),
      nonce: testNonce,
    );

GenAiChatRequest request({
  String prompt = 'Help with campus.',
  List<GenAiMessage> history = const [],
}) =>
    GenAiChatRequest(
      chatGroupId: 'agent-test',
      prompt: prompt,
      aiType: 'demo',
      rootAiType: 'demo',
      history: history,
    );

Stream<GenAiChatEvent> answer(
  String value, {
  GenAiFinishReason reason = GenAiFinishReason.stop,
}) async* {
  yield GenAiTextDelta(value);
  yield GenAiChatFinished(reason);
}

GenAiAgentTool tool({
  String name = 'read_data',
  bool mutation = false,
  Map<String, Object?> schema = objectSchema,
  Future<Object?> Function(GenAiAgentToolContext)? execute,
}) =>
    GenAiAgentTool(
      name: name,
      description: 'Test tool.',
      parameters: schema,
      prepare: (_, context) async => GenAiAgentPreparedTool(
        requiresApproval: mutation,
        summary: 'Concrete test action',
        details: {'price': 5},
        execute: () async => execute == null ? {'value': 42} : execute(context),
      ),
    );

Future<List<GenAiAgentEvent>> run(
  GenAiAgentRunner runner, {
  GenAiChatRequest? input,
  GenAiCancellation? cancellation,
  bool Function()? isCurrent,
  GenAiAgentApproval? approve,
  List<GenAiAgentHistoryEntry>? transcript,
  Future<void> Function(Map<String, Object?> snapshot)? checkpoint,
}) =>
    runner
        .run(
          request: input ?? request(),
          cancellation: cancellation ?? GenAiCancellation(),
          isCurrent: isCurrent ?? () => true,
          approve: approve ?? (_, __, ___) async => true,
          transcript: transcript,
          checkpoint: checkpoint,
        )
        .toList();

void main() {
  test(
      'strict nonce parser rejects malformed live envelopes and leaves examples as text',
      () {
    expect(
      parseGenAiAgentResponse(call('one'), nonce: testNonce)!.name,
      'read_data',
    );
    for (final ordinary in [
      '{"call_id":"one","name":"read_data","arguments":{}}',
      '```tool_call\n{"call_id":"one","name":"read_data","arguments":{}}\n```',
      '```json\n{"message":"ordinary JSON"}\n```',
      'The tool_call format is documented here.',
      '```xml\n${call('example')}\n```',
      '> ${call('example')}',
      '<|open|>call tool="read_data"',
    ]) {
      expect(parseGenAiAgentResponse(ordinary, nonce: testNonce), isNull);
    }
    for (final malformed in [
      '${call('one')}\n${call('two')}',
      call('one').replaceFirst(testNonce, 'old_nonce_0123456789'),
      call('one')
          .replaceFirst('"call_id":"one"', '"call_id":"one","call_id":"two"'),
      call('one').replaceFirst('"arguments":{}', '"arguments":{"x":1,"x":2}'),
      call('one')
          .replaceFirst('"arguments":{}', '"arguments":{},"execute":true'),
      call('one').replaceFirst('{', '{invalid'),
      '<techpie-agent-call version="2">incomplete',
      '',
    ]) {
      expect(
        () => parseGenAiAgentResponse(malformed, nonce: testNonce),
        throwsA(isA<GenAiAgentToolException>()),
      );
    }
  });

  test(
      'Kimi native tool syntax repairs without execution and stays inert in examples',
      () async {
    const native = '<|open|>tools<|sep|><|open|>call tool="read_data" '
        'index="1"<|sep|><|close|>call<|sep|><|close|>tools<|sep|>';
    for (final example in ['```text\n$native\n```', '`$native`', '> $native']) {
      expect(parseGenAiAgentResponse(example, nonce: testNonce), isNull);
    }
    var executed = 0;
    var turns = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool(execute: (_) async => ++executed)]),
      streamChat: (r, _) {
        turns++;
        if (turns == 1) return answer('我先调用工具。$native');
        if (turns == 2) {
          expect(executed, 0);
          expect(r.prompt, contains('unsupported_tool_format'));
          expect(r.prompt, contains('No tool executed'));
          return answer(call('corrected'));
        }
        expect(executed, 1);
        return answer('Done.');
      },
    );
    final events = await run(runner);
    expect(
      events.where((e) => e.kind == GenAiAgentEventKind.protocolError),
      hasLength(1),
    );
    expect(events.last.kind, GenAiAgentEventKind.completed);
    expect(executed, 1);

    final stuck = testRunner(
      tools: GenAiAgentToolRegistry([tool(execute: (_) async => ++executed)]),
      streamChat: (_, __) => answer(native),
    );
    final failed = await run(stuck);
    expect(failed.last.failure?.kind, GenAiFailureKind.protocol);
    expect(
      failed.where((e) => e.kind == GenAiAgentEventKind.protocolError),
      hasLength(3),
    );
    expect(executed, 1);
  });

  test(
      'copied history calls request repair without authorizing archived actions',
      () async {
    final archived = decodeGenAiAgentRecord(call('archive'))!;
    final source = archived.content;
    for (final example in ['```xml\n$source\n```', '> $source']) {
      expect(parseGenAiAgentResponse(example, nonce: testNonce), isNull);
    }
    var executed = 0;
    var turns = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool(execute: (_) async => ++executed)]),
      streamChat: (r, _) {
        if (++turns == 1) return answer(source);
        expect(executed, 0);
        expect(r.prompt, contains('historical_tool_format'));
        return answer('No action was taken.');
      },
    );
    final events = await run(runner);
    expect(events.last.kind, GenAiAgentEventKind.completed);
    expect(
      events.where((e) => e.kind == GenAiAgentEventKind.toolProposed),
      isEmpty,
    );
    expect(executed, 0);
    expect(decodeGenAiAgentRecord(source)!.call!.id, 'archive');
  });

  test('registry validates nested types, range, enum, and unknown arguments',
      () {
    final registry = GenAiAgentToolRegistry([
      tool(
        schema: {
          'type': 'object',
          'required': ['week', 'sport', 'players'],
          'properties': {
            'week': {'type': 'integer', 'minimum': 1, 'maximum': 30},
            'sport': {
              'type': 'string',
              'enum': ['tennis', 'badminton'],
            },
            'players': {
              'type': 'array',
              'maxItems': 2,
              'items': {'type': 'string', 'minLength': 1},
            },
          },
        },
      ),
    ]);
    final good = {
      'week': 3,
      'sport': 'tennis',
      'players': ['test'],
    };
    registry.validate(
      GenAiAgentToolCall(id: 'x', name: 'read_data', arguments: good),
    );
    for (final args in [
      <String, Object?>{},
      {...good, 'week': 0},
      {...good, 'week': 1.0},
      {...good, 'sport': 'invented'},
      {...good, 'extra': true},
      {
        ...good,
        'players': [''],
      },
    ]) {
      expect(
        () => registry.validate(
          GenAiAgentToolCall(id: 'x', name: 'read_data', arguments: args),
        ),
        throwsA(isA<GenAiAgentToolException>()),
      );
    }
  });

  test(
      'read loop sends schema in system prompt and structured result into next turn',
      () async {
    final requests = <GenAiChatRequest>[];
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool()]),
      streamChat: (r, _) {
        requests.add(r);
        return answer(
          requests.length == 1 ? call('one') : 'Your campus result is 42.',
        );
      },
    );
    final events = await run(runner);
    expect(events.last.kind, GenAiAgentEventKind.completed);
    expect(events.last.text, 'Your campus result is 42.');
    expect(
      requests.first.history.first.content,
      startsWith(genAiAgentProtocolMarker),
    );
    expect(requests.last.prompt, contains('"result":{"value":42}'));
    expect(requests.every((r) => r.chatGroupId == 'agent-test'), isTrue);
    expect(events.last.history.map((m) => m.role), [
      GenAiRole.user,
      GenAiRole.assistant,
      GenAiRole.user,
      GenAiRole.assistant,
    ]);
  });

  test('malformed/unknown calls produce recoverable feedback without execution',
      () async {
    var executed = 0;
    var turns = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool(execute: (_) async => ++executed)]),
      streamChat: (r, _) {
        turns++;
        return answer(
          switch (turns) {
            1 => call('bad', name: 'shell'),
            2 => call('badargs', args: {'extra': true}),
            3 => call('good'),
            _ => 'Done.'
          },
        );
      },
    );
    final events = await run(runner);
    expect(executed, 1);
    expect(
      events.where((e) => e.kind == GenAiAgentEventKind.protocolError),
      hasLength(2),
    );
    expect(events.last.kind, GenAiAgentEventKind.completed);
  });

  test(
      'reasoning never dispatches a tool and rejected finish reasons never execute',
      () async {
    var executed = 0;
    final tools =
        GenAiAgentToolRegistry([tool(execute: (_) async => ++executed)]);
    final reasoningRunner = testRunner(
      tools: tools,
      streamChat: (_, __) async* {
        yield GenAiReasoningDelta(call('hidden'));
        yield const GenAiTextDelta('Safe final answer.');
        yield const GenAiChatFinished(GenAiFinishReason.stop);
      },
    );
    expect((await run(reasoningRunner)).last.text, 'Safe final answer.');
    for (final reason in [
      GenAiFinishReason.length,
      GenAiFinishReason.contentFilter,
      GenAiFinishReason.other,
    ]) {
      final runner = testRunner(
        tools: tools,
        streamChat: (_, __) => answer(call('partial'), reason: reason),
      );
      expect((await run(runner)).last.kind, GenAiAgentEventKind.failed);
    }
    final eofRunner = testRunner(
      tools: tools,
      streamChat: (_, __) => Stream.value(GenAiTextDelta(call('eof'))),
    );
    expect((await run(eofRunner)).last.kind, GenAiAgentEventKind.failed);
    expect(executed, 0);
  });

  test('approval is concrete and a changed account blocks the pending mutation',
      () async {
    final approval = Completer<bool>();
    final waiting = Completer<void>();
    var active = true;
    var executed = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([
        tool(
          mutation: true,
          execute: (_) async => ++executed,
        ),
      ]),
      streamChat: (_, __) => answer(call('one')),
    );
    final running = run(
      runner,
      isCurrent: () => active,
      approve: (_, __, prepared) {
        expect(prepared.details['price'], 5);
        expect(() => prepared.details['price'] = 7, throwsUnsupportedError);
        waiting.complete();
        return approval.future;
      },
    );
    await waiting.future;
    active = false;
    approval.complete(true);
    expect((await running).last.failure?.kind, GenAiFailureKind.accountChanged);
    expect(executed, 0);
  });

  test('account change at approval yield prevents stale approval callbacks',
      () async {
    var active = true;
    var approvals = 0;
    var executions = 0;
    final events = <GenAiAgentEvent>[];
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([
        tool(mutation: true, execute: (_) async => ++executions),
      ]),
      streamChat: (_, __) => answer(call('scoped-approval')),
    );
    await for (final event in runner.run(
      request: request(),
      cancellation: GenAiCancellation(),
      isCurrent: () => active,
      approve: (_, __, ___) async {
        approvals++;
        return true;
      },
    )) {
      events.add(event);
      if (event.kind == GenAiAgentEventKind.approvalRequired) active = false;
    }
    expect(approvals, 0);
    expect(executions, 0);
    expect(events.last.failure?.kind, GenAiFailureKind.accountChanged);
    expect(events.last.history, isEmpty);
  });

  test('account cancellation during a tool scrubs its private continuation',
      () async {
    final cancellation = GenAiCancellation();
    final started = Completer<void>();
    final result = Completer<Object?>();
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([
        tool(
          execute: (_) {
            started.complete();
            return result.future;
          },
        ),
      ]),
      streamChat: (_, __) => answer(call('private-read')),
    );
    final pending = run(
      runner,
      input: request(prompt: 'Private assignment question'),
      cancellation: cancellation,
    );
    await started.future;
    cancellation.cancel(GenAiFailureKind.accountChanged);
    final events = await pending;
    result.complete({'private': 'late result'});
    expect(events.last.failure?.kind, GenAiFailureKind.accountChanged);
    expect(events.last.history, isEmpty);
    expect(runner.transcriptForConversation('agent-test'), isEmpty);
  });

  test(
      'cancellation interrupts pending approval without waiting for a user reply',
      () async {
    final cancellation = GenAiCancellation();
    final approval = Completer<bool>();
    final waiting = Completer<void>();
    var executed = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([
        tool(
          mutation: true,
          execute: (_) async => ++executed,
        ),
      ]),
      streamChat: (_, __) => answer(call('one')),
    );
    final running = run(
      runner,
      cancellation: cancellation,
      approve: (_, __, ___) {
        waiting.complete();
        return approval.future;
      },
    );
    await waiting.future;
    cancellation.cancel();
    expect((await running).last.kind, GenAiAgentEventKind.cancelled);
    approval.complete(true);
    expect(executed, 0);
  });

  test(
      'denial and identical approved mutations are not repeated across followups',
      () async {
    for (final allowed in [false, true]) {
      var turns = 0;
      var executions = 0;
      var approvals = 0;
      final runner = testRunner(
        tools: GenAiAgentToolRegistry([
          tool(
            mutation: true,
            execute: (_) async => ++executions,
          ),
        ]),
        streamChat: (_, __) {
          turns++;
          return answer(turns.isOdd ? call('id_$turns') : 'Done.');
        },
      );
      final first = await run(
        runner,
        approve: (_, __, ___) async {
          approvals++;
          return allowed;
        },
      );
      final second = await run(
        runner,
        input: request(prompt: 'Continue.', history: first.last.history),
        approve: (_, __, ___) async {
          approvals++;
          return allowed;
        },
      );
      expect(executions, allowed ? 1 : 0);
      expect(approvals, 1);
      expect(
        second
            .firstWhere((e) => e.kind == GenAiAgentEventKind.toolFinished)
            .result!['reused'],
        true,
      );
    }
  });

  test(
      'tool timeout cancels late work and preserves unknown-effect deduplication',
      () async {
    final late = Completer<void>();
    var executions = 0;
    var turns = 0;
    GenAiAgentToolContext? captured;
    final runner = testRunner(
      limits: const GenAiAgentLimits(toolTimeout: Duration(milliseconds: 10)),
      tools: GenAiAgentToolRegistry([
        tool(
          mutation: true,
          execute: (context) async {
            captured = context;
            await late.future;
            context.checkActive();
            executions++;
            return true;
          },
        ),
      ]),
      streamChat: (_, __) {
        turns++;
        return answer(turns == 1 || turns == 3 ? call('id_$turns') : 'Done.');
      },
    );
    final first = await run(runner);
    expect(captured!.cancellation.isCancelled, isTrue);
    final failedTool =
        first.firstWhere((e) => e.kind == GenAiAgentEventKind.toolFinished);
    expect(
      (failedTool.result!['error']! as Map<String, Object?>)['code'],
      'outcome_unknown',
    );
    late.complete();
    await Future<void>.delayed(Duration.zero);
    final second = await run(runner);
    expect(
      second
          .firstWhere((e) => e.kind == GenAiAgentEventKind.toolFinished)
          .result!['reused'],
      true,
    );
    expect(executions, 0);
  });

  test('late preparation after cancellation cannot reach execution', () async {
    final prepared = Completer<GenAiAgentPreparedTool>();
    final preparing = Completer<void>();
    final cancellation = GenAiCancellation();
    var executed = false;
    final t = GenAiAgentTool(
      name: 'read_data',
      description: 'Test',
      parameters: objectSchema,
      prepare: (_, __) {
        preparing.complete();
        return prepared.future;
      },
    );
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([t]),
      streamChat: (_, __) => answer(call('one')),
    );
    final running = run(runner, cancellation: cancellation);
    await preparing.future;
    cancellation.cancel();
    expect((await running).last.kind, GenAiAgentEventKind.cancelled);
    prepared.complete(
      GenAiAgentPreparedTool(
        execute: () async {
          executed = true;
          return null;
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(executed, isFalse);
  });

  test('a repeated call id with different arguments does not execute',
      () async {
    var turns = 0;
    var executions = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([
        tool(
          schema: {
            'type': 'object',
            'properties': {
              'n': {'type': 'integer'},
            },
          },
          execute: (_) async => ++executions,
        ),
      ]),
      streamChat: (_, __) {
        turns++;
        return answer(turns < 3 ? call('same', args: {'n': turns}) : 'Done.');
      },
    );
    final events = await run(runner);
    expect(executions, 1);
    final results = events
        .where((e) => e.kind == GenAiAgentEventKind.toolFinished)
        .toList();
    expect(
      (results.last.result!['error']! as Map<String, Object?>)['code'],
      'reused_call_id',
    );
  });

  test('account change at model progress yield prevents any new model request',
      () async {
    var active = true;
    var requests = 0;
    final events = <GenAiAgentEvent>[];
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([]),
      streamChat: (_, __) {
        requests++;
        return answer('Must not be requested.');
      },
    );
    await for (final event in runner.run(
      request: request(),
      cancellation: GenAiCancellation(),
      isCurrent: () => active,
      approve: (_, __, ___) async => true,
    )) {
      events.add(event);
      if (event.kind == GenAiAgentEventKind.modelStarted) active = false;
    }
    expect(requests, 0);
    expect(events.last.failure?.kind, GenAiFailureKind.accountChanged);
    expect(events.last.history, isEmpty);
  });

  test(
      'denied action stays denied in continuation when cancelled after feedback',
      () async {
    final cancellation = GenAiCancellation();
    final events = <GenAiAgentEvent>[];
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool(mutation: true)]),
      streamChat: (_, __) => answer(call('denied')),
    );
    await for (final event in runner.run(
      request: request(),
      cancellation: cancellation,
      isCurrent: () => true,
      approve: (_, __, ___) async => false,
    )) {
      events.add(event);
      if (event.kind == GenAiAgentEventKind.toolFinished) cancellation.cancel();
    }
    expect(events.last.kind, GenAiAgentEventKind.cancelled);
    expect(events.last.history.last.content, contains('approval_denied'));
    expect(events.last.history.last.content, isNot(contains('interrupted')));
  });

  test('step budget retains the last tool feedback for safe continuation',
      () async {
    final runner = testRunner(
      limits: const GenAiAgentLimits(maxTurns: 1),
      tools: GenAiAgentToolRegistry([tool()]),
      streamChat: (_, __) => answer(call('one')),
    );
    final events = await run(runner);
    expect(events.last.kind, GenAiAgentEventKind.failed);
    expect(events.last.history.last.content, contains('"ok":true'));
  });

  test(
      'compaction keeps the current followup goal through subsequent tool turns',
      () async {
    final requests = <GenAiChatRequest>[];
    final oldHistory = <GenAiMessage>[
      const GenAiMessage(role: GenAiRole.user, content: 'An old goal.'),
      for (var index = 0; index < 6; index++) ...[
        GenAiMessage(role: GenAiRole.assistant, content: 'x' * 700),
        GenAiMessage(role: GenAiRole.user, content: 'y' * 700),
      ],
      const GenAiMessage(
        role: GenAiRole.assistant,
        content: 'Old task completed.',
      ),
    ];
    final runner = testRunner(
      limits: const GenAiAgentLimits(maxContextCharacters: 7000),
      tools: GenAiAgentToolRegistry([tool(execute: (_) async => 'z' * 900)]),
      streamChat: (r, _) {
        requests.add(r);
        return answer(
          requests.length <= 4 ? call('id_${requests.length}') : 'Done.',
        );
      },
    );
    final events = await run(
      runner,
      input: request(prompt: 'CURRENT GOAL: my schedule', history: oldHistory),
    );
    expect(events.last.kind, GenAiAgentEventKind.completed);
    for (final r in requests.skip(1)) {
      expect(
        r.history.any((m) => m.content == 'CURRENT GOAL: my schedule'),
        isTrue,
      );
      expect(
        r.prompt.length +
            r.history.fold<int>(0, (n, m) => n + m.content.length),
        lessThanOrEqualTo(7000),
      );
    }
  });

  test(
      'normalized effect keys prevent retries with explicit versus omitted defaults',
      () async {
    var turns = 0;
    var executions = 0;
    var approvals = 0;
    final normalized = GenAiAgentTool(
      name: 'read_data',
      description: 'Normalized mutation',
      parameters: {
        'type': 'object',
        'properties': {
          'width': {'type': 'integer'},
        },
      },
      prepare: (args, context) async => GenAiAgentPreparedTool(
        requiresApproval: true,
        effectKey: 'width:${args['width'] ?? 1024}',
        execute: () async {
          executions++;
          throw const GenAiFailure(GenAiFailureKind.timeout);
        },
      ),
    );
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([normalized]),
      streamChat: (_, __) {
        turns++;
        return answer(
          switch (turns) {
            1 => call('first'),
            2 => call('equivalent', args: {'width': 1024}),
            _ => 'Done.',
          },
        );
      },
    );
    final events = await run(
      runner,
      approve: (_, __, ___) async {
        approvals++;
        return true;
      },
    );
    expect(executions, 1);
    expect(approvals, 1);
    final result = events
        .where((e) => e.kind == GenAiAgentEventKind.toolFinished)
        .last
        .result!;
    expect(result['reused'], true);
    expect(
      (result['error']! as Map<String, Object?>)['code'],
      'outcome_unknown',
    );
  });

  test('prepared execution deadline extends only the execution phase',
      () async {
    var turns = 0;
    final slow = GenAiAgentTool(
      name: 'read_data',
      description: 'Slow image',
      parameters: objectSchema,
      prepare: (_, context) async => GenAiAgentPreparedTool(
        executionTimeout: const Duration(milliseconds: 200),
        execute: () async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          context.checkActive();
          return 'completed';
        },
      ),
    );
    final runner = testRunner(
      limits: const GenAiAgentLimits(toolTimeout: Duration(milliseconds: 10)),
      tools: GenAiAgentToolRegistry([slow]),
      streamChat: (_, __) => answer(++turns == 1 ? call('one') : 'Done.'),
    );
    final events = await run(runner);
    expect(
      events
          .firstWhere((e) => e.kind == GenAiAgentEventKind.toolFinished)
          .result!['ok'],
      true,
    );
  });

  test('output and run deadlines terminate stalled or oversized model streams',
      () async {
    final huge = testRunner(
      limits: const GenAiAgentLimits(maxOutputCharacters: 20),
      tools: GenAiAgentToolRegistry([]),
      streamChat: (_, __) => answer('x' * 21),
    );
    expect((await run(huge)).last.failure?.kind, GenAiFailureKind.protocol);
    final stalledStream = StreamController<GenAiChatEvent>();
    final stalled = testRunner(
      limits: const GenAiAgentLimits(runTimeout: Duration(milliseconds: 10)),
      tools: GenAiAgentToolRegistry([]),
      streamChat: (_, __) => stalledStream.stream,
    );
    expect((await run(stalled)).last.failure?.kind, GenAiFailureKind.timeout);
    await stalledStream.close();
  });

  test(
      'raw service exceptions are sanitized and oversized tool results are bounded',
      () async {
    var turns = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([
        tool(execute: (_) async => throw Exception('secret-token=123')),
        tool(name: 'huge', execute: (_) async => 'x' * 7000),
      ]),
      streamChat: (_, __) {
        turns++;
        return answer(
          switch (turns) {
            1 => call('one'),
            2 => call('two', name: 'huge'),
            _ => 'Done.'
          },
        );
      },
    );
    final events = await run(runner);
    final results = events
        .where((e) => e.kind == GenAiAgentEventKind.toolFinished)
        .toList();
    expect(jsonEncode(results.first.result), isNot(contains('secret-token')));
    expect(
      (results.last.result!['error']! as Map<String, Object?>)['code'],
      'result_too_large',
    );
  });
  test('fresh request nonces reject replay while archived calls stay inert',
      () async {
    final requests = <GenAiChatRequest>[];
    String? firstNonce;
    var executions = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool(execute: (_) async => ++executions)]),
      streamChat: (request, _) {
        requests.add(request);
        final nonce = genAiAgentNonceFromSystem(request.history.first.content)!;
        firstNonce ??= nonce;
        if (requests.length == 1) return answer(call('first'));
        if (requests.length == 2) {
          return answer(
            encodeGenAiAgentCall(
              GenAiAgentToolCall(
                id: 'replay',
                name: 'read_data',
                arguments: const {},
              ),
              nonce: firstNonce!,
            ),
          );
        }
        return answer('Done.');
      },
    );
    final events = await run(runner);
    expect(executions, 1);
    expect(
      events.where((event) => event.kind == GenAiAgentEventKind.protocolError),
      hasLength(1),
    );
    expect(
      requests
          .map((r) => genAiAgentNonceFromSystem(r.history.first.content))
          .toSet(),
      hasLength(3),
    );
    final secondHistory = requests[1]
        .history
        .skip(1)
        .map((message) => message.content)
        .join('\n');
    expect(secondHistory, contains('<techpie-agent-history version="2">'));
    expect(secondHistory, isNot(contains(firstNonce!)));
    expect(
      runner
          .transcriptForConversation('agent-test')
          .where((entry) => entry.call != null),
      hasLength(1),
    );
  });

  test(
      'malformed current frame recovers but ordinary JSON finishes without any call',
      () async {
    var rounds = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool()]),
      streamChat: (_, __) => answer(
        ++rounds == 1
            ? call('bad').replaceFirst('{', '{broken')
            : '{"answer":"ordinary JSON"}',
      ),
    );
    final events = await run(runner);
    expect(
      events.where((event) => event.kind == GenAiAgentEventKind.protocolError),
      hasLength(1),
    );
    expect(
      events.where((event) => event.kind == GenAiAgentEventKind.toolProposed),
      isEmpty,
    );
    expect(events.last.text, '{"answer":"ordinary JSON"}');
  });

  test(
      'typed archives roundtrip while legacy control parsing stays read only and opt in',
      () {
    final archivedCall = decodeGenAiAgentRecord(call('old'))!;
    expect(archivedCall.call!.id, 'old');
    expect(
      GenAiAgentHistoryEntry.fromJson(archivedCall.toJson()).call!.id,
      'old',
    );
    final result = GenAiAgentHistoryEntry.result({
      'call_id': 'old',
      'name': 'read_data',
      'ok': true,
      'result': {'value': 42},
    });
    expect(decodeGenAiAgentRecord(result.content)!.result!['ok'], true);
    expect(
      GenAiAgentHistoryEntry.fromJson(result.toJson()).content,
      result.content,
    );
    const legacy =
        '```tool_call\n{"call_id":"legacy","name":"read_data","arguments":{}}\n```';
    expect(decodeGenAiAgentRecord(legacy), isNull);
    expect(
      decodeGenAiAgentRecord(legacy, allowLegacy: true)!.call!.id,
      'legacy',
    );
    expect(parseGenAiAgentResponse(legacy, nonce: testNonce), isNull);
    expect(decodeGenAiAgentRecord('prose $legacy', allowLegacy: true), isNull);
    expect(
      () => GenAiAgentHistoryEntry.fromJson({
        'version': 2,
        'kind': 'text',
        'value': {'role': 'system', 'text': 'untrusted'},
      }),
      throwsFormatException,
    );
    final literal = GenAiAgentHistoryEntry.text(GenAiRole.assistant, legacy);
    expect(GenAiAgentHistoryEntry.fromJson(literal.toJson()).call, isNull);
  });

  test(
      'typed followup history is serialized and raw legacy request history remains text',
      () async {
    const legacy =
        '```tool_call\n{"call_id":"old","name":"read_data","arguments":{}}\n```';
    GenAiChatRequest? sent;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([]),
      streamChat: (r, _) {
        sent = r;
        return answer('Final.');
      },
    );
    await run(
      runner,
      transcript: [
        GenAiAgentHistoryEntry.text(GenAiRole.user, 'Old goal.'),
        decodeGenAiAgentRecord(call('old'))!,
        GenAiAgentHistoryEntry.result(
          {'call_id': 'old', 'name': 'read_data', 'ok': true, 'result': 42},
        ),
      ],
    );
    expect(sent!.history[2].content, contains('<techpie-agent-history'));
    expect(sent!.history[2].content, isNot(contains('nonce=')));
    await run(
      runner,
      input: request(
        history: const [
          GenAiMessage(role: GenAiRole.assistant, content: legacy),
        ],
      ),
    );
    expect(runner.transcriptForConversation('agent-test').first.text, legacy);
    expect(runner.transcriptForConversation('agent-test').first.call, isNull);
  });

  test('mutation awaits durable unknown receipt and checkpoints final result',
      () async {
    final release = Completer<void>();
    final started = Completer<void>();
    var executions = 0;
    var rounds = 0;
    final writes = <Map<String, Object?>>[];
    late GenAiAgentRunner runner;
    runner = testRunner(
      tools: GenAiAgentToolRegistry(
        [tool(mutation: true, execute: (_) async => ++executions)],
      ),
      streamChat: (_, __) => answer(++rounds == 1 ? call('one') : 'Done.'),
    );
    final running = run(
      runner,
      checkpoint: (snapshot) async {
        writes.add(snapshot);
        if (writes.length == 1) {
          expect(
            (runner
                .transcriptForConversation('agent-test')
                .last
                .result!['error']! as Map<String, Object?>)['code'],
            'outcome_unknown',
          );
          started.complete();
          await release.future;
        }
      },
    );
    await started.future;
    expect(executions, 0);
    release.complete();
    expect((await running).last.kind, GenAiAgentEventKind.completed);
    expect(executions, 1);
    expect(writes, hasLength(2));
    final first = (writes.first['effects']! as Map<String, Object?>)
        .values
        .single as Map<String, Object?>;
    final last = (writes.last['effects']! as Map<String, Object?>).values.single
        as Map<String, Object?>;
    expect(
      (first['error']! as Map<String, Object?>)['code'],
      'outcome_unknown',
    );
    expect(last['ok'], true);
  });

  test(
      'checkpoint failure before dispatch fails closed and cannot retry after restart',
      () async {
    var executions = 0;
    final registry = GenAiAgentToolRegistry(
      [tool(mutation: true, execute: (_) async => ++executions)],
    );
    final runner =
        testRunner(tools: registry, streamChat: (_, __) => answer(call('one')));
    final events = await run(
      runner,
      checkpoint: (_) async => throw StateError('disk unavailable'),
    );
    expect(events.last.failure?.kind, GenAiFailureKind.storage);
    expect(executions, 0);
    var rounds = 0;
    final restored = testRunner(
      tools: registry,
      streamChat: (_, __) => answer(++rounds == 1 ? call('new_id') : 'Done.'),
    );
    restored.restoreConversation(
      'agent-test',
      runner.snapshotConversation('agent-test'),
    );
    var approvals = 0;
    final resumed = await run(
      restored,
      approve: (_, __, ___) async {
        approvals++;
        return true;
      },
    );
    expect(approvals, 0);
    expect(executions, 0);
    expect(
      resumed
          .firstWhere(
            (event) => event.kind == GenAiAgentEventKind.toolFinished,
          )
          .result!['reused'],
      true,
    );
  });

  test(
      'persisted unknown receipt blocks repeats when post-dispatch persistence fails',
      () async {
    var executions = 0;
    var writes = 0;
    Map<String, Object?>? durable;
    final registry = GenAiAgentToolRegistry(
      [tool(mutation: true, execute: (_) async => ++executions)],
    );
    final runner =
        testRunner(tools: registry, streamChat: (_, __) => answer(call('one')));
    final events = await run(
      runner,
      checkpoint: (snapshot) async {
        if (++writes == 1) {
          durable = snapshot;
          return;
        }
        throw const GenAiFailure(GenAiFailureKind.storage);
      },
    );
    expect(events.last.failure?.kind, GenAiFailureKind.storage);
    expect(executions, 1);
    var rounds = 0;
    final restored = testRunner(
      tools: registry,
      streamChat: (_, __) => answer(++rounds == 1 ? call('new_id') : 'Done.'),
    );
    restored.restoreConversation('agent-test', durable!);
    final resumed = await run(restored);
    expect(executions, 1);
    final result = resumed
        .firstWhere((event) => event.kind == GenAiAgentEventKind.toolFinished)
        .result!;
    expect(result['reused'], true);
    expect(
      (result['error']! as Map<String, Object?>)['code'],
      'outcome_unknown',
    );
  });

  test(
      'denials are persisted and snapshot restoration rejects pending or malformed state',
      () async {
    var rounds = 0;
    final runner = testRunner(
      tools: GenAiAgentToolRegistry([tool(mutation: true)]),
      streamChat: (_, __) => answer(++rounds == 1 ? call('one') : 'Done.'),
    );
    final writes = <Map<String, Object?>>[];
    await run(
      runner,
      approve: (_, __, ___) async => false,
      checkpoint: (snapshot) async {
        writes.add(snapshot);
      },
    );
    expect(writes, hasLength(1));
    final denied = (writes.single['effects']! as Map<String, Object?>)
        .values
        .single as Map<String, Object?>;
    expect(
      (denied['error']! as Map<String, Object?>)['code'],
      'approval_denied',
    );
    for (final invalid in [
      <String, Object?>{'version': 2, 'effects': {}},
      <String, Object?>{'version': 1, 'effects': {}, 'pending': true},
      <String, Object?>{
        'version': 1,
        'effects': {
          'read_data:{}': {'approved': true},
        },
      },
      <String, Object?>{
        'version': 1,
        'effects': {'other:{}': denied},
      },
    ]) {
      expect(
        () => runner.restoreConversation('other', invalid),
        throwsFormatException,
      );
    }
  });
}
