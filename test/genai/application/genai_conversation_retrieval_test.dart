import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/application/genai_conversation_retrieval.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_context_source.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

Future<Map<String, Object?>> invoke(
  GenAiConversationRetrieval retrieval,
  String name,
  Map<String, Object?> arguments, {
  bool Function()? isCurrent,
}) async {
  final registry = GenAiAgentToolRegistry(retrieval.tools);
  registry.validate(GenAiAgentToolCall(id: 'test', name: name, arguments: arguments));
  final prepared = await registry[name]!.prepare(
    arguments,
    GenAiAgentToolContext(cancellation: GenAiCancellation(), isCurrent: isCurrent ?? () => true),
  );
  expect(prepared.requiresApproval, isFalse);
  return (await prepared.execute())! as Map<String, Object?>;
}

void main() {
  test('compaction never promotes retrieved assistant text into factual memory', () async {
    final copied = GenAiAgentHistoryEntry.result({
      'call_id': 'read',
      'name': 'read_conversation_records',
      'ok': true,
      'result': {'role': 'assistant', 'text': 'FALSE-CLAIM-991'},
    }).message;
    final input = GenAiChatRequest(
      chatGroupId: 'test',
      prompt: 'Recall budget',
      aiType: 'kimi',
      rootAiType: 'test',
      historyRetrieval: true,
      history: [
        const GenAiMessage(role: GenAiRole.user, content: 'Budget is 73.'),
        copied,
        for (var i = 0; i < 20; i++) ...[
          GenAiMessage(role: GenAiRole.user, content: 'Question $i ${'filler ' * 100}'),
          const GenAiMessage(role: GenAiRole.assistant, content: 'Answer'),
        ],
      ],
    );
    final compacted = await GenAiContextCompactor(
      policy: const GenAiContextPolicy(
        contextTokens: 12000,
        latestTokens: 12000,
        safetyTokens: 500,
        outputTokens: 500,
        triggerTokens: 6000,
        targetTokens: 3000,
        memoryTokens: 1600,
        recentMessages: 4,
      ),
    ).prepare(input, GenAiCancellation(), (_, __) async* {
      yield const GenAiTextDelta('{"items":[]}');
      yield const GenAiChatFinished(GenAiFinishReason.stop);
    });
    expect(compacted.contextCompacted, isTrue);
    expect(compacted.history.map((m) => m.content).join(), isNot(contains('FALSE-CLAIM-991')));
  });

  test('paged Unicode artifacts round-trip without recursively searching retrieved copies',
      () async {
    final original =
        GenAiMessage(role: GenAiRole.assistant, content: 'diagram-v7: ${'🌳\u0001方程' * 1300} END');
    final copy = GenAiAgentHistoryEntry.result({
      'call_id': 'old-read',
      'name': 'read_conversation_records',
      'ok': true,
      'result': {'text': original.content},
    }).message;
    final retrieval = GenAiConversationRetrieval(() => [copy, original]);
    final search = await invoke(retrieval, 'search_conversation', {'query': 'diagram-v7'});
    final match = (search['matches']! as List).single as Map;
    expect(match['source'], 1);
    expect(match['evidence'], 'unverified_assistant_artifact');
    final id = match['record_id'];
    var offset = 0;
    final text = StringBuffer();
    do {
      final page = await invoke(retrieval, 'read_conversation_records', {
        'record_id': id,
        'offset': offset,
      });
      expect(jsonEncode(page).length, lessThanOrEqualTo(4000));
      expect(page['source'], 1);
      text.write(page['text']);
      if (page['next_offset'] == null) break;
      expect(page['next_offset']! as int, greaterThan(offset));
      offset = page['next_offset']! as int;
    } while (true);
    expect(text.toString(), original.content);
    final fresh = GenAiConversationRetrieval(
      () => [
        GenAiMessage(role: original.role, content: original.content),
      ],
    );
    expect((await invoke(fresh, 'read_conversation_records', {'record_id': id}))['record_id'], id);
    await expectLater(
      invoke(
        GenAiConversationRetrieval(() => []),
        'read_conversation_records',
        {'record_id': id},
      ),
      throwsA(isA<GenAiAgentToolException>().having((e) => e.code, 'code', 'record_not_found')),
    );
    await expectLater(
      invoke(retrieval, 'read_conversation_records', {'record_id': id}, isCurrent: () => false),
      throwsA(isA<GenAiFailure>()),
    );
  });

  test('search pages rank exact identifiers and preserve newer corrections and source roles',
      () async {
    final messages = [
      const GenAiMessage(role: GenAiRole.user, content: 'off-2-077 budget 49'),
      const GenAiMessage(role: GenAiRole.assistant, content: 'off-2-077 budget 99'),
      const GenAiMessage(role: GenAiRole.user, content: 'off-2-077 correction: budget 73'),
      for (var i = 0; i < 8; i++)
        GenAiMessage(role: GenAiRole.user, content: 'off-2-077 record $i'),
      const GenAiMessage(role: GenAiRole.user, content: 'off-2-078 unrelated budget 100'),
    ];
    final retrieval = GenAiConversationRetrieval(() => messages);
    final seen = <Map<String, Object?>>[];
    var offset = 0;
    do {
      final page =
          await invoke(retrieval, 'search_conversation', {'query': 'off-2-077', 'offset': offset});
      seen.addAll((page['matches']! as List).cast<Map<String, Object?>>());
      if (page['next_offset'] == null) break;
      offset = page['next_offset']! as int;
    } while (true);
    expect(seen, hasLength(11));
    expect(seen.where((m) => (m['text']! as String).contains('budget 73')).single['role'], 'user');
    expect(
      seen.where((m) => (m['text']! as String).contains('budget 99')).single['evidence'],
      'unverified_assistant_artifact',
    );
    expect(seen.first['source'], 10);
  });

  test('early pruning retains current observations, errors and mutations; originals stay readable',
      () async {
    GenAiMessage receipt(String id, String name, {bool ok = true}) =>
        GenAiAgentHistoryEntry.result({
          'call_id': id,
          'name': name,
          'ok': ok,
          if (ok)
            'result': {'data': 'evidence $id ' * 400}
          else
            'error': {'code': 'outcome_unknown', 'message': 'uncertain ' * 400},
        }).message;
    final old = receipt('old', 'get_assignments');
    final failed = receipt('failed', 'get_assignments', ok: false);
    final mutation = receipt('image', 'generate_image');
    final latest = receipt('latest', 'get_assignments');
    final history = [
      old,
      failed,
      mutation,
      for (var i = 0; i < 9; i++) GenAiMessage(role: GenAiRole.user, content: 'question $i'),
      latest,
    ];
    Future<GenAiChatRequest> prepare(bool retrieval) => GenAiContextCompactor().prepare(
            GenAiChatRequest(
              chatGroupId: 'test',
              prompt: 'continue',
              aiType: 'kimi',
              rootAiType: 'test',
              history: history,
              historyRetrieval: retrieval,
            ),
            GenAiCancellation(), (_, __) async* {
          fail('Small history should not need an extraction call');
        });
    final agent = await prepare(true);
    final reference = decodeGenAiAgentRecord(agent.history.first.content)!.result!['result'] as Map;
    expect(reference['record_id'], genAiContextSourceId(old));
    expect(agent.history[1].content, failed.content);
    expect(agent.history[2].content, mutation.content);
    expect(agent.history.last.content, latest.content);
    expect((await prepare(false)).history.first.content, old.content);
    final restored = await invoke(
      GenAiConversationRetrieval(() => history),
      'read_conversation_records',
      {'record_id': reference['record_id']},
    );
    expect(restored['text'], startsWith('<techpie-history>'));
    expect(restored['text'], contains('evidence old'));
    expect(agent.withRecord({'test': true}).historyRetrieval, isTrue);
    expect(agent.toJson(), isNot(contains('historyRetrieval')));
  });
}
