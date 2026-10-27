import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_archive.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/application/genai_transcript_export.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';

void main() {
  GenAiConversationArchive archive(GenAiConversationTurn turn) => GenAiConversationArchive(
        id: 'fixture-conversation',
        title: '校园计划',
        updatedAt: DateTime(2026),
        turns: [turn],
        agentEnabled: true,
        netSearchEnabled: false,
        thinkingEnabled: false,
        modelAiType: 'demo',
        modelRootAiType: 'demo',
        mutations: const {'version': 1, 'effects': <String, Object?>{}},
      );

  test('readable snapshot retains real conversation and images, omits protocol', () {
    final call = GenAiAgentToolCall(
      id: 'internal-call-id',
      name: 'generate_image',
      arguments: const {},
    );
    final turn = GenAiConversationTurn('为校园计划生成图片', isAgent: true)
      ..phase = GenAiChatPhase.completed
      ..answer = '校园图片已经生成。'
      ..attachedFileNames = ['计划.txt']
      ..agentHistory = const [
        GenAiMessage(role: GenAiRole.assistant, content: 'old-wire-format'),
      ]
      ..agentTranscript = [GenAiAgentHistoryEntry.call(call)]
      ..agentEvents[call.id] = GenAiAgentEvent(
        kind: GenAiAgentEventKind.toolFinished,
        turn: 1,
        call: call,
        result: {
          'call_id': call.id,
          'name': call.name,
          'ok': true,
          'reused': true,
          'result': {
            'status': 'generated',
            'images': [
              'https://genaipic.shanghaitech.edu.cn/sys/common/static/campus.png',
            ],
          },
        },
      );
    final saved = archive(turn);
    turn.answer = 'Changed after snapshot';
    final output = exportGenAiTranscript(saved);
    expect(output, contains('# 校园计划'));
    expect(output, contains('为校园计划生成图片'));
    expect(output, contains('校园图片已经生成。'));
    expect(output, contains('图片创作 · 已完成'));
    expect(output, contains('复用已保存的结果'));
    expect(
      output,
      contains(
        '![生成图片](<https://genaipic.shanghaitech.edu.cn/sys/common/static/campus.png>)',
      ),
    );
    for (final hidden in [
      'old-wire-format',
      'internal-call-id',
      'techpie-agent',
      'Changed after snapshot',
    ]) {
      expect(output, isNot(contains(hidden)));
    }
  });

  test('interrupted mutation exports uncertainty, not success or a hostile image', () {
    final call = GenAiAgentToolCall(
      id: 'pending',
      name: 'generate_image',
      arguments: const {},
    );
    final turn = GenAiConversationTurn('画一张图', isAgent: true)
      ..phase = GenAiChatPhase.streaming
      ..attachedImageUrls = [
        'javascript:alert(1)',
        'https://evil.example/image.png',
      ]
      ..agentEvents[call.id] = GenAiAgentEvent(
        kind: GenAiAgentEventKind.toolStarted,
        turn: 1,
        call: call,
      );
    final output = exportGenAiTranscript(archive(turn));
    expect(output, contains('结果待核实'));
    expect(output, contains('此轮已停止'));
    expect(output, isNot(contains('已完成')));
    expect(output, isNot(contains('evil.example')));
    expect(output, isNot(contains('javascript:')));
  });

  GenAiConversationTurn withResults(Map<String, Map<String, Object?>> results) {
    final turn = GenAiConversationTurn('校园记录', isAgent: true)..phase = GenAiChatPhase.completed;
    for (final entry in results.entries) {
      final call = GenAiAgentToolCall(
        id: 'internal-${entry.key}',
        name: entry.key,
        arguments: const {},
      );
      turn.agentEvents[call.id] = GenAiAgentEvent(
        kind: GenAiAgentEventKind.toolFinished,
        turn: 1,
        call: call,
        result: {'ok': true, 'result': entry.value},
      );
    }
    return turn;
  }

  test('academic results export useful labels without bookkeeping identifiers', () {
    final output = exportGenAiTranscript(
      archive(
        withResults({
          'get_current_time': {
            'campus_time': '2026-10-23T15:00:00+08:00',
            'utc': '2026-10-23T07:00:00Z',
            'device_time': '2026-10-23T15:00:00',
            'source': 'device_clock',
          },
          'get_semesters': {
            'source': 'techpie_cache',
            'ownership_verified': true,
            'selected_semester_id': 'internal-semester',
            'default_semester_id': 'internal-semester',
            'semesters': [
              {'id': 'internal-semester', 'label': '2026–2027 第一学期'},
            ],
          },
          'get_week_schedule': {
            'semester_id': 'internal-semester',
            'semester_label': '2026–2027 第一学期',
            'week': 4,
            'truncated': true,
            'next_offset': 12,
            'courses': [
              {
                'name': '线性代数',
                'weekday': 1,
                'start_time': '08:15',
                'end_time': '09:55',
                'location': '教学楼 101',
              },
            ],
          },
          'get_assignments': {
            'partial': true,
            'assignments': [
              {
                'id': 'internal-assignment',
                'title': '矩阵练习',
                'course': '线性代数',
                'kind': 'assignment',
                'due': '2026-10-23T07:00:00Z',
                'completed': false,
              },
            ],
          },
        }),
      ),
    );
    for (final expected in [
      '校区时间：2026-10-23 15:00（上海时间）',
      '2026–2027 第一学期（当前选择、默认学期）',
      '教学周：第 4 周',
      '线性代数 · 周一 · 08:15–09:55 · 教学楼 101',
      '矩阵练习 · 线性代数 · 作业 · 截止 2026-10-23 15:00（上海时间） · 未完成',
      '部分数据未能加载',
      '还有更多记录',
    ]) {
      expect(output, contains(expected));
    }
    for (final omitted in [
      'internal-',
      'source',
      'ownership_verified',
      'next_offset',
      'techpie_cache',
      'device_clock',
    ]) {
      expect(output, isNot(contains(omitted)));
    }
  });

  test('court receipts distinguish rejected booking from successful query', () {
    final rejected = exportGenAiTranscript(
      archive(
        withResults({
          'reserve_court': {
            'status': 'rejected',
            'success': false,
            'sport': 'badminton',
            'date': '2026-10-24',
            'court_number': 3,
            'time_slot': 2,
            'players_count': 4,
            'message': '学校服务未确认预约成功，请查看场馆预约页。',
          },
        }),
      ),
    );
    expect(rejected, contains('场地预约 · 未预约成功'));
    expect(rejected, contains('运动：羽毛球'));
    expect(rejected, contains('时段：12:00-13:00'));
    expect(rejected, contains('场地：3 号场地'));
    expect(rejected, contains('人数：4 人'));
    expect(rejected, isNot(contains('已完成')));
    final availability = exportGenAiTranscript(
      archive(
        withResults({
          'reserve_court': {
            'status': 'availability',
            'sport': 'tennis',
            'availability': [
              {
                'date': '2026-10-24',
                'time_slot': 2,
                'time_range': '12:00-13:00',
                'available_courts': [
                  {'number': 1, 'label': '网球场 1'},
                ],
              }
            ],
            'price': '平台未提供价格',
          },
        }),
      ),
    );
    expect(availability, contains('2026-10-24 · 12:00-13:00 · 网球场 1'));
    expect(availability, contains('费用：平台未提供价格'));
    expect(availability, isNot(contains('time_slot')));
  });

  test('local images are labeled and proxied real images export canonical links', () {
    final local = exportGenAiTranscript(
      archive(
        withResults({
          'generate_image': {
            'status': 'generated',
            'demo': true,
            'quality': 'low',
            'size': '1024x1024',
            'images': [
              'https://genaipic.shanghaitech.edu.cn/sys/common/static/techpie-preview/image-1.png',
            ],
          },
        }),
      ),
    );
    expect(local, contains('本地测试图片'));
    expect(local, contains('质量：普通'));
    expect(local, isNot(contains('![')));
    expect(local, isNot(contains('https://')));
    final real = exportGenAiTranscript(
      archive(
        withResults({
          'generate_image': {
            'status': 'generated',
            'images': [
              'http://127.0.0.1:18768/sys/common/static/real-image.png',
            ],
          },
        }),
      ),
    );
    expect(
      real,
      contains(
        'https://genaipic.shanghaitech.edu.cn/sys/common/static/real-image.png',
      ),
    );
    expect(real, isNot(contains('127.0.0.1')));
  });

  test('declined actions stay declined and never export success payloads', () {
    final call = GenAiAgentToolCall(
      id: 'declined',
      name: 'generate_image',
      arguments: const {},
    );
    final turn = GenAiConversationTurn('画图', isAgent: true)
      ..phase = GenAiChatPhase.completed
      ..agentEvents[call.id] = GenAiAgentEvent(
        kind: GenAiAgentEventKind.toolFinished,
        turn: 1,
        call: call,
        result: const {
          'ok': false,
          'error': {'code': 'approval_denied', 'message': '用户拒绝执行。'},
        },
      );
    final output = exportGenAiTranscript(archive(turn));
    expect(output, contains('图片创作 · 已拒绝'));
    expect(output, contains('用户拒绝执行。'));
    expect(output, isNot(contains('已完成')));
  });
}
