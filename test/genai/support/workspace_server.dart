import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/data/genai_request_signer.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

/// In-memory transport for streaming, history and workspace regression tests.
final class FakeGenAiServer implements GenAiTransport {
  FakeGenAiServer({this.chunkDelay = const Duration(milliseconds: 1)});

  final Duration chunkDelay;
  bool failUpload = false;
  static const token = 'test-token';
  static const studentId = '20240001';
  final _operations = <GenAiCancellation>{};
  int _uploadSequence = 0;
  final _history = <String, List<Map<String, Object?>>>{};
  final _images = <Map<String, Object?>>[];

  GenAiResponse _ok(Object? result) => _json({'success': true, 'code': 200, 'result': result});

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
          'userInfo': {'id': 'test-user', 'username': studentId},
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
              'aiName': 'Test chat',
              'aiType': 'test-general',
              'rootAiType': 'demo',
              'payType': 'FREE',
              'enableDeepThink': 1,
              'status': 3,
            },
            {
              'aiName': 'Test code',
              'aiType': 'test-code',
              'rootAiType': 'demo',
              'payType': 'FREE',
              'enableDeepThink': 1,
              'status': 3,
            },
            {
              'aiName': 'Test image',
              'aiType': 'test-image',
              'rootAiType': 'demo',
              'payType': 'PAID',
              'status': 2,
            },
          ],
        },
      });
    }
    if (uri.path == '/htk/chat/upload/chat/file') {
      return _ok({
        'fileId': 'test-file-${DateTime.now().millisecondsSinceEpoch}',
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
        'url': 'temp/test-upload-${++_uploadSequence}.png',
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
        : (body.startsWith('{') ? jsonDecode(body) as Map<String, dynamic> : <String, dynamic>{});
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
                        (turn) => (turn['question'] as String? ?? '').toLowerCase().contains(query),
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
    if (uri.path == '/htk/chat/start/chat' && data['aiType'] == 'test-image') {
      final path = 'test-images/image-${_images.length + 1}.png';
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
    final storedPrompt = request['chatInfo'] as String;
    final prompt = decodeGenAiRemoteRecord(storedPrompt)?['input'] as String? ?? storedPrompt;
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
    final answer = 'Response to: $prompt. Turn $turn.';
    for (var index = 0; index < answer.length; index += 5) {
      await cancellation.race(Future<void>.delayed(chunkDelay));
      cancellation.throwIfCancelled();
      yield _event({
        'content': answer.substring(index, (index + 5).clamp(0, answer.length)),
      });
    }
    final groupId = request['chatGroupId'] as String;
    _history.putIfAbsent(groupId, () => []).add({
      'question': storedPrompt,
      'createTime': DateTime.now().toUtc().toIso8601String(),
      'imageUrl': (request['imageUrls'] as List<Object?>? ?? []).join(','),
      'answer': answer,
      'aiType': request['aiType'],
      'chatGroupId': groupId,
    });
    yield _event({}, finish: 'stop');
  }

  List<int> _event(Map<String, String> delta, {String? finish}) => utf8.encode('data: ${jsonEncode({
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

final class TestGenAiSessionStore implements GenAiSessionStore {
  final _sessions = <String, GenAiSession>{};
  @override
  Future<GenAiSession?> read(GenAiOwner owner) async => _sessions[owner.storageId];
  @override
  Future<void> write(GenAiSession session) async {
    _sessions[session.owner.storageId] = session;
  }

  @override
  Future<void> delete(GenAiOwner owner) async {
    _sessions.remove(owner.storageId);
  }
}

final class TestGenAiWorkspace {
  TestGenAiWorkspace._(this.backend, this.sessions, this.chat, this.workspace);
  final FakeGenAiServer backend;
  final GenAiSessionService sessions;
  final GenAiChatService chat;
  final GenAiWorkspaceController workspace;

  static Future<TestGenAiWorkspace> create({
    bool connected = true,
    Duration chunkDelay = const Duration(milliseconds: 1),
  }) async {
    final backend = FakeGenAiServer(chunkDelay: chunkDelay);
    final api = GenAiApiClient(
      transport: backend,
      signer: const GenAiRequestSigner('synthetic-signing-salt'),
    );
    final sessions = GenAiSessionService(api: api, store: TestGenAiSessionStore());
    await sessions.setOwner(
      const GenAiOwner(
        primaryUserId: 'test-primary',
        studentId: FakeGenAiServer.studentId,
        bindingId: 'test-binding',
      ),
    );
    if (connected) {
      await sessions.connect(const GenAiCredential(token: FakeGenAiServer.token));
    }
    final repository = GenAiRepository(api: api, sessions: sessions);
    final chat = GenAiChatService(repository);
    final workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
    );
    return TestGenAiWorkspace._(backend, sessions, chat, workspace);
  }

  void dispose() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    backend.dispose();
  }
}
