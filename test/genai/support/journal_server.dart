import 'dart:async';
import 'dart:convert';

import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_context_record.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';

import 'fakes.dart';

/// Fake remote server shared by otherwise independent application instances.
/// Records exactly chatInfo/answer; messages are deliberately not persisted.
class JournalServer {
  final rows = <String, List<Map<String, Object?>>>{};
  final generations = <Map<String, dynamic>>[];
  FutureOr<String> Function(Map<String, dynamic>)? onGenerate;
  Completer<void>? readGate;
  bool hideHistory = false;
  int deletes = 0;
  int summaries = 0;
  int _recordSequence = 0;
  bool failDelete = false;
  late final transport = ScriptedTransport((request) async {
    final path = request.uri.path;
    if (path.endsWith('/getByChatGroupId')) {
      final snapshot = List.of(
        rows[request.uri.queryParameters['chatGroupId']] ?? const <Map<String, Object?>>[],
      );
      await request.cancellation.race(readGate?.future ?? Future<void>.value());
      return response(
        json: {'success': true, 'code': 200, 'result': hideHistory ? <Object?>[] : snapshot},
      );
    }
    if (path.endsWith('/listByContentGroup')) {
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              for (final id in rows.keys) {'chatGroupId': id, 'question': 'server label'},
            ],
            'total': rows.length,
          },
        },
      );
    }
    if (path.endsWith('/delete/batch')) {
      deletes++;
      if (failDelete) return response(status: 500, json: {});
      final ids = request.uri.queryParameters['ids']!.split(',').toSet();
      for (final history in rows.values) {
        history.removeWhere((row) => ids.contains(row['id']));
      }
      return response(json: {'success': true, 'code': 200});
    }
    if (path.endsWith('/delete/groupId')) {
      deletes++;
      if (failDelete) return response(status: 500, json: {});
      rows.remove(request.uri.queryParameters['id']);
      return response(json: {'success': true, 'code': 200});
    }
    if (path.endsWith('/list')) {
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              {
                'aiName': 'Kimi-K3',
                'aiType': 'Kimi-k3',
                'rootAiType': 'xinference',
                'payType': 'FREE',
                'enableDeepThink': 1,
              },
            ],
          },
        },
      );
    }
    if (path.endsWith('/chat/upload/chat/file')) {
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'fileId': 'doc-1',
            'fileName': 'notes.txt',
            'content': 'The original number is 5837.',
          },
        },
      );
    }
    if (path.endsWith('/start/chat')) {
      final body = jsonDecode(request.body!) as Map<String, dynamic>;
      final prompt = body['chatInfo'] as String;
      String answer;
      if (isGenAiContextExtraction(prompt)) {
        summaries++;
        final source =
            jsonDecode(((body['messages'] as List).last as Map)['content'] as String) as List;
        answer = jsonEncode({
          'items': [
            for (final item in source.take(8))
              {
                'source': item['source'],
                'kind': 'fact',
                'quote': (item['text'] as String).split('\n').first,
              },
          ],
        });
      } else {
        generations.add(body);
        answer = await (onGenerate?.call(body) ?? 'Answer.');
      }
      request.cancellation.throwIfCancelled();
      (rows[body['chatGroupId'] as String] ??= []).add({
        'id': 'record-${++_recordSequence}',
        'question': (body['fileIds'] is List && (body['fileIds'] as List).isNotEmpty)
            ? '【上传文件：notes.txt】\n$prompt'
            : prompt,
        'answer': answer,
        'aiType': body['aiType'],
        'createTime': DateTime.now().toUtc().toIso8601String(),
      });
      Stream<List<int>> events() async* {
        yield utf8.encode(sseChunk(text: answer));
        yield utf8.encode(sseChunk(finish: 'stop'));
      }

      return response(type: 'text/event-stream', bytes: events());
    }
    return profileResponse();
  });

  String input(Map<String, dynamic> body) =>
      decodeGenAiRemoteRecord(body['chatInfo'] as String)?['input'] as String? ??
      body['chatInfo'] as String;

  String nonce(Map<String, dynamic> body) =>
      genAiAgentNonceFromSystem(((body['messages'] as List).first as Map)['content'] as String)!;

  String finalAnswer(Map<String, dynamic> body, String text) =>
      encodeGenAiAgentFinal(text, nonce: nonce(body));
  String call(
    Map<String, dynamic> body, {
    String name = 'get_semesters',
    Map<String, Object?> arguments = const {},
  }) =>
      encodeGenAiAgentCall(
        GenAiAgentToolCall(id: 'call-${generations.length}', name: name, arguments: arguments),
        nonce: nonce(body),
      );
}

class JournalClient {
  JournalClient._(this.sessions, this.repository, this.chat, this.workspace);
  final GenAiSessionService sessions;
  final GenAiRepository repository;
  final GenAiChatService chat;
  final GenAiWorkspaceController workspace;

  static Future<JournalClient> create(
    JournalServer server, {
    List<GenAiAgentTool> tools = const [],
    GenAiContextPolicy? policy,
  }) async {
    final api = GenAiApiClient(transport: server.transport);
    final sessions = GenAiSessionService(api: api, store: MemorySessionStore());
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'synthetic'));
    final repository = GenAiRepository(
      api: api,
      sessions: sessions,
      contextCompactor: policy == null ? null : GenAiContextCompactor(policy: policy),
    );
    final chat = GenAiChatService(repository);
    final workspace =
        GenAiWorkspaceController(sessions: sessions, repository: repository, chat: chat);
    workspace.configureAgent(
      runner: GenAiAgentRunner(
        streamChat: repository.streamChat,
        tools: () => GenAiAgentToolRegistry(tools),
      ),
    );
    await workspace.reloadModels();
    return JournalClient._(sessions, repository, chat, workspace);
  }

  void dispose() {
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
  }
}
