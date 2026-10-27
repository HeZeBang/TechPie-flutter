import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/application/genai_remote_history.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';

const nonce = 'remote_test_nonce_012345';

void main() {
  test('late completion cannot revive a cancelled ancestor or hide its follow-up', () {
    final stopped = GenAiConversationTurn('Long task', id: 'stopped', isAgent: true)
      ..phase = GenAiChatPhase.cancelled
      ..answer = 'Partial answer'
      ..contextUsage = const GenAiContextUsage(
        stage: GenAiContextStage.ready,
        estimatedInputUnits: 2000,
        allowedInputUnits: 10000,
        originalInputUnits: 9000,
        compacted: true,
      );
    final followup = GenAiConversationTurn('New question', id: 'next', parentId: stopped.id);
    GenAiSavedTurn row(GenAiConversationTurn turn, String answer, {bool carryStop = false}) =>
        GenAiSavedTurn(
          prompt: encodeGenAiRemoteRecord({
            'kind': 'exchange',
            'step_id': 'step-${turn.id}',
            'turn': turn.toRemoteInput(),
            'input': turn.prompt,
            if (carryStop) 'interrupted': [stopped.toInterruptedRecord()],
          }),
          answer: answer,
        );
    // Aborting Fetch cannot stop the upstream model: its old POST may be
    // persisted after a newer request carrying the explicit stop record.
    final rows = [
      row(followup, 'New answer', carryStop: true),
      row(stopped, encodeGenAiAgentFinal('Late full answer', nonce: nonce)),
    ];
    final recovered = decodeGenAiConversation('group', rows).archive.restoreTurns();
    expect(recovered.map((turn) => turn.id), ['stopped', 'next']);
    expect(recovered.first.phase, GenAiChatPhase.cancelled);
    expect(recovered.first.answer, 'Partial answer');
    expect(recovered.first.contextUsage?.toRecord(), stopped.contextUsage!.toRecord());
    expect(recovered.last.answer, 'New answer');
  });

  test('server-only recovery joins identified tools, preserves files and selects retry ancestry',
      () {
    final source = GenAiConversationTurn('Read my document', id: 'a', isAgent: true)
      ..attachedFileNames = ['notes.txt']
      ..attachedFileIds = ['file-a']
      ..attachedFileContents = {'file-a': 'Original numeric record: 5837'};
    final call = GenAiAgentToolCall(id: 'c1', name: 'get_semesters', arguments: const {});
    GenAiSavedTurn row(String step, GenAiConversationTurn turn, String input, String answer) =>
        GenAiSavedTurn(
          prompt: '【上传文件：notes.txt】\n${encodeGenAiRemoteRecord({
                'kind': 'exchange',
                'step_id': step,
                'turn': step == 's2' ? null : turn.toRemoteInput(),
                'turn_id': turn.id,
                'input': input,
                'agent': turn.isAgent,
                'thinking': true,
                'search': false,
                'aiType': 'Kimi-k3',
                'rootAiType': 'xinference',
                'contextUsage': step == 's4'
                    ? {'input': -1}
                    : {
                        'input': step == 's2' ? 2600 : 1500,
                        'limit': 10000,
                        'original': 9000,
                        'compacted': true,
                      },
              })}',
          answer: answer,
        );
    final rows = [
      row('s1', source, source.prompt, encodeGenAiAgentCall(call, nonce: nonce)),
      row(
        's2',
        source,
        encodeGenAiAgentResult(
          {
            'call_id': 'c1',
            'name': 'get_semesters',
            'ok': true,
            'result': {'semester': 3},
          },
          nonce: nonce,
        ),
        encodeGenAiAgentFinal('Semester 3.', nonce: nonce),
      ),
      row(
        's3',
        GenAiConversationTurn('Old followup', id: 'b', parentId: 'a'),
        'Old followup',
        'Old answer',
      ),
      row(
        's4',
        GenAiConversationTurn('Retry followup', id: 'c', parentId: 'a'),
        'Retry followup',
        'New answer',
      ),
    ];
    final recovered = decodeGenAiConversation('group', rows).archive.restoreTurns();
    expect(recovered.map((t) => t.id), ['a', 'c']);
    expect(recovered.first.attachedFileContents['file-a'], contains('5837'));
    expect(recovered.first.agentEvents['c1']!.result!['ok'], true);
    expect(recovered.first.answer, 'Semester 3.');
    expect(recovered.first.contextUsage?.estimatedInputUnits, 2600);
    expect(recovered.first.contextCompacted, isTrue);
    expect(recovered.last.contextUsage, isNull);
    expect(recovered.any((turn) => turn.isHistoryGap), isFalse);
    expect(recovered.first.phase, GenAiChatPhase.completed);
    expect(decodeGenAiRemoteRecord('arbitrary document prose ${rows.first.prompt}'), isNull);
    expect(recovered.last.answer, 'New answer');
    expect(recovered.first.evidenceEntries.where((e) => e.result != null), hasLength(1));
  });

  test('mixed record versions recover normalized mutation identities without duplicate receipts',
      () {
    final original = GenAiConversationTurn('Book a court', id: 'a', isAgent: true);
    final call = GenAiAgentToolCall(
      id: 'book',
      name: 'reserve_court',
      arguments: const {'action': 'book', 'court': 'Court One'},
    );
    const effectKey = 'reserve_court:court-id/date/slot';
    final receipt = <String, Object?>{
      'call_id': call.id,
      'name': call.name,
      'ok': true,
      'result': {'booking_id': 'booking-314'},
    };
    // Literal v1 framing exercises compatibility, rather than the v2 writer.
    final old = '<techpie-record version="1">\n${jsonEncode({
          'kind': 'exchange',
          'step_id': 'old-step',
          'turn': original.toRemoteInput(),
          'input': original.prompt,
          'agent': true,
          'aiType': 'Kimi-k3',
          'rootAiType': 'xinference',
        })}\n</techpie-record>';
    final compact = encodeGenAiRemoteRecord({
      'kind': 'exchange',
      'step_id': 'new-step',
      'turn_id': original.id,
      'turn': null,
      'input': encodeGenAiAgentResult(receipt, nonce: nonce),
      'effectKeys': [effectKey],
      'mutations': {'version': 1, 'effects': <String, Object?>{}},
      'approvalBudget': {'reserve_court': 1},
      'agent': true,
      'thinking': false,
      'search': false,
      'rootAiType': 'xinference',
    });
    final rows = [
      GenAiSavedTurn(prompt: old, answer: encodeGenAiAgentCall(call, nonce: nonce)),
      GenAiSavedTurn(
        prompt: compact,
        answer: encodeGenAiAgentFinal('Booked.', nonce: nonce),
        aiType: 'Kimi-k3',
      ),
    ];
    final archive = decodeGenAiConversation('group', rows).archive;
    final turn = archive.restoreTurns().single;
    expect(turn.phase, GenAiChatPhase.completed);
    expect(turn.agentEvents[call.id]!.result, receipt);
    expect(turn.approvalBudget['reserve_court'], 1);
    expect((archive.mutations['effects']! as Map)[effectKey], receipt);
    expect(archive.agentEnabled, true);
    expect(archive.modelAiType, 'Kimi-k3');
    expect(archive.modelRootAiType, 'xinference');
    final record = decodeGenAiRemoteRecord(compact)!;
    expect(record.keys, isNot(contains('mutations')));
    expect(record.keys, isNot(contains('agent')));
    expect(record.keys, isNot(contains('thinking')));
    expect('booking-314'.allMatches(compact), hasLength(1));
  });

  test('upload fallback parents migrate without reviving stale interrupted snapshots', () {
    final first = GenAiConversationTurn('Start', id: 'first');
    final document = GenAiConversationTurn('Read file', id: 'doc', parentId: 'first', isAgent: true)
      ..attachedFileIds = ['file']
      ..attachedFileNames = ['notes.txt']
      ..attachedFileContents = {'file': 'Seats: 144'};
    final followup = GenAiConversationTurn('Recall seats', id: 'next', parentId: 'legacy-2');
    final call = GenAiAgentToolCall(id: 'time', name: 'get_current_time', arguments: const {});
    GenAiSavedTurn row(
      String step,
      GenAiConversationTurn? turn,
      String input,
      String answer, {
      bool upload = false,
      List<Object?> interrupted = const [],
    }) =>
        GenAiSavedTurn(
          prompt: '${upload ? '【上传文件：notes.txt】\n' : ''}${encodeGenAiRemoteRecord({
                'kind': 'exchange',
                'step_id': step,
                'turn': turn?.toRemoteInput(),
                'turn_id': turn?.id ?? 'doc',
                'input': input,
                'interrupted': interrupted,
              })}',
          answer: answer,
        );
    final rows = [
      row('1', first, first.prompt, 'Ready'),
      row('2', document, document.prompt, encodeGenAiAgentCall(call, nonce: nonce), upload: true),
      row(
        '3',
        null,
        encodeGenAiAgentResult(
          {
            'call_id': 'time',
            'name': 'get_current_time',
            'ok': true,
            'result': {'time': '12:00'},
          },
          nonce: nonce,
        ),
        encodeGenAiAgentFinal('144 seats', nonce: nonce),
        upload: true,
      ),
      row(
        '4',
        followup,
        followup.prompt,
        '144',
        interrupted: [
          GenAiConversationTurn('obsolete raw wrapper', id: 'legacy-1', parentId: 'first')
              .toArchiveJson(),
        ],
      ),
    ];
    final turns = decodeGenAiConversation('group', rows).archive.restoreTurns();
    expect(turns.map((t) => t.id), ['first', 'doc', 'next']);
    expect(turns[1].agentEvents['time']!.result!['ok'], true);
    expect(turns[1].attachedFileContents['file'], 'Seats: 144');
    expect(turns.any((t) => t.isHistoryGap), false);
    // An unrelated missing parent must still break continuity.
    followup.parentId = 'legacy-99';
    final broken = decodeGenAiConversation('group', [
      ...rows.take(3),
      row('5', followup, followup.prompt, '144'),
    ]).archive.restoreTurns();
    expect(broken.first.isHistoryGap, true);
  });

  test('reopened image proposals retain operation scope for retry protection', () {
    final turn = GenAiConversationTurn(
      'Generate image',
      id: 'image-turn',
      actionScopeId: 'original-task',
      isAgent: true,
    );
    final call = GenAiAgentToolCall(id: 'image', name: 'generate_image', arguments: const {});
    final recovered = decodeGenAiConversation(
      'group',
      [
        GenAiSavedTurn(
          prompt: encodeGenAiRemoteRecord({
            'kind': 'exchange',
            'step_id': 'image-step',
            'turn': turn.toRemoteInput(),
            'input': turn.prompt,
          }),
          answer: encodeGenAiAgentCall(call, nonce: nonce),
        ),
      ],
    ).archive;
    expect(recovered.restoreTurns().single.actionScopeId, 'original-task');
    expect(recovered.restoreTurns().single.toArchiveJson()['actionScopeId'], 'original-task');
    expect(
      (recovered.mutations['effects']! as Map).keys,
      contains(genAiMutationReceiptKey(call, turnId: 'original-task')),
    );
  });

  test('missing tool receipt remains unknown and never recreates a pending approval', () {
    final source = GenAiConversationTurn('Book this court', id: 'a', isAgent: true);
    final rows = [
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'kind': 'exchange',
          'step_id': 's1',
          'turn': source.toArchiveJson(),
          'input': source.prompt,
        }),
        answer: encodeGenAiAgentCall(
          GenAiAgentToolCall(
            id: 'book',
            name: 'reserve_court',
            arguments: const {'action': 'book'},
          ),
          nonce: nonce,
        ),
      ),
    ];
    final turn = decodeGenAiConversation('group', rows).archive.restoreTurns().single;
    expect(turn.phase, GenAiChatPhase.interrupted);
    expect(turn.approvalBudget['reserve_court'], 1);
    expect((turn.agentEvents['book']!.result!['error']! as Map)['code'], 'outcome_unknown');
    expect(turn.agentEvents['book']!.prepared, isNull);
  });
}
