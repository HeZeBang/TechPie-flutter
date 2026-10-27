import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_legacy_conversation_import.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';

GenAiAgentToolCall _call(String id, [String name = 'get_current_time']) =>
    GenAiAgentToolCall(id: id, name: name, arguments: const {});

Map<String, Object?> _result(String? id, String? name) => {
      'call_id': id,
      'name': name,
      'ok': true,
      'result': {'value': 'saved'},
    };

String _legacyCall(GenAiAgentToolCall call) => '```tool_call\n${jsonEncode(call.toJson())}\n```';
String _legacyResult(Map<String, Object?> result) => '```tool_response\n${jsonEncode(result)}\n```';

void main() {
  test('server-only recovery folds action-promise repair into the original tool turn', () {
    const nonce = 'historicalNonce123456';
    final turns = importGenAiLegacyConversation([
      const GenAiSavedTurn(
        prompt: 'which semester are we in?',
        answer: "I'll check the current semester information for you.",
      ),
      GenAiSavedTurn(
        prompt: encodeGenAiAgentResult(
          {
            'call_id': null,
            'name': null,
            'ok': false,
            'error': {'code': 'unfinished_action', 'message': 'No tool executed.'},
          },
          nonce: nonce,
        ),
        answer: encodeGenAiAgentCall(_call('semester', 'get_semesters'), nonce: nonce),
      ),
      GenAiSavedTurn(
        prompt: encodeGenAiAgentResult(_result('semester', 'get_semesters'), nonce: nonce),
        answer: 'The returned semester is autumn.',
      ),
    ]);
    expect(turns, hasLength(1));
    expect(turns.single.prompt, 'which semester are we in?');
    expect(turns.single.answer, 'The returned semester is autumn.');
    expect(turns.single.phase, GenAiChatPhase.completed);
    expect(turns.single.agentEvents.values.single.call!.name, 'get_semesters');
  });

  test('unreadable server row breaks an otherwise matching tool chain', () {
    const nonce = 'historicalNonce123456';
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(
        prompt: '查询时间',
        answer: encodeGenAiAgentCall(_call('time'), nonce: nonce),
      ),
      const GenAiSavedTurn(prompt: '', answer: '', isHistoryGap: true),
      GenAiSavedTurn(
        prompt: encodeGenAiAgentResult(
          _result('time', 'get_current_time'),
          nonce: nonce,
        ),
        answer: '历史回答',
      ),
    ]);
    expect(turns, hasLength(3));
    expect(turns.first.phase, GenAiChatPhase.interrupted);
    expect(turns.first.agentEvents.values.single.result!['ok'], isFalse);
    expect(turns[1].isHistoryGap, isTrue);
    expect(turns[1].prompt, isEmpty);
    expect(turns[1].answer, isEmpty);
    expect(turns[1].agentStatus, contains('上下文可能缺失'));
    expect(turns.last.phase, GenAiChatPhase.interrupted);
    expect(turns.last.agentTranscript, isEmpty);
  });

  test('adjacent matching legacy steps become one display-only task', () {
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(
        prompt: '整理本周课表',
        answer: _legacyCall(_call('time')),
        reasoning: 'saved thought',
      ),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('time', 'get_current_time')),
        answer: _legacyCall(_call('schedule', 'get_week_schedule')),
      ),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('schedule', 'get_week_schedule')),
        answer: '本周课表如下。',
      ),
      const GenAiSavedTurn(prompt: '谢谢', answer: '不客气'),
    ]);
    expect(turns, hasLength(2));
    final task = turns.first;
    expect(task.prompt, '整理本周课表');
    expect(task.answer, '本周课表如下。');
    expect(task.reasoning, 'saved thought');
    expect(task.isAgent, isTrue);
    expect(task.phase, GenAiChatPhase.completed);
    expect(task.agentEvents.keys, ['time', 'schedule']);
    expect(
      task.agentEvents.values.every((event) => event.prepared == null),
      isTrue,
    );
    expect(task.agentHistory, isEmpty);
    expect(task.agentTranscript, isEmpty);
    expect(turns.last.isAgent, isFalse);
  });

  test('ordinary code examples and mismatched calls remain ordinary text', () {
    final example = _legacyCall(_call('example'));
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(prompt: '请给一个 tool_call 示例', answer: example),
      const GenAiSavedTurn(prompt: '实际使用应如何设计？', answer: '解释说明'),
    ]);
    expect(turns.first.isAgent, isFalse);
    expect(turns.first.answer, example);
    final mismatched = importGenAiLegacyConversation([
      GenAiSavedTurn(prompt: '示例', answer: example),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('other', 'get_current_time')),
        answer: '保存的说明',
      ),
    ]);
    expect(mismatched.first.isAgent, isFalse);
    expect(mismatched.last.prompt, '恢复的工具记录');
    expect(mismatched.last.answer, '保存的说明');
    expect(mismatched.last.phase, GenAiChatPhase.interrupted);
  });

  test('trailing tool call stays unknown and has no restored approval', () {
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(prompt: '生图', answer: _legacyCall(_call('time'))),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('time', 'get_current_time')),
        answer: _legacyCall(_call('image', 'generate_image')),
      ),
    ]);
    final turn = turns.single;
    expect(turn.answer, isEmpty);
    expect(turn.phase, GenAiChatPhase.interrupted);
    expect(turn.agentEvents['image']!.result!['error'], {
      'code': 'outcome_unknown',
      'message': '保存的记录缺少工具结果，无法确认是否执行。请先查看相关记录。',
    });
    expect(turn.agentEvents['image']!.prepared, isNull);
    expect(turn.agentStatus, contains('勿重复执行'));
  });

  test('V2 frames import as inert cards with no nonce or framing in bubbles', () {
    const nonce = 'historicalNonce123456';
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(
        prompt: '现在几点',
        answer: encodeGenAiAgentCall(_call('time'), nonce: nonce),
      ),
      GenAiSavedTurn(
        prompt: encodeGenAiAgentResult(
          _result('time', 'get_current_time'),
          nonce: nonce,
        ),
        answer: '现在是下午三点。',
      ),
    ]);
    expect(turns.single.isAgent, isTrue);
    expect(turns.single.answer, '现在是下午三点。');
    expect(turns.single.agentEvents, hasLength(1));
    expect(turns.single.agentHistory, isEmpty);
    expect(turns.single.agentTranscript, isEmpty);
    final unfinished = importGenAiLegacyConversation([
      GenAiSavedTurn(
        prompt: '生图',
        answer: encodeGenAiAgentCall(
          _call('image', 'generate_image'),
          nonce: nonce,
        ),
      ),
    ]).single;
    expect(unfinished.answer, isEmpty);
    expect(unfinished.phase, GenAiChatPhase.interrupted);
  });

  test('orphan protocol error does not crash or expose raw result JSON', () {
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(
        prompt: _legacyResult({
          'call_id': null,
          'name': null,
          'ok': false,
          'error': {'code': 'invalid_tool_call', 'message': 'Correct the call'},
        }),
        answer: '已修正问题。',
      ),
    ]);
    expect(turns.single.prompt, '恢复的工具记录');
    expect(turns.single.answer, '已修正问题。');
    expect(turns.single.agentEvents, isEmpty);
    expect(turns.single.phase, GenAiChatPhase.interrupted);
  });

  test('repeated call ids retain receipts and normal saved attachments', () {
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(prompt: '查询两次', answer: _legacyCall(_call('same'))),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('same', 'get_current_time')),
        answer: _legacyCall(_call('same')),
      ),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('same', 'get_current_time')),
        answer: '查询完成',
      ),
      const GenAiSavedTurn(
        prompt: '分析图片',
        answer: '红色方块',
        imageUrls: [
          'https://genaipic.shanghaitech.edu.cn/sys/common/static/a.png',
        ],
      ),
    ]);
    expect(turns.first.agentEvents, hasLength(2));
    expect(turns.last.attachedImageUrl, endsWith('/a.png'));
    expect(turns.last.attachedImageUrls, hasLength(1));
  });

  test('malformed protocol inside established chain is never a final bubble', () {
    final turns = importGenAiLegacyConversation([
      GenAiSavedTurn(prompt: '查询时间', answer: _legacyCall(_call('time'))),
      GenAiSavedTurn(
        prompt: _legacyResult(_result('time', 'get_current_time')),
        answer: '```tool_call\n{"broken":true}\n```',
      ),
    ]);
    expect(turns.single.answer, isEmpty);
    expect(turns.single.phase, GenAiChatPhase.interrupted);
    expect(turns.single.agentEvents, hasLength(1));
  });
}
