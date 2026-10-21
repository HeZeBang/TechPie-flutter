import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/genai_chat_service.dart';
import '../application/genai_repository.dart';
import '../application/genai_session_service.dart';
import '../application/genai_workspace_controller.dart';
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
        'url': 'temp/demo-upload-${DateTime.now().millisecondsSinceEpoch}.png',
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
    if (prompt.contains('样式') ||
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
      'answer': answer,
      'aiType': request['aiType'],
      'chatGroupId': groupId,
    });
    yield _event({}, finish: 'stop');
  }

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
