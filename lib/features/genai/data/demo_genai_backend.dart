import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/genai_chat_service.dart';
import '../application/genai_repository.dart';
import '../application/genai_session_service.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';
import '../platform/genai_transport.dart';
import 'genai_api_client.dart';
import 'genai_request_signer.dart';

/// Debug-only in-memory backend. It has no HTTP client or persisted credentials.
final class DemoGenAiBackend implements GenAiTransport {
  DemoGenAiBackend({this.chunkDelay = const Duration(milliseconds: 32)}) {
    if (!kDebugMode) throw UnsupportedError('GenAI demo is debug-only');
  }

  final Duration chunkDelay;
  bool failUpload = false;
  static const token = 'synthetic-preview-token';
  static const studentId = '20240001';
  final _operations = <GenAiCancellation>{};
  int _uploadSequence = 0;
  final _history = <String, List<Map<String, Object?>>>{};
  final _images = <Map<String, Object?>>[];

  GenAiResponse _ok(Object? result) =>
      _json({'success': true, 'code': 200, 'result': result});

  Map<String, Object?> _page(List<Object?> rows, Uri uri) {
    final page = int.tryParse(uri.queryParameters['pageNo'] ?? '') ?? 1;
    final size = int.tryParse(uri.queryParameters['pageSize'] ?? '') ?? 20;
    return {
      'records': rows.skip((page - 1) * size).take(size).toList(),
      'total': rows.length,
    };
  }

  @override
  Future<GenAiResponse> send({
    required String method,
    required Uri uri,
    required GenAiCancellation cancellation,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
  }) async {
    cancellation.throwIfCancelled();
    if (headers['X-Access-Token'] != token &&
        headers['token'] != '2ea38f293adb4abca21132feba61eaa3') {
      return _json({'success': false, 'code': 401});
    }
    if (uri.path.startsWith('/htk/user/info/')) {
      return _json({
        'success': true,
        'code': 200,
        'result': {
          'userInfo': {'id': 'preview-user', 'username': studentId},
        },
      });
    }
    if (uri.path == '/htk/ai/aiModel/list') {
      return _json({
        'success': true,
        'code': 200,
        'result': {
          'records': [
            {
              'aiName': '校园通用 · 演示',
              'aiType': 'demo-general',
              'rootAiType': 'demo',
              'payType': 'FREE',
              'status': 3,
            },
            {
              'aiName': '代码助手 · 演示',
              'aiType': 'demo-code',
              'rootAiType': 'demo',
              'payType': 'FREE',
              'status': 3,
            },
            {
              'aiName': '图片创作 · 演示',
              'aiType': 'demo-image',
              'rootAiType': 'demo',
              'payType': 'PAID',
              'status': 2,
            },
          ],
        },
      });
    }
    if (uri.path == '/htk/chat/net/search') {
      return _ok({
        'count': 2,
        'links': [
          {
            'num': 1,
            'title': '上海科技大学 - 官方门户',
            'link': 'https://www.shanghaitech.edu.cn',
            'snippet': '上海科技大学是一所由上海市人民政府与中国科学院共同举办、共同建设的全日制研究型大学。',
          },
          {
            'num': 2,
            'title': '上海科技大学信息科学与技术学院',
            'link': 'https://sist.shanghaitech.edu.cn',
            'snippet': '上海科技大学信息学院致力于培养高水平计算机与电子信息拔尖创新人才。',
          },
        ],
      });
    }
    if (uri.path == '/htk/chat/upload/chat/file') {
      return _ok({
        'fileId': 'demo-file-${DateTime.now().millisecondsSinceEpoch}',
        'fileName': 'uploaded_document.txt',
        'content': '已提取文档内容：关于上海科技大学相关学术介绍与校园服务指南。',
        'chatGroupId': uri.queryParameters['chatGroupId'] ?? '',
      });
    }
    if (uri.path == '/sys/common/upload') {
      if (failUpload) {
        return _json({
          'success': false,
          'code': 500,
          'message': 'Upload failed',
        });
      }
      return _ok({
        'url': 'temp/demo-upload-${++_uploadSequence}.png',
        'width': 1024,
        'height': 1024,
      });
    }
    if (uri.path == '/htk/chat/convert2wav') {
      return GenAiResponse(
        statusCode: 200,
        headers: const {'Content-Type': 'audio/wav'},
        bytes: Stream.value(_createSilentWav()),
        close: () {},
      );
    }
    if (uri.path == '/htk/chat/recognize') {
      return _ok({
        'transcription': jsonEncode({
          'transcription': [
            {'text': '你好，这是通过语音识别转换的文字内容。'},
          ],
        }),
      });
    }
    final data = body == null
        ? <String, dynamic>{}
        : (body.startsWith('{')
            ? jsonDecode(body) as Map<String, dynamic>
            : <String, dynamic>{});
    switch (uri.path) {
      case '/htk/ai/history/listByContentGroup':
        final rawQuery = uri.queryParameters['question'] ?? '';
        final query = rawQuery.trim().toLowerCase();
        return _ok(
          _page(
            [
              for (final entry in _history.entries.toList().reversed)
                if (entry.value.isNotEmpty)
                  if (query.isEmpty ||
                      entry.value.any(
                        (turn) => (turn['question'] as String? ?? '')
                            .toLowerCase()
                            .contains(query),
                      ))
                    {
                      'chatGroupId': entry.key,
                      'question': entry.value.first['question'],
                      'createTime': '2026-10-19 12:00:00',
                    },
            ],
            uri,
          ),
        );
      case '/htk/ai/history/getByChatGroupId':
        return _ok(_history[uri.queryParameters['chatGroupId']] ?? <Object>[]);
      case '/htk/ai/history/delete/groupId':
        _history.remove(uri.queryParameters['id'] ?? data['id']);
        return _ok(null);
      case '/htk/ai-image-history/list':
        return _ok(_page(_images.reversed.toList(), uri));
      case '/htk/ai-image-history/delete':
        _images.removeWhere(
          (row) => row['id'] == (uri.queryParameters['id'] ?? data['id']),
        );
        return _ok(null);
      case '/htk/ai-api-gateway/my/summary':
        return _ok({
          'free': {'total': 35, 'used': 0, 'remain': 35},
          'projects': <Object>[],
          'keys': <Object>[],
        });
      case '/htk/ai-trade-order/my/list':
        return _ok(_page([], uri));
    }
    if (uri.path == '/htk/chat/start/chat' && data['aiType'] == 'demo-image') {
      final path = 'techpie-preview/image-${_images.length + 1}.png';
      _images.add({
        'id': 'preview-image-${_images.length + 1}',
        'question': data['chatInfo'],
        'images': [
          {'imageUrl': path},
        ],
      });
      return _json({
        'data': [
          {'url': path},
        ],
      });
    }
    if (method != 'POST' || uri.path != '/htk/chat/start/chat') {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    final json = jsonDecode(body!) as Map<String, dynamic>;
    final operation = GenAiCancellation();
    _operations.add(operation);
    final remove = cancellation.onCancel(operation.cancel);
    return GenAiResponse(
      statusCode: 200,
      headers: const {'Content-Type': 'text/event-stream'},
      bytes: _stream(json, operation),
      close: () {
        remove();
        operation.cancel();
        _operations.remove(operation);
      },
    );
  }

  GenAiResponse _json(Map<String, Object?> data) => GenAiResponse(
        statusCode: 200,
        headers: const {'Content-Type': 'application/json'},
        bytes: Stream.value(utf8.encode(jsonEncode(data))),
        close: () {},
      );

  static List<int> _createSilentWav() {
    final header = Uint8List(44);
    final view = ByteData.view(header.buffer);
    header.setRange(0, 4, ascii.encode('RIFF'));
    view.setUint32(4, 36, Endian.little);
    header.setRange(8, 12, ascii.encode('WAVE'));
    header.setRange(12, 16, ascii.encode('fmt '));
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little); // PCM
    view.setUint16(22, 1, Endian.little); // mono
    view.setUint32(24, 16000, Endian.little); // sample rate
    view.setUint32(28, 32000, Endian.little); // byte rate
    view.setUint16(32, 2, Endian.little); // block align
    view.setUint16(34, 16, Endian.little); // bits per sample
    header.setRange(36, 40, ascii.encode('data'));
    view.setUint32(40, 0, Endian.little);
    return header;
  }

  Stream<List<int>> _stream(
    Map<String, dynamic> request,
    GenAiCancellation cancellation,
  ) async* {
    final prompt = request['chatInfo'] as String;
    final history = request['messages'] as List<dynamic>;
    final turn = history.length ~/ 2 + 1;
    if (request['thinking'] == true) {
      const thoughts = '正在分析您的问题并检索相关信息...\n结合上下文梳理核心要点。';
      for (var index = 0; index < thoughts.length; index += 5) {
        await cancellation.race(Future<void>.delayed(chunkDelay));
        cancellation.throwIfCancelled();
        yield _event({
          'reasoning_content': thoughts.substring(
            index,
            (index + 5).clamp(0, thoughts.length),
          ),
        });
      }
    }
    final String answer;
    final agentAnswer = _agentAnswer(prompt, history);
    if (agentAnswer != null) {
      answer = agentAnswer;
    } else if (prompt.contains('样式') ||
        prompt.contains('排版') ||
        prompt.contains('markdown') ||
        prompt.contains('Markdown') ||
        prompt.contains('引用') ||
        prompt.contains('blockquote') ||
        prompt.contains('示例') ||
        prompt.contains('example') ||
        prompt.contains('测试')) {
      answer = '''
# Markdown 排版与样式综合示例

这是一段正文导语，展示各种基础与进阶排版元素的暗色模式自适应效果。

## 1. 引用块 (Blockquotes) 与边界情况

> 单行常规引用：上海科技大学致力于建设一所小规模、高水平、国际化的研究型大学。

> **多段落与富文本引用**：
>
> 引用内的第二段，包含 **粗体**、*斜体* 以及行内代码 `kGenAiMonospaceFamily`。
>
> 引用内也支持数学公式：质能等价方程为 \$E = mc^2\$。
>
> > 这是二级嵌套引用：验证多层嵌套下的内边距与左侧指示条。
> >
> > > 这是三级极深嵌套引用：验证层级递进下的阅读舒适度与容器边界。

## 2. 列表与任务清单

- 无序层级 1：计算机科学与技术
  - 无序层级 2：人工智能与机器学习
    - 无序层级 3：大语言模型推理优化
- 无序层级 1：信息工程与自动化

1. 第一阶段：问题梳理与约束分析
2. 第二阶段：最小可执行原型验证
   1. 编写单测覆盖边界情况
   2. 检查多平台渲染一致性
3. 第三阶段：全量构建与部署

- [x] 暗黑模式下引用块去高亮刺眼背景（无 `Colors.blue.shade100` 溢出）
- [x] 引用块内文本使用舒适变体灰阶，避免纯白光晕
- [ ] 后续多主题调优

## 3. 表格与对齐 (Tables)

| 模块名称 | 类型 | 默认字体族 | 对齐方式 | 状态 |
| :--- | :---: | :--- | ---: | :---: |
| `GenAiStandardCodeBlock` | 代码块 | `RobotoMono` | 左对齐 | 稳定 |
| `GenAiLatexBlockView` | 公式块 | KaTeX-HTML | 居中 | 稳定 |
| `GenAiChartView` | 图表组件 | 系统动态配色 | 自适应 | 交互可用 |

## 4. 行内与代码块 (Code)

行内代码示例：在入口配置中调用 `runApp(const TechPieApp())`。

```python
def solve_system(equations: list[str]) -> dict[str, float]:
    """求解多元一次方程组并返回解集字典。"""
    # 模拟高斯消元法流程
    print("正在构建增广矩阵...")
    return {"x": 1.0, "y": -2.5, "z": 4.0}

result = solve_system(["2x + y = -0.5", "y + z = 1.5"])
for var, val in result.items():
    print(f"{var} = {val}")
```

## 5. 数学公式 (LaTeX)

行内公式示例：对于任意实数 \$x\$，高斯积分满足 \$\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}\$。

独立展示公式：

\$\$\\oint_C \\mathbf{B} \\cdot d\\boldsymbol{\\ell} = \\mu_0 \\left( I_{\\text{enc}} + \\varepsilon_0 \\frac{d\\Phi_E}{dt} \\right)\$\$

## 6. Mermaid 流程图

```mermaid
graph LR; A[Start] --> B[Done];
```

*这是本地演示排版示例，未调用校园模型。*
''';
    } else if (prompt.contains('代码') || request['aiType'] == 'demo-code') {
      answer =
          '当然。下面是一个把想法拆成小步骤的 Python 示例：\n\n```python\ndef make_plan(goal):\n    return [f"理解 {goal}", "尝试一个小例子", "验证结果"]\n\nfor step in make_plan("今天的学习目标"):\n    print(step)\n```\n\n先运行最小的例子，再逐步完善。你也可以继续告诉我输入、输出和限制，我们一起细化。\n\n*这是本地演示回复，未调用校园模型。*';
    } else {
      answer =
          '当然，我们可以从一个清晰的小目标开始。\n\n### 给你一个可以马上开始的思路\n\n1. **明确目标**：把「${prompt.length > 48 ? '${prompt.substring(0, 48)}…' : prompt}」拆成一个具体问题。\n2. **列出已知条件**：整理材料、时间和你最关心的部分。\n3. **做一次小尝试**：先完成最小的一步，再根据结果调整。\n\n| 阶段 | 建议安排 |\n| --- | --- |\n| 梳理问题 | 10 分钟 |\n| 专注尝试 | 25 分钟 |\n| 回顾与调整 | 5 分钟 |\n\n这是我们当前对话的第 **$turn** 轮。你可以继续补充细节，我会把前面的上下文一起考虑。\n\n*这是本地演示回复，未调用校园模型。*';
    }
    for (var index = 0; index < answer.length; index += 5) {
      await cancellation.race(Future<void>.delayed(chunkDelay));
      cancellation.throwIfCancelled();
      yield _event({
        'content': answer.substring(index, (index + 5).clamp(0, answer.length)),
      });
    }
    final groupId = request['chatGroupId'] as String;
    _history.putIfAbsent(groupId, () => []).add({
      'question': prompt,
      'imageUrl': (request['imageUrls'] as List<Object?>? ?? []).join(','),
      'answer': answer,
      'aiType': request['aiType'],
      'chatGroupId': groupId,
    });
    yield _event({}, finish: 'stop');
  }

  /// Only the harness-owned system marker enables this local protocol fixture.
  /// Normal chat, even when it quotes a tool call, retains its existing behavior.
  String? _agentAnswer(String prompt, List<dynamic> history) {
    final systems = history.whereType<Map<dynamic, dynamic>>().where(
          (entry) =>
              entry['role'] == 'system' &&
              entry['content'] is String &&
              (entry['content'] as String).startsWith(genAiAgentProtocolMarker),
        );
    final nonce = systems.isEmpty
        ? null
        : genAiAgentNonceFromSystem(systems.first['content'] as String);
    if (nonce == null) return null;
    final userMessages = <String>[
      for (final entry in history)
        if (entry is Map &&
            entry['role'] == 'user' &&
            entry['content'] is String)
          entry['content'] as String,
      prompt,
    ];
    final responses = <String, Map<String, Object?>>{};
    var goal = '';
    var goalNumber = 0;
    for (final text in userMessages) {
      final response = _agentToolResponse(text);
      if (response == null) {
        goal = text;
        goalNumber++;
        responses.clear();
      } else if (response['name'] is String) {
        responses[response['name'] as String] = response;
      }
    }
    final lower = goal.toLowerCase();
    final imageGoal =
        RegExp('图片|图像|画一|画个|海报|image|picture|illustrat').hasMatch(lower);
    final courtGoal =
        RegExp('球场|场地|预约|羽毛球|乒乓|网球|匹克|court|reserve').hasMatch(lower);
    final searchAvailable = (systems.first['content'] as String)
        .split('AVAILABLE_TOOLS:')
        .last
        .contains('"name":"web_search"');
    final sequence = imageGoal
        ? const ['generate_image']
        : courtGoal
            ? const ['get_current_time', 'reserve_court']
            : [
                'get_current_time',
                'get_semesters',
                if (searchAvailable) 'web_search',
                'get_week_schedule',
                'get_assignments',
              ];
    for (final name in sequence) {
      if (responses.containsKey(name)) continue;
      final arguments = <String, Object?>{};
      if (name == 'web_search') {
        arguments['query'] = '上海科技大学 公开校园资源 图书馆';
      } else if (name == 'generate_image') {
        arguments.addAll({
          'prompt': goal,
          'width': 1024,
          'height': 1024,
          'quality': 'low',
        });
      } else if (name == 'reserve_court') {
        final time = responses['get_current_time']?['result'];
        final explicitDate = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(goal)?[0];
        final date = explicitDate ?? _agentDate(time);
        if (date == null) {
          return '本地演示：当前时间工具未返回有效日期，尚未查询或预约场地。';
        }
        arguments.addAll({
          'action': 'availability',
          'sport': lower.contains('网球') || lower.contains('tennis')
              ? 'tennis'
              : lower.contains('乒乓') || lower.contains('pingpong')
                  ? 'pingpong'
                  : lower.contains('匹克') || lower.contains('pickleball')
                      ? 'pickleball'
                      : 'badminton',
          'date': date,
          'time_slot': 8,
        });
      }
      return encodeGenAiAgentCall(
        GenAiAgentToolCall(
          id: 'demo_${goalNumber}_${sequence.indexOf(name) + 1}_$name',
          name: name,
          arguments: arguments,
        ),
        nonce: nonce,
      );
    }
    final output = StringBuffer();
    for (final name in sequence) {
      final response = responses[name]!;
      if (response['ok'] != true) {
        final error = response['error'];
        final message = error is Map ? error['message'] : null;
        output.writeln('**${_agentToolLabel(name)}**：'
            '${_agentText(message, fallback: '工具未能完成请求。')}');
        if (name == 'reserve_court') output.writeln('尚未提交任何场地预约。');
        if (name == 'generate_image') {
          final code = error is Map ? error['code'] : null;
          output.writeln(
            code == 'approval_denied' || code == 'denied'
                ? '已取消，未执行生图。'
                : '未确认生成成功，请先查看图片历史。',
          );
        }
      } else {
        final result = response['result'];
        output.writeln(
          result is Map
              ? _agentSummary(name, result)
              : '**${_agentToolLabel(name)}**：工具没有返回可展示的信息。',
        );
      }
      output.writeln();
    }
    output.write('*本地确定性演示，未调用校园模型。*');
    return output.toString();
  }

  String _agentSummary(String name, Map<dynamic, dynamic> result) {
    switch (name) {
      case 'web_search':
        final citations = result['citations'];
        final count = citations is List ? citations.length : 0;
        return '**公开资源**：已通过联网搜索工具检索 $count 条参考来源，可展开搜索步骤查看。';
      case 'get_current_time':
        final time = result['campus_time'] ?? result['date'];
        return '**当前时间**：${_agentCampusTime(time)}（上海）';
      case 'get_semesters':
        final id = result['selected_semester_id'];
        final semesters = result['semesters'];
        final selected = semesters is List
            ? semesters
                .whereType<Map<dynamic, dynamic>>()
                .where((item) => item['id'] == id)
                .firstOrNull
            : null;
        return '**当前学期**：${_agentText(selected?['label'] ?? id, fallback: '尚未选择')}';
      case 'get_week_schedule':
        final rows = _agentRows(result['courses']);
        final week = result['week'];
        final title = week is int ? '第 $week 周课表' : '本周课表';
        final output = StringBuffer('**$title**：本次返回 ${rows.length} 节课');
        if (result['truncated'] == true) output.write('，还有更多课程');
        output.writeln('。');
        for (final course in rows.take(3)) {
          final day = course['weekday'];
          final weekday = day is int && day >= 1 && day <= 7
              ? '周${'一二三四五六日'[day - 1]} '
              : '';
          final start = course['start_time'];
          final end = course['end_time'];
          final time = start is String && end is String ? '$start–$end ' : '';
          output.writeln(
            '- $weekday$time${_agentText(course['name'], fallback: '未命名课程')}',
          );
        }
        if (rows.length > 3) output.writeln('其余课程可展开课表工具卡片查看。');
        return output.toString().trimRight();
      case 'get_assignments':
        final rows = _agentRows(result['assignments']);
        final output = StringBuffer('**作业与截止时间**：本次返回 ${rows.length} 项');
        if (result['truncated'] == true) output.write('，还有更多待办');
        output.writeln('。');
        for (final assignment in rows.take(3)) {
          final due = assignment['due'];
          final deadline =
              due is String ? ' · 截止 ${_agentCampusTime(due)}（上海）' : '';
          output.writeln(
            '- ${_agentText(assignment['title'], fallback: '未命名作业')}$deadline',
          );
        }
        if (rows.length > 3) output.writeln('其余待办可展开作业工具卡片查看。');
        if (result['partial'] == true) output.writeln('部分来源尚未同步完整。');
        return output.toString().trimRight();
      case 'generate_image':
        final images = result['images'];
        if (result['status'] != 'generated' ||
            images is! List ||
            images.isEmpty) {
          return '工具未返回已确认的图片，请先查看图片历史。';
        }
        return '工具已返回 ${images.length} 张图片，已显示在聊天中，点击图片可放大查看。';
      case 'reserve_court':
        final rows = _agentRows(result['availability']);
        return '已收到 ${rows.length} 个时段的场地查询结果，可展开工具卡片查看。尚未提交任何场地预约。';
      default:
        return '${_agentToolLabel(name)}已完成，可展开工具卡片查看结果。';
    }
  }

  List<Map<dynamic, dynamic>> _agentRows(Object? value) => value is List
      ? value.whereType<Map<dynamic, dynamic>>().toList()
      : const [];

  String _agentText(Object? value, {required String fallback}) {
    if (value is! String || value.trim().isEmpty) return fallback;
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length <= 100 ? text : '${text.substring(0, 100)}…';
  }

  String _agentCampusTime(Object? value) {
    if (value is! String) return '未知';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return value;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return _agentText(value, fallback: '未知');
    final campus = parsed.toUtc().add(const Duration(hours: 8));
    String two(int part) => part.toString().padLeft(2, '0');
    return '${campus.year}-${two(campus.month)}-${two(campus.day)} '
        '${two(campus.hour)}:${two(campus.minute)}';
  }

  Map<String, Object?>? _agentToolResponse(String text) =>
      decodeGenAiAgentRecord(text)?.result;

  String? _agentDate(Object? value) {
    if (value is! Map) return null;
    for (final key in [
      'campus_time',
      'date',
      'local_date',
      'local_time',
      'iso',
      'iso8601',
    ]) {
      final field = value[key];
      if (field is String) {
        final match = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(field);
        if (match != null) return match[0];
      }
    }
    return null;
  }

  String _agentToolLabel(String name) => switch (name) {
        'web_search' => '联网搜索',
        'get_current_time' => '当前时间',
        'get_semesters' => '学期',
        'get_week_schedule' => '本周课表',
        'get_assignments' => '作业与截止时间',
        'reserve_court' => '场地查询',
        'generate_image' => '图片创作',
        _ => name,
      };

  List<int> _event(Map<String, String> delta, {String? finish}) =>
      utf8.encode('data: ${jsonEncode({
            'choices': [
              {
                'index': 0,
                'delta': delta,
                if (finish != null) 'finish_reason': finish,
              }
            ],
          })}\n\n');

  @override
  void dispose() {
    for (final operation in _operations.toList()) {
      operation.cancel();
    }
    _operations.clear();
  }
}

final class DemoGenAiSessionStore implements GenAiSessionStore {
  final _sessions = <String, GenAiSession>{};
  @override
  Future<GenAiSession?> read(GenAiOwner owner) async =>
      _sessions[owner.storageId];
  @override
  Future<void> write(GenAiSession session) async {
    _sessions[session.owner.storageId] = session;
  }

  @override
  Future<void> delete(GenAiOwner owner) async {
    _sessions.remove(owner.storageId);
  }
}

final class GenAiDemo {
  GenAiDemo._(this.backend, this.sessions, this.chat, this.workspace);
  final DemoGenAiBackend backend;
  final GenAiSessionService sessions;
  final GenAiChatService chat;
  final GenAiWorkspaceController workspace;

  static Future<GenAiDemo> create({
    bool connected = true,
    Duration chunkDelay = const Duration(milliseconds: 32),
  }) async {
    final backend = DemoGenAiBackend(chunkDelay: chunkDelay);
    final api = GenAiApiClient(
      transport: backend,
      signer: const GenAiRequestSigner('synthetic-signing-salt'),
    );
    final sessions =
        GenAiSessionService(api: api, store: DemoGenAiSessionStore());
    await sessions.setOwner(
      const GenAiOwner(
        primaryUserId: 'preview-primary',
        studentId: DemoGenAiBackend.studentId,
        bindingId: 'preview-binding',
      ),
    );
    if (connected) {
      await sessions
          .connect(const GenAiCredential(token: DemoGenAiBackend.token));
    }
    final repository = GenAiRepository(api: api, sessions: sessions);
    final chat = GenAiChatService(repository);
    final workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
    );
    return GenAiDemo._(backend, sessions, chat, workspace);
  }

  void dispose() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    backend.dispose();
  }
}
