import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_projection.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/application/genai_remote_history.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_context_source.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';

const nonce = 'remote_test_nonce_012345';

void main() {
  test('compact usage defaults and legacy usage recover the same ring state', () {
    final turn = GenAiConversationTurn('question', id: 'usage');
    for (final usage in [
      {'input': 1200, 'limit': 10000},
      {'input': 1200, 'limit': 10000, 'original': 1200, 'compacted': false},
      {'input': 1200, 'limit': 10000, 'original': 9000, 'compacted': true},
    ]) {
      final recovered = decodeGenAiConversation('group', [
        GenAiSavedTurn(
          prompt: encodeGenAiRemoteRecord({
            'step_id': nonce,
            'turn': turn.toRemoteInput(),
            'input': turn.prompt,
            'contextUsage': usage,
          }),
          answer: 'answer',
        ),
      ]).archive.turns.single;
      expect(recovered.contextUsage?.estimatedInputUnits, 1200);
      expect(recovered.contextUsage?.originalInputUnits, usage['original'] ?? 1200);
      expect(recovered.contextCompacted, usage['compacted'] ?? false);
      expect(
        recovered.contextUsage!.toRecord()!.containsKey('original'),
        usage['compacted'] == true,
      );
    }
    for (final field in ['original', 'compacted']) {
      expect(GenAiContextUsage.fromRecord({'input': 1200, 'limit': 10000, field: null}), isNull);
    }
  });

  test('a rejected stale-nonce call stays inert after server-only recovery', () {
    final turn = GenAiConversationTurn('Read the archive', id: 'nonce-repair', isAgent: true);
    const stale = 'old_step_nonce_0123456789';
    final rejected = GenAiAgentToolCall(
      id: 'read9600',
      name: 'read_conversation_records',
      arguments: {'record_id': 'r_0123456789abcdef01234567', 'offset': 9600},
    );
    final first = GenAiSavedTurn(
      prompt: encodeGenAiRemoteRecord({
        'step_id': nonce,
        'agent_format': 5,
        'turn': turn.toRemoteInput(),
        'input': turn.prompt,
      }),
      answer: encodeGenAiAgentCall(rejected, nonce: stale),
    );
    final initial = decodeGenAiConversation('group', [first]).archive;
    expect(initial.turns.single.agentEvents, isEmpty);
    expect(initial.turns.single.failure?.kind, GenAiFailureKind.protocol);
    expect(initial.turns.single.answer, contains('read9600'));
    final corrected = GenAiSavedTurn(
      prompt: encodeGenAiRemoteRecord({
        'step_id': '${nonce}2',
        'agent_format': 5,
        'turn_id': turn.id,
        'input': encodeGenAiAgentResult({
          'call_id': null,
          'name': null,
          'ok': false,
          'error': {'code': 'wrong_nonce', 'message': 'wrong_nonce'},
        }, nonce: '${nonce}2'),
      }),
      answer: 'Archive inspected.',
    );
    final recovered = decodeGenAiConversation('group', [first, corrected]).archive.turns.single;
    expect(recovered.answer, 'Archive inspected.');
    expect(recovered.phase, GenAiChatPhase.completed);
    expect(recovered.agentEvents, isEmpty);
    expect(
      recovered.agentActivity.where((e) => e.kind == GenAiAgentEventKind.protocolError),
      hasLength(1),
    );
  });

  test('versioned plain answer recovers after a tool receipt without local state', () {
    final turn = GenAiConversationTurn('Read then explain', id: 'plain', isAgent: true);
    final call = GenAiAgentToolCall(id: 'read', name: 'get_current_time', arguments: {});
    final rows = [
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'step_id': nonce,
          'agent_format': 5,
          'turn': turn.toRemoteInput(),
          'input': turn.prompt,
        }),
        answer: encodeGenAiAgentCall(call, nonce: nonce),
      ),
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'step_id': '${nonce}2',
          'agent_format': 5,
          'turn_id': turn.id,
          'input': encodeGenAiAgentResult({
            'call_id': call.id,
            'name': call.name,
            'ok': true,
            'result': {'utc': '2026-11-02T12:00:00Z'},
          }, nonce: nonce),
        }),
        answer: 'It is 20:00 in Shanghai.\n```techpie-visual\n<p>20:00</p>\n```',
      ),
    ];
    final restored = decodeGenAiConversation('group', rows).archive.turns.single;
    expect(restored.phase, GenAiChatPhase.completed);
    expect(restored.answer, rows.last.answer);
    expect(restored.agentEvents['read']!.result!['ok'], true);
    expect(
      restored.agentActivity.where((e) => e.kind == GenAiAgentEventKind.protocolError),
      isEmpty,
    );
  });

  test('server-only recovery keeps native-format retry and end-delimited final', () {
    final turn = GenAiConversationTurn('Get the time', id: 'turn', isAgent: true);
    final recovered = decodeGenAiConversation('group', [
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'step_id': nonce,
          'turn': turn.toRemoteInput(),
          'input': turn.prompt,
        }),
        answer: '<|open|>call tool="get_current_time"<|close|>',
      ),
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'step_id': '${nonce}2',
          'turn_id': turn.id,
          'input': encodeGenAiAgentResult({
            'call_id': null,
            'name': null,
            'ok': false,
            'error': {'code': 'native_tool_format', 'message': 'native_tool_format'},
          }, nonce: nonce),
        }),
        answer: '<techpie-final nonce="${nonce}2">Unable to retrieve the time.',
      ),
    ]).archive.turns.single;
    expect(recovered.phase, GenAiChatPhase.completed);
    expect(recovered.answer, 'Unable to retrieve the time.');
    expect(recovered.agentEvents, isEmpty);
    expect(
      recovered.agentActivity.where((e) => e.kind == GenAiAgentEventKind.protocolError),
      hasLength(1),
    );
  });

  test('retrieved excerpts recover from school records without duplicated source text', () {
    const text = 'Budget: 42 数学😀; never substitute an assistant guess.';
    const original = GenAiMessage(role: GenAiRole.user, content: text);
    final first = GenAiConversationTurn(text, id: 'original');
    final next = GenAiConversationTurn(
      'Recall budget',
      id: 'lookup',
      parentId: first.id,
      isAgent: true,
    );
    for (final name in ['search_conversation', 'read_conversation_records']) {
      final page = <String, Object?>{
        'record_id': genAiContextSourceId(original),
        'offset': 0,
        'text': text,
        'partial': false,
      };
      final receipt = <String, Object?>{
        'call_id': 'lookup-call',
        'name': name,
        'ok': true,
        'result': name == 'search_conversation'
            ? {
                'matches': [
                  page,
                  {
                    ...page,
                    'offset': text.runes.toList().indexOf('数'.runes.single),
                    'text': '数学😀',
                    'partial': true,
                  },
                ],
                'total': 2,
              }
            : page,
      };
      final compact = genAiCompactRetrievedReceipt(receipt, [original]);
      expect(jsonEncode(compact), isNot(contains(text)));
      final rows = [
        GenAiSavedTurn(
          prompt: encodeGenAiRemoteRecord({
            'step_id': 'original-step',
            'turn': first.toRemoteInput(),
            'input': text,
          }),
          answer: 'Recorded.',
        ),
        GenAiSavedTurn(
          prompt: encodeGenAiRemoteRecord({
            'step_id': 'lookup-step',
            'turn': next.toRemoteInput(),
            'input': next.prompt,
          }),
          answer: encodeGenAiAgentCall(
            GenAiAgentToolCall(id: 'lookup-call', name: name, arguments: {}),
            nonce: nonce,
          ),
        ),
        GenAiSavedTurn(
          prompt: encodeGenAiRemoteRecord({
            'step_id': 'result-step',
            'turn_id': next.id,
            'input': encodeGenAiAgentResult(compact, nonce: nonce),
          }),
          answer: encodeGenAiAgentFinal('42', nonce: nonce),
        ),
      ];
      final recovered = decodeGenAiConversation('group', rows).archive.turns.last;
      expect(recovered.phase, GenAiChatPhase.completed);
      expect(recovered.agentEvents['lookup-call']!.result, receipt);
      expect(() => genAiRestoreRetrievedReceipt(compact, []), throwsFormatException);
    }
  });

  test('server recovery retains unverified output inertly and a valid repair replaces it', () {
    final turn = GenAiConversationTurn('Explain', id: 'unverified', isAgent: true);
    const candidate = 'Useful observation.\n```techpie-visual\n<script>run()</script>\n```';
    GenAiSavedTurn row(String step, String answer, {bool first = false}) => GenAiSavedTurn(
      prompt: encodeGenAiRemoteRecord({
        'step_id': step,
        'turn_id': turn.id,
        if (first) 'turn': turn.toRemoteInput(),
        'input': first ? turn.prompt : 'Repair format',
      }),
      answer: answer,
    );
    final initial = row('first', candidate, first: true);
    final recovered = decodeGenAiConversation('group', [initial]).archive.turns.single;
    expect(recovered.phase, GenAiChatPhase.interrupted);
    expect(recovered.failure?.kind, GenAiFailureKind.protocol);
    expect(recovered.answer, genAiUnverifiedAgentSource(candidate));
    final repaired = decodeGenAiConversation('group', [
      initial,
      row('second', encodeGenAiAgentFinal('Verified answer', nonce: nonce)),
    ]).archive.turns.single;
    expect(repaired.phase, GenAiChatPhase.completed);
    expect(repaired.failure, isNull);
    expect(repaired.answer, 'Verified answer');
  });

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
    final recovered = decodeGenAiConversation('group', rows).archive.turns;
    expect(recovered.map((turn) => turn.id), ['stopped', 'next']);
    expect(recovered.first.phase, GenAiChatPhase.cancelled);
    expect(recovered.first.answer, 'Partial answer');
    expect(recovered.first.contextUsage?.toRecord(), stopped.contextUsage!.toRecord());
    expect(recovered.last.answer, 'New answer');
  });

  test('server-only recovery joins identified tools, preserves files and selects retry ancestry', () {
    final source = GenAiConversationTurn('Read my document', id: 'a', isAgent: true)
      ..files = [
        const GenAiTurnFile(
          id: 'file-a',
          name: 'notes.txt',
          content: 'Original numeric record: 5837',
        ),
      ];
    final call = GenAiAgentToolCall(id: 'c1', name: 'get_semesters', arguments: const {});
    GenAiSavedTurn row(
      String step,
      GenAiConversationTurn turn,
      String input,
      String answer,
    ) => GenAiSavedTurn(
      prompt:
          '【上传文件：notes.txt】\n${encodeGenAiRemoteRecord({
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
            'contextUsage': step == 's4' ? {'input': -1} : {'input': step == 's2' ? 2600 : 1500, 'limit': 10000, 'original': 9000, 'compacted': true},
          })}',
      answer: answer,
    );
    final rows = [
      row('s1', source, source.prompt, encodeGenAiAgentCall(call, nonce: nonce)),
      row(
        's2',
        source,
        encodeGenAiAgentResult({
          'call_id': 'c1',
          'name': 'get_semesters',
          'ok': true,
          'result': {'semester': 3},
        }, nonce: nonce),
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
    final recovered = decodeGenAiConversation('group', rows).archive.turns;
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

  test('mixed record versions recover normalized mutation identities without duplicate receipts', () {
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
    final old =
        '<techpie-record version="1">\n${jsonEncode({'kind': 'exchange', 'step_id': 'old-step', 'turn': original.toRemoteInput(), 'input': original.prompt, 'agent': true, 'aiType': 'Kimi-k3', 'rootAiType': 'xinference'})}\n</techpie-record>';
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
      'thinking': true,
      'search': false,
      'rootAiType': 'xinference',
    });
    final rows = [
      GenAiSavedTurn(
        prompt: old,
        answer: encodeGenAiAgentCall(call, nonce: nonce),
      ),
      GenAiSavedTurn(
        prompt: compact,
        answer: encodeGenAiAgentFinal('Booked.', nonce: nonce),
        aiType: 'Kimi-k3',
      ),
    ];
    final archive = decodeGenAiConversation('group', rows).archive;
    final turn = archive.turns.single;
    expect(turn.phase, GenAiChatPhase.completed);
    expect(turn.agentEvents[call.id]!.result, receipt);
    expect(turn.approvalBudget['reserve_court'], 1);
    expect((archive.mutations['effects']! as Map)[effectKey], receipt);
    expect(archive.agentEnabled, true);
    expect(archive.modelAiType, 'Kimi-k3');
    expect(archive.modelRootAiType, isNull);
    final record = decodeGenAiRemoteRecord(compact)!;
    expect(record.keys, isNot(contains('mutations')));
    expect(record.keys, isNot(contains('agent')));
    expect(record.keys, isNot(contains('thinking')));
    expect(record.keys, isNot(contains('rootAiType')));
    expect('booking-314'.allMatches(compact), hasLength(1));
  });

  test('server checkpoints normalize earlier parallel attachment fields', () {
    final stopped = GenAiConversationTurn('Read attached notes', id: 'stopped')
      ..answer = 'Partial answer';
    final checkpoint = stopped.toInterruptedRecord()
      ..remove('files')
      ..addAll({
        'attachedFileIds': ['notes-id'],
        'attachedFileNames': ['notes.txt'],
        'attachedFileContents': {'notes-id': 'Seats: 144'},
      });
    final next = GenAiConversationTurn('Continue', id: 'next', parentId: 'stopped');
    final recovered = decodeGenAiConversation('group', [
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'kind': 'exchange',
          'step_id': 'next-step',
          'turn': next.toRemoteInput(),
          'turn_id': next.id,
          'input': next.prompt,
          'interrupted': [checkpoint],
        }),
        answer: '144 seats',
      ),
    ]).archive.turns;
    expect(recovered.first.files.single.id, 'notes-id');
    expect(recovered.first.files.single.content, 'Seats: 144');
    expect(recovered.first.files.single.name, 'notes.txt');
    expect(recovered.first.phase, GenAiChatPhase.cancelled);
  });

  test('upload fallback parents migrate without reviving stale interrupted snapshots', () {
    final first = GenAiConversationTurn('Start', id: 'first');
    final document = GenAiConversationTurn('Read file', id: 'doc', parentId: 'first', isAgent: true)
      ..files = [const GenAiTurnFile(id: 'file', name: 'notes.txt', content: 'Seats: 144')];
    final followup = GenAiConversationTurn('Recall seats', id: 'next', parentId: 'legacy-2');
    final call = GenAiAgentToolCall(id: 'time', name: 'get_current_time', arguments: const {});
    GenAiSavedTurn row(
      String step,
      GenAiConversationTurn? turn,
      String input,
      String answer, {
      bool upload = false,
      List<Object?> interrupted = const [],
    }) => GenAiSavedTurn(
      prompt:
          '${upload ? '【上传文件：notes.txt】\n' : ''}${encodeGenAiRemoteRecord({'kind': 'exchange', 'step_id': step, 'turn': turn?.toRemoteInput(), 'turn_id': turn?.id ?? 'doc', 'input': input, 'interrupted': interrupted})}',
      answer: answer,
    );
    final rows = [
      row('1', first, first.prompt, 'Ready'),
      row('2', document, document.prompt, encodeGenAiAgentCall(call, nonce: nonce), upload: true),
      row(
        '3',
        null,
        encodeGenAiAgentResult({
          'call_id': 'time',
          'name': 'get_current_time',
          'ok': true,
          'result': {'time': '12:00'},
        }, nonce: nonce),
        encodeGenAiAgentFinal('144 seats', nonce: nonce),
        upload: true,
      ),
      row(
        '4',
        followup,
        followup.prompt,
        '144',
        interrupted: [
          GenAiConversationTurn(
            'obsolete raw wrapper',
            id: 'legacy-1',
            parentId: 'first',
          ).toArchiveJson(),
        ],
      ),
    ];
    final turns = decodeGenAiConversation('group', rows).archive.turns;
    expect(turns.map((t) => t.id), ['first', 'doc', 'next']);
    expect(turns[1].agentEvents['time']!.result!['ok'], true);
    expect(turns[1].attachedFileContents['file'], 'Seats: 144');
    expect(turns.any((t) => t.isHistoryGap), false);
    // An unrelated missing parent must still break continuity.
    followup.parentId = 'legacy-99';
    final broken = decodeGenAiConversation('group', [
      ...rows.take(3),
      row('5', followup, followup.prompt, '144'),
    ]).archive.turns;
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
    final recovered = decodeGenAiConversation('group', [
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'kind': 'exchange',
          'step_id': 'image-step',
          'turn': turn.toRemoteInput(),
          'input': turn.prompt,
        }),
        answer: encodeGenAiAgentCall(call, nonce: nonce),
      ),
    ]).archive;
    expect(recovered.turns.single.actionScopeId, 'original-task');
    expect(recovered.turns.single.toArchiveJson()['actionScopeId'], 'original-task');
    expect(
      (recovered.mutations['effects']! as Map).keys,
      contains(genAiMutationReceiptKey(call, turnId: 'original-task')),
    );
  });

  test('generated image receipt retains title and quality through archive roundtrip', () {
    final source = GenAiConversationTurn('Draw a red square', id: 'image', isAgent: true);
    final call = GenAiAgentToolCall(
      id: 'img',
      name: 'generate_image',
      arguments: const {
        'prompt': 'A red square',
        'title': 'Red square',
        'width': 1024,
        'height': 1024,
        'quality': 'high',
      },
    );
    final receipt = <String, Object?>{
      'call_id': 'img',
      'name': 'generate_image',
      'ok': true,
      'result': {
        'status': 'generated',
        'model': 'Image',
        'title': 'Red square',
        'quality': 'high',
        'size': '1024x1024',
        'images': ['https://genaipic.shanghaitech.edu.cn/sys/common/static/temp/red.png'],
      },
    };
    final rows = [
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'kind': 'exchange',
          'step_id': 'image-call',
          'turn': source.toRemoteInput(),
          'turn_id': source.id,
          'input': source.prompt,
        }),
        answer: encodeGenAiAgentCall(call, nonce: nonce),
      ),
      GenAiSavedTurn(
        prompt: encodeGenAiRemoteRecord({
          'kind': 'exchange',
          'step_id': 'image-result',
          'turn': null,
          'turn_id': source.id,
          'input': encodeGenAiAgentResult(receipt, nonce: nonce),
        }),
        answer: encodeGenAiAgentFinal('Done.', nonce: nonce),
      ),
    ];
    Map<String, Object?> imageResult(GenAiConversationTurn turn) =>
        Map<String, Object?>.from(turn.agentEvents['img']!.result!['result']! as Map);

    final archive = decodeGenAiConversation('group', rows).archive;
    final recovered = imageResult(archive.turns.single);
    expect(recovered['title'], 'Red square');
    expect(recovered['quality'], 'high');
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
    final turn = decodeGenAiConversation('group', rows).archive.turns.single;
    expect(turn.phase, GenAiChatPhase.interrupted);
    expect(turn.approvalBudget['reserve_court'], 1);
    expect((turn.agentEvents['book']!.result!['error']! as Map)['code'], 'outcome_unknown');
    expect(turn.agentEvents['book']!.prepared, isNull);
  });
}
