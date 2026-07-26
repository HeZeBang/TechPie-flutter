import 'package:flutter/services.dart';
import 'package:flutter_ai_core/flutter_ai_core.dart'
    show ToolCallPart, ToolCallState, ToolResultPart;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:techpie/models/ai_chat.dart';
import 'package:techpie/services/ai_service.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage_ohos reads via this method channel; in unit tests
  // there's no plugin, so stub it to behave as empty storage.
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'read':
        return null; // nothing stored → AiService loads defaults
      case 'write':
      case 'delete':
        return null;
      default:
        return null;
    }
  });

  late StorageService storage;
  late AiService ai;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments =
        AssignmentService(storage, http, auth, tpAuth, schedule);
    ai = AiService(storage, schedule, assignments, tpAuth);
    await ai.initialize();
  });

  group('AiThread serialization', () {
    test('round-trips through JSON with a single text part', () {
      final thread = AiThread(
        id: 't1',
        title: 'hello',
        updatedAt: DateTime.utc(2026, 7, 26),
        messages: [
          AiMessage(
            id: 'm1',
            role: AiRole.user,
            parts: [TextPart('hi there')],
          ),
        ],
      );
      final json = thread.toJson();
      final restored = AiThread.fromJson(json);

      expect(restored.id, 't1');
      expect(restored.title, 'hello');
      expect(restored.messages, hasLength(1));
      expect(restored.messages.first.role, AiRole.user);
      expect(restored.messages.first.text, 'hi there');
      expect(restored.messages.first.parts.first, isA<TextPart>());
    });

    test('empty-content non-system messages are dropped on load', () {
      final raw = {
        'id': 't2',
        'title': 'x',
        'updatedAt': '2026-07-26T00:00:00.000Z',
        'messages': [
          {'id': 'a', 'role': 'user', 'status': 'complete', 'parts': [
            {'type': 'text', 'text': ''},
          ]},
          {'id': 'b', 'role': 'assistant', 'status': 'complete', 'parts': [
            {'type': 'text', 'text': 'real reply'},
          ]},
        ],
      };
      final restored = AiThread.fromJson(raw);
      expect(restored.messages, hasLength(1));
      expect(restored.messages.first.text, 'real reply');
    });

    test('tool-result messages survive a persistence round-trip', () {
      // Tool messages have no text part. The load filter must not drop them:
      // losing a tool result leaves its tool_use unanswered, and providers
      // reject the whole conversation on the next request.
      final thread = AiThread(
        id: 't3',
        title: 'x',
        updatedAt: DateTime.utc(2026, 7, 26),
        messages: const [
          AiMessage(id: 'u', role: AiRole.user, parts: [TextPart('几点了')]),
          AiMessage(
            id: 'a',
            role: AiRole.assistant,
            parts: [
              ToolCallPart(
                toolCallId: 'c1',
                toolName: 'get_current_time',
                state: ToolCallState.inputAvailable,
              ),
            ],
            status: AiMessageStatus.complete,
          ),
          AiMessage(
            id: 't',
            role: AiRole.tool,
            parts: [
              ToolResultPart(
                toolCallId: 'c1',
                result: {'now': '2026-07-26T12:00:00'},
              ),
            ],
            status: AiMessageStatus.complete,
          ),
        ],
      );
      final restored = AiThread.fromJson(thread.toJson());
      expect(restored.messages, hasLength(3));
      expect(restored.messages[2].role, AiRole.tool);
      expect(
        restored.messages[2].parts.single,
        isA<ToolResultPart>(),
      );
    });
  });

  group('AiService lifecycle', () {
    test('initialize seeds one fresh conversation', () {
      expect(ai.conversations, hasLength(1));
      expect(ai.currentConversation, isNotNull);
      expect(ai.currentConversation!.title, '新对话');
      expect(ai.isConfigured, isFalse);
      expect(ai.isStreaming, isFalse);
    });

    test('newConversation adds a thread and switches to it', () {
      final first = ai.currentConversation!.id;
      final created = ai.newConversation();
      expect(ai.conversations, hasLength(2));
      expect(ai.currentConversation!.id, created.id);
      expect(created.id, isNot(first));
    });

    test('renameConversation updates title and is reflected in the list', () {
      final id = ai.currentConversation!.id;
      ai.renameConversation(id, '我的对话');
      expect(ai.currentConversation!.title, '我的对话');
    });

    test('deleteConversation on the current thread re-points to another', () {
      final a = ai.newConversation();
      final b = ai.newConversation();
      expect(ai.currentConversation!.id, b.id);
      ai.deleteConversation(b.id);
      expect(ai.conversations.any((c) => c.id == b.id), isFalse);
      expect(ai.currentConversation, isNotNull);
      expect(ai.currentConversation!.id, isNot(b.id));
      expect(ai.conversations.any((c) => c.id == a.id), isTrue);
    });

    test('clearAllConversations leaves exactly one fresh thread', () async {
      ai.newConversation();
      ai.newConversation();
      await ai.clearAllConversations();
      expect(ai.conversations, hasLength(1));
      expect(ai.currentConversation!.title, '新对话');
    });

    test('selectConversation switches the current pointer', () {
      final a = ai.currentConversation!.id;
      final b = ai.newConversation().id;
      expect(ai.currentConversation!.id, b);
      ai.selectConversation(a);
      expect(ai.currentConversation!.id, a);
    });
  });

  group('baseUrl normalization', () {
    test('appends /v1 when missing', () {
      expect(
        normalizeAiBaseUrl('https://api.deepseek.com/anthropic'),
        'https://api.deepseek.com/anthropic/v1',
      );
    });

    test('strips a trailing /messages', () {
      expect(
        normalizeAiBaseUrl('https://api.deepseek.com/anthropic/v1/messages'),
        'https://api.deepseek.com/anthropic/v1',
      );
    });

    test('leaves an already-/v1 root untouched', () {
      expect(
        normalizeAiBaseUrl('https://api.deepseek.com/anthropic/v1'),
        'https://api.deepseek.com/anthropic/v1',
      );
    });

    test('trims trailing slashes', () {
      expect(
        normalizeAiBaseUrl('https://api.anthropic.com/v1/'),
        'https://api.anthropic.com/v1',
      );
    });

    test('falls back to the default for empty input', () {
      expect(normalizeAiBaseUrl(''), AiConfig.defaultBaseUrl);
    });
  });
}
