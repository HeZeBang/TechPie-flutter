import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/application/genai_history_edit.dart';
import 'package:techpie/features/genai/application/genai_remote_history.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_context_record.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';

const nonce = 'history_edit_test_nonce_12345';

GenAiSavedTurn row(
  String id,
  GenAiConversationTurn turn,
  String answer, {
  String? continuation,
  Map<String, Object?> extra = const {},
}) =>
    GenAiSavedTurn(
      recordId: id,
      prompt: encodeGenAiRemoteRecord({
        'step_id': id,
        if (continuation == null) 'turn': turn.toRemoteInput() else 'turn_id': turn.id,
        'input': continuation ?? turn.prompt,
        ...extra,
      }),
      answer: answer,
    );

void main() {
  test('revert preserves a complete agent turn and drops downstream compaction and receipts', () {
    final a = GenAiConversationTurn('semester', id: 'a', isAgent: true);
    final b = GenAiConversationTurn('discard facts', id: 'b', parentId: 'a', isAgent: true);
    final call = GenAiAgentToolCall(id: 'call', name: 'get_semesters', arguments: {});
    final receipt = encodeGenAiAgentResult(
      {
        'call_id': 'call',
        'name': 'get_semesters',
        'ok': true,
        'result': {'semester': 3},
      },
      nonce: nonce,
    );
    final rows = [
      row('1', a, encodeGenAiAgentCall(call, nonce: nonce)),
      row('2', a, encodeGenAiAgentFinal('semester 3', nonce: nonce), continuation: receipt),
      GenAiSavedTurn(
        recordId: '3',
        prompt: genAiContextExtractionPrompt('a' * 64),
        answer: jsonEncode({
          'items': [
            {'fact': 'cached material'},
          ],
        }),
      ),
      row(
        '4',
        b,
        encodeGenAiAgentCall(call, nonce: nonce),
        extra: {
          'context': {
            'discarded-memory': {
              'items': ['discard facts'],
            },
          },
        },
      ),
      row('5', b, encodeGenAiAgentFinal('discard answer', nonce: nonce), continuation: receipt),
    ];
    final plan = GenAiHistoryEdit.plan('group', rows, 'a', keepTurn: true);
    expect(plan.removedIds, ['3', '4', '5']);
    final fresh = decodeGenAiConversation('group', plan.retained).archive;
    expect(fresh.contextMemory, isEmpty);
    final restored = fresh.restoreTurns().single;
    expect(restored.answer, 'semester 3');
    expect(restored.agentEvents['call']!.result!['ok'], true);
    expect(restored.phase, GenAiChatPhase.completed);
    final delete = GenAiHistoryEdit.plan('group', rows, 'b');
    expect(delete.removedIds, plan.removedIds);
  });

  test('deleting a retry cannot resurrect the abandoned answer or interrupted snapshot', () {
    final a = GenAiConversationTurn('keep', id: 'a');
    final old = GenAiConversationTurn('old', id: 'old', parentId: 'a')
      ..phase = GenAiChatPhase.cancelled;
    final retry = GenAiConversationTurn('retry', id: 'retry', parentId: 'a');
    final rows = [
      row('1', a, 'keep answer'),
      row('2', old, 'abandoned'),
      row(
        '3',
        retry,
        'new answer',
        extra: {
          'interrupted': [old.toInterruptedRecord()],
        },
      ),
    ];
    final plan = GenAiHistoryEdit.plan('group', rows, 'retry');
    expect(plan.removedIds, ['2', '3']);
    expect(decodeGenAiConversation('group', plan.retained).archive.restoreTurns().single.id, 'a');
    expect(GenAiHistoryEdit.plan('group', rows, 'a').removedIds, ['1', '2', '3']);
  });

  test('legacy agent calls and results are deleted as one turn', () {
    final call = GenAiAgentToolCall(id: 'c', name: 'get_current_time', arguments: {});
    final rows = [
      const GenAiSavedTurn(recordId: '1', prompt: 'keep', answer: 'kept'),
      GenAiSavedTurn(
        recordId: '2',
        prompt: 'time',
        answer: encodeGenAiAgentCall(call, nonce: nonce),
      ),
      GenAiSavedTurn(
        recordId: '3',
        prompt: encodeGenAiAgentResult(
          {
            'call_id': 'c',
            'name': 'get_current_time',
            'ok': true,
            'result': '12:00',
          },
          nonce: nonce,
        ),
        answer: encodeGenAiAgentFinal('12:00', nonce: nonce),
      ),
    ];
    final turns = decodeGenAiConversation('group', rows).archive.restoreTurns();
    expect(turns, hasLength(2));
    final plan = GenAiHistoryEdit.plan('group', rows, turns.last.id);
    expect(plan.removedIds, ['2', '3']);
    expect(
      decodeGenAiConversation('group', plan.retained).archive.restoreTurns().single.answer,
      'kept',
    );
  });

  test('missing record IDs and shared snapshots never authorize partial turn deletion', () {
    final a = GenAiConversationTurn('stopped', id: 'a')..phase = GenAiChatPhase.cancelled;
    final b = GenAiConversationTurn('followup', id: 'b', parentId: 'a');
    final shared = row(
      '1',
      b,
      'answer',
      extra: {
        'interrupted': [a.toInterruptedRecord()],
      },
    );
    expect(() => GenAiHistoryEdit.plan('group', [shared], 'b'), throwsA(isA<GenAiFailure>()));
    expect(
      () => GenAiHistoryEdit.plan(
        'group',
        [
          const GenAiSavedTurn(prompt: 'no ID', answer: 'answer'),
        ],
        'legacy-0',
      ),
      throwsA(isA<GenAiFailure>()),
    );
    // Deleting both turns needs only the shared server row and is safe.
    expect(GenAiHistoryEdit.plan('group', [shared], 'a').removedIds, ['1']);
  });
}
