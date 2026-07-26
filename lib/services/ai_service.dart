import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_client/flutter_ai_client.dart';
import 'package:flutter_ai_core/flutter_ai_core.dart';
import 'package:flutter_ai_provider_anthropic/flutter_ai_provider_anthropic.dart';
import 'package:flutter_ai_tools/flutter_ai_tools.dart';

import '../models/ai_chat.dart';
import 'ai_tools.dart';
import 'assignment_service.dart';
import 'schedule_service.dart';
import 'storage_service.dart';
import 'third_party_auth_service.dart';

/// Central state for the AI Assistant feature.
///
/// Wraps the library's [UseChatController] (the streaming state machine) and an
/// [AnthropicProvider], exposing TechPie's own chat API so the rest of the app
/// — UI, config page, history, gallery — binds to a single `ChangeNotifier`
/// exactly as before. The controller's notifications are forwarded to this
/// service's listeners, so `ListenableBuilder(listenable: aiService, ...)`
/// keeps working.
///
/// Responsibilities split as: the controller owns the live transcript + stream
/// state (in library [AiConversation] form); this service owns the [AiConfig]
/// (persisted), the list of persisted [AiThread]s (TechPie's metadata +
/// messages), the current-thread pointer, and serializing the controller's
/// transcript back to [StorageService] when a turn settles.
class AiService extends ChangeNotifier {
  final StorageService _storage;
  final ScheduleService _schedule;
  final AssignmentService _assignments;
  final ThirdPartyAuthService _tpAuth;

  /// The campus-service tools the model can call. Built once at construction.
  late final ToolRegistry _tools = buildAiTools(
    scheduleService: _schedule,
    assignmentService: _assignments,
    thirdPartyAuthService: _tpAuth,
  );

  AiConfig _config = AiConfig.defaults();
  List<AiThread> _conversations = const [];
  String? _currentConversationId;

  /// The library controller. Lazily created once config is available so an
  /// unconfigured app doesn't spin up a provider with an empty key.
  UseChatController? _controller;
  AnthropicProvider? _provider;

  /// True while the controller's forward-listener is active, to avoid
  /// re-entrant notifyListeners churn.
  bool _forwarding = false;

  /// A service-level error surfaced ahead of any network call (e.g. the app
  /// isn't configured yet). Cleared when a real turn starts or config is saved.
  String? _userError;

  /// Last-seen controller status / error, to detect transitions worth notifying
  /// the UI about (streaming start/stop, error appear/clear) without firing on
  /// every token.
  ChatStatus? _lastStatus;
  Object? _lastError;

  /// Debounced persistence timer.
  Timer? _persistTimer;

  AiService(
    this._storage,
    this._schedule,
    this._assignments,
    this._tpAuth,
  );

  // ---- Accessors ----

  AiConfig get config => _config;

  bool get isConfigured => _config.hasAuthToken;

  bool get isStreaming {
    final c = _controller;
    // isBusy covers submitted/streaming/executingTools — the tool-execution
    // phase must count as busy too, or the UI re-enables input mid agent-loop
    // and a new send() lands on a transcript with unanswered tool calls.
    return c != null && c.status.isBusy;
  }

  /// The error from the last failed turn, surfaced as a string for the UI
  /// banner. Returns null when idle/healthy. Prefers a service-level user
  /// error (e.g. "not configured") over the controller's last network error.
  String? get streamingError {
    if (_userError != null) return _userError;
    final c = _controller;
    if (c == null) return null;
    final err = c.error;
    if (err == null) return null;
    if (err is LlmException) {
      // LlmException carries a status code + body, not a plain message. Map
      // auth failures to a friendlier hint; otherwise surface the body.
      if (err is LlmAuthException) {
        return '认证失败（${err.statusCode}）：请检查 API 令牌与端点。';
      }
      final body = err.body;
      final detail =
          body.isEmpty ? err.toString() : (body.length > 200 ? '${body.substring(0, 200)}…' : body);
      return '请求失败（${err.statusCode}）：$detail';
    }
    return '发生错误：$err';
  }

  List<AiThread> get conversations {
    final list = [..._conversations];
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  AiThread? get currentConversation {
    final id = _currentConversationId;
    if (id == null) return null;
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The library chat controller the UI binds to (AiChat / AiPromptInput).
  ///
  /// Lazily built on first access. The controller owns the live transcript +
  /// streaming state; this service mirrors its transcript back into the
  /// persisted [AiThread] list (see [_onControllerChanged]) and owns config /
  /// conversation metadata. Thread switches happen via [selectConversation] /
  /// [newConversation] (which call `controller.load`), NOT here — re-loading
  /// on every build would tear down an in-flight stream.
  UseChatController get controller => _ensureController(forCurrent: false);

  // ---- Lifecycle ----

  Future<void> initialize() async {
    _config = await _storage.loadAiConfig();
    _conversations = _storage.loadAiConversations();
    if (_conversations.isEmpty) {
      // Start the user with one fresh conversation so the chat is never empty.
      final fresh = _newConversation();
      _conversations = [fresh];
      _currentConversationId = fresh.id;
    } else {
      _currentConversationId = conversations.first.id;
    }
    _ensureController(forCurrent: true);
    notifyListeners();
  }

  // ---- Config ----

  Future<void> saveConfig(AiConfig config) async {
    _config = config;
    // Token goes to secure storage; the rest to prefs (token stripped inside).
    await _storage.saveAiAuthToken(config.authToken);
    await _storage.saveAiConfig(config);
    // Re-point the controller's provider/options to the new config.
    _ensureController(forCurrent: true);
    _controller?.setProvider(_buildProvider());
    _controller?.setOptions(_buildOptions());
    // A fresh config clears any "not configured" prompt.
    _userError = null;
    notifyListeners();
  }

  // ---- Conversations ----

  /// Create and switch to a new conversation, optionally seeded with a prompt
  /// (used by the gallery).
  AiThread newConversation({String? seedPrompt}) {
    final conv = _newConversation();
    _conversations = [..._conversations, conv];
    _currentConversationId = conv.id;
    _ensureController(forCurrent: true);
    _schedulePersist();
    notifyListeners();
    return conv;
  }

  void selectConversation(String id) {
    if (_currentConversationId == id) return;
    final conv = _conversationById(id);
    if (conv == null) return;
    _controller?.stop();
    _currentConversationId = id;
    _ensureController(forCurrent: true);
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    if (_currentConversationId == id) {
      _controller?.stop();
    }
    _conversations = _conversations.where((c) => c.id != id).toList();
    if (_currentConversationId == id) {
      _currentConversationId =
          _conversations.isEmpty ? null : conversations.first.id;
      if (_conversations.isEmpty) {
        final fresh = _newConversation();
        _conversations = [fresh];
        _currentConversationId = fresh.id;
      }
      _ensureController(forCurrent: true);
    }
    _schedulePersist();
    notifyListeners();
  }

  Future<void> clearAllConversations() async {
    _controller?.stop();
    await _storage.clearAiConversations();
    _conversations = [_newConversation()];
    _currentConversationId = _conversations.first.id;
    _ensureController(forCurrent: true);
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    _conversations = [
      for (final c in _conversations)
        if (c.id == id) c.copyWith(title: title) else c,
    ];
    _schedulePersist();
    notifyListeners();
  }

  // ---- Sending / streaming ----

  /// Send [text] as a user turn and stream the assistant reply. If [text] is
  /// empty, re-streams the last user turn (regenerate). Errors are captured
  /// into [streamingError] (via the controller's `error`), not thrown.
  Future<void> send(String text, {String? conversationId}) async {
    final c = _ensureController(forCurrent: true);
    if (!_config.hasAuthToken) {
      _userError = '请先在设置中填写 API 令牌';
      notifyListeners();
      return;
    }
    if (c.status.isBusy) return;
    // Starting a real turn — clear any prior service-level error.
    if (_userError != null) {
      _userError = null;
      notifyListeners();
    }

    // Auto-title from the first user message if untitled.
    final convId = conversationId ?? _currentConversationId;
    if (convId != null && _conversationById(convId)?.title == '新对话') {
      final firstUserText = text.trim().isNotEmpty ? text : _lastUserText(c);
      if (firstUserText != null) {
        unawaited(renameConversation(convId, _deriveTitle(firstUserText)));
      }
    }

    if (text.trim().isNotEmpty) {
      await c.sendText(text);
    } else {
      // Regenerate: re-run from the last user message.
      await c.regenerate();
    }
  }

  /// Stop an in-flight stream. The partial assistant text is kept.
  void stop() => _controller?.stop();

  // ---- Controller plumbing ----

  /// Lazily build (or re-seat) the controller for the current conversation.
  /// When [forCurrent] is true and the controller already exists, the current
  /// conversation is loaded into it (thread switch). Returns the controller.
  UseChatController _ensureController({required bool forCurrent}) {
    if (_controller == null) {
      _controller = UseChatController(
        provider: _buildProvider(),
        options: _buildOptions(),
        // Campus-service tools (schedule / assignments / time). Providing
        // onToolCalls turns the controller into an automatic agent loop:
        // after a stream, pending ToolCallParts are executed, results are
        // appended as an AiRole.tool message, and the model is re-prompted —
        // repeating until no tool calls remain (bounded by maxSteps=8).
        tools: _tools.definitions,
        onToolCalls: (calls, signal) async {
          // Run each call through the registry; it catches per-tool failures
          // as isError results so one bad tool doesn't kill the batch.
          final results = <ToolResultPart>[];
          for (final call in calls) {
            if (signal.isCancelled) break;
            results.add(await _tools.run(call));
          }
          return results;
        },
      );
      _controller!.addListener(_onControllerChanged);
    }
    if (forCurrent) {
      final conv = currentConversation;
      if (conv != null) {
        _controller!.load(_withSystemMessage(conv.conversation));
      }
    }
    return _controller!;
  }

  void _onControllerChanged() {
    if (_forwarding) return;
    _forwarding = true;
    try {
      // Mirror the controller's live transcript into the persisted thread so
      // currentConversation reflects streamed tokens. Done silently — token
      // arrivals must NOT call notifyListeners, or the page rebuilds every
      // token and AiChat's scroll/anchor logic fights the rebuild (visible as
      // flicker + no smooth auto-scroll). AiChat listens to the controller
      // directly for live transcript updates.
      _syncCurrentFromController();
      final status = _controller?.status;
      final error = _controller?.error;
      // Only surface a notification when something the UI actually cares about
      // changes: streaming started/stopped, or an error appeared/cleared.
      // Token-only changes (status stays streaming, same error) are silent.
      final statusChanged = status != _lastStatus;
      final errorChanged = error != _lastError;
      _lastStatus = status;
      _lastError = error;
      if (statusChanged || errorChanged) {
        notifyListeners();
      }
      // Persist once the turn settles (status leaves streaming).
      if (status != ChatStatus.streaming) {
        _schedulePersist();
      }
    } finally {
      _forwarding = false;
    }
  }

  /// Copy the controller's transcript into the persisted thread record.
  void _syncCurrentFromController() {
    final id = _currentConversationId;
    final c = _controller;
    if (id == null || c == null) return;
    // Strip the leading system message before persisting — it's re-injected
    // from config on load, so we don't want it duplicated across saves.
    final messages =
        c.conversation.messages.where((m) => m.role != AiRole.system).toList();
    _conversations = [
      for (final conv in _conversations)
        if (conv.id == id)
          conv.copyWith(messages: messages, updatedAt: DateTime.now())
        else
          conv,
    ];
  }

  /// The conversation with the configured system prompt prepended (the
  /// AnthropicProvider folds `AiRole.system` messages into the request's
  /// top-level `system` field).
  AiConversation _withSystemMessage(AiConversation conv) {
    final prompt = _config.systemPrompt;
    if (prompt.trim().isEmpty) return conv;
    if (conv.messages.any((m) => m.role == AiRole.system)) return conv;
    final systemMsg = AiMessage(
      id: 'system-${conv.id}',
      role: AiRole.system,
      parts: [TextPart(prompt)],
    );
    return conv.copyWith(messages: [systemMsg, ...conv.messages]);
  }

  AnthropicProvider _buildProvider() {
    // Reuse an existing provider when auth + endpoint are unchanged; otherwise
    // build fresh and close the old one. (baseUrl is private on the provider,
    // so we track the resolved URL ourselves for the reuse check.)
    final previous = _provider;
    final resolved = normalizeAiBaseUrl(_config.baseUrl);
    if (previous != null &&
        previous.apiKey == _config.authToken &&
        _resolvedBaseUrl == resolved) {
      return previous;
    }
    previous?.close();
    final provider = AnthropicProvider(
      apiKey: _config.authToken.isEmpty ? 'unset' : _config.authToken,
      baseUrl: Uri.parse(resolved),
      defaultModel: _config.model,
      defaultMaxTokens: _config.maxTokens,
      timeout: const Duration(seconds: 90),
    );
    _provider = provider;
    _resolvedBaseUrl = resolved;
    return provider;
  }

  String? _resolvedBaseUrl;

  AiRequestOptions? _buildOptions() {
    return AiRequestOptions(
      model: _config.model,
      temperature: _config.temperature,
      maxOutputTokens: _config.maxTokens,
    );
  }

  String? _lastUserText(UseChatController c) {
    for (final m in c.conversation.messages.reversed) {
      if (m.role == AiRole.user) return m.text;
    }
    return null;
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_storage.saveAiConversations(_conversations));
    });
  }

  AiThread _newConversation() => AiThread(
        id: _id(),
        title: '新对话',
        messages: const [],
        updatedAt: DateTime.now(),
      );

  AiThread? _conversationById(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  String _deriveTitle(String text) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.isEmpty ? '新对话' : (t.length > 20 ? '${t.substring(0, 20)}…' : t);
  }

  String _id() => 'm${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  int _counter = 0;

  @override
  void dispose() {
    _persistTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _provider?.close();
    super.dispose();
  }
}
