import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_context_usage.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_document_upload.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'genai_agent_runner.dart';
import 'genai_agent_web_search.dart';
import 'genai_chat_service.dart';
import 'genai_conversation_store.dart';
import 'genai_conversation_turn.dart';
import 'genai_image_studio_controller.dart';
import 'genai_legacy_conversation_import.dart';
import 'genai_repository.dart';
import 'genai_session_service.dart';
import 'genai_system_prompt.dart';

export 'genai_conversation_turn.dart';

/// A host-prepared action awaiting an explicit decision in the chat UI.
final class GenAiPendingAgentApproval {
  GenAiPendingAgentApproval(this.call, this.prepared);

  final GenAiAgentToolCall call;
  final GenAiAgentPreparedTool prepared;
  final _result = Completer<bool>();
}

final class GenAiAttachment {
  const GenAiAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    this.fileId,
    this.documentContent,
    this.isImage = false,
    this.imageUrl,
    this.uploading = false,
    this.error,
  });

  final String id;
  final String name;
  final List<int> bytes;
  final String? fileId;
  final String? documentContent;
  final bool isImage;
  final String? imageUrl;
  final bool uploading;
  final String? error;

  GenAiAttachment copyWith({
    String? fileId,
    String? documentContent,
    String? imageUrl,
    bool? uploading,
    String? error,
    bool clearError = false,
  }) =>
      GenAiAttachment(
        id: id,
        name: name,
        bytes: bytes,
        fileId: fileId ?? this.fileId,
        documentContent: documentContent ?? this.documentContent,
        isImage: isImage,
        imageUrl: imageUrl ?? this.imageUrl,
        uploading: uploading ?? this.uploading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Owns the current in-memory conversation. The app runtime retains it across
/// page navigation; server history is a separate feature.
final class GenAiWorkspaceController extends ChangeNotifier {
  GenAiWorkspaceController({
    required this.sessions,
    required GenAiRepository repository,
    required GenAiChatService chat,
    GenAiConversationStore? conversationStore,
  })  : _conversationStore = conversationStore ?? MemoryGenAiConversationStore(),
        _repository = repository,
        _chat = chat {
    _owner = sessions.owner;
    _agentSessionRevision = sessions.revision;
    _archiveScope = _currentArchiveScope();
    sessions.addListener(_sessionChanged);
    _chat.addListener(_chatChanged);
    _sessionChanged();
  }

  final GenAiSessionService sessions;
  final GenAiConversationStore _conversationStore;
  final GenAiRepository _repository;
  late final imageStudio = GenAiImageStudioController(_repository);
  final GenAiChatService _chat;
  final _turns = <GenAiConversationTurn>[];
  GenAiOwner? _owner;
  GenAiSession? _catalogSession;
  GenAiCancellation? _catalogOperation;
  List<GenAiModel> _models = const [];
  GenAiModel? _selectedModel;
  GenAiConversationTurn? _active;
  GenAiFailure? _loginFailure;
  GenAiFailure? _catalogFailure;
  bool _connecting = false;
  bool _loadingModels = false;
  bool _disposed = false;
  bool _thinkingEnabled = false;
  bool _netSearchEnabled = false;
  bool _recognizingAudio = false;
  final _attachments = <GenAiAttachment>[];
  final _pendingUploads = <Future<void>>{};
  final _attachmentOperations = <String, GenAiCancellation>{};
  int _generation = 0;
  int _conversationLoad = 0;
  int _conversationRevision = 0;
  GenAiCancellation? _sendOperation;
  GenAiAgentRunner? _agentRunner;
  Object? Function()? _agentScope;
  Object? _agentScopeValue;
  Listenable? _agentScopeChanges;
  late int _agentSessionRevision;
  bool _agentEnabled = false;
  GenAiCancellation? _agentOperation;
  Future<void>? _agentDrain;
  GenAiPendingAgentApproval? _pendingAgentApproval;
  String _groupId = createGroupId();
  String? _archiveScope;
  String? _titleOverride;
  final _archiveFailures = <String, String>{};
  Future<void> _archiveWrites = Future.value();
  Timer? _archiveTimer;
  (String, String, int)? _dirtyArchive;
  final _pendingArchives = <String, (String, GenAiConversationArchive, int)>{};
  final _archiveVersions = <String, int>{};
  final _deletingArchives = <String>{};
  final _pendingLocalDeletes = <String, (String, String)>{};
  final _uncertainDeletions = <String, String>{};
  Map<String, Object?> _restoredMutations = const {
    'version': 1,
    'effects': <String, Object?>{},
  };
  bool _ledgerNeedsRestore = false;

  List<GenAiConversationTurn> get turns => List.unmodifiable(_turns);
  List<GenAiModel> get models => List.unmodifiable(_models.where((m) => !m.isImage));
  List<GenAiModel> get imageModels => List.unmodifiable(_models.where((m) => m.isImage));
  GenAiRepository get repository => _repository;

  /// Opaque identity for views containing account- or binding-scoped data.
  Object? get accountScope => _archiveScope;
  GenAiModel? get selectedModel => _selectedModel;
  GenAiFailure? get loginFailure => _loginFailure;
  GenAiFailure? get catalogFailure => _catalogFailure;
  GenAiFailure? get archiveFailure => _archiveFailures.containsValue(_archiveScope)
      ? const GenAiFailure(GenAiFailureKind.storage)
      : null;
  int get uncertainDeletionCount =>
      _uncertainDeletions.values.where((scope) => scope == _archiveScope).length;
  bool get connecting => _connecting;
  bool get loadingModels => _loadingModels;
  bool get sending => _active != null;
  bool get connected => sessions.session != null;
  bool get thinkingEnabled => _thinkingEnabled;
  bool get netSearchEnabled => _netSearchEnabled;
  bool get agentAvailable => _agentRunner != null;
  bool get agentEnabled => _agentEnabled;
  GenAiPendingAgentApproval? get pendingAgentApproval => _pendingAgentApproval;
  bool get recognizingAudio => _recognizingAudio;
  List<GenAiAttachment> get attachments => List.unmodifiable(_attachments);
  bool get hasPendingUploads => _attachments.any((a) => a.uploading) || _pendingUploads.isNotEmpty;
  bool get hasFailedUploads => _attachments.any((a) => a.error != null);
  String get groupId => _groupId;
  GenAiContextUsage? get contextUsage => _turns.lastOrNull?.contextUsage;

  /// Changes even when reopening the same saved conversation.
  int get conversationRevision => _conversationRevision;
  String get title => _titleOverride ?? (_turns.isEmpty ? '新的对话' : _turns.first.prompt);

  void toggleThinking() {
    _thinkingEnabled = !_thinkingEnabled;
    _notify();
  }

  void setThinking(bool value) {
    if (_thinkingEnabled == value) return;
    _thinkingEnabled = value;
    _notify();
  }

  /// Installs the app-owned tools once and watches every account binding used
  /// by them. The scope value must have stable equality (for example a record).
  void configureAgent({
    required GenAiAgentRunner runner,
    Object? Function()? scope,
    Listenable? scopeChanges,
  }) {
    if (_disposed) return;
    final nextScope = scope?.call();
    final replaced =
        _agentRunner != null && (!identical(_agentRunner, runner) || nextScope != _agentScopeValue);
    if (replaced) {
      newConversation();
      _agentRunner?.clear();
    }
    _agentScopeChanges?.removeListener(_agentScopeChanged);
    _flushPendingArchives();
    _agentRunner = runner;
    _agentScope = scope;
    _agentScopeValue = nextScope;
    _archiveScope = _currentArchiveScope();
    _agentScopeChanges = scopeChanges;
    _agentSessionRevision = sessions.revision;
    scopeChanges?.addListener(_agentScopeChanged);
    unawaited(_restoreDeletionIntents());
  }

  void _agentScopeChanged() {
    if (_disposed || _agentRunner == null) return;
    final scope = _agentScope?.call();
    if (scope == _agentScopeValue) return;
    _agentScopeValue = scope;
    newConversation();
    _agentRunner?.clear();
    unawaited(_restoreDeletionIntents());
  }

  void setAgentEnabled(bool value) {
    if (_disposed || sending || value == _agentEnabled) return;
    if (value && !agentAvailable) {
      return;
    }
    _agentScopeChanged();
    _agentEnabled = value;
    // A picker opened in the previous mode must not attach a late file.
    _conversationRevision++;
    _notify();
  }

  void toggleNetSearch() => setNetSearch(!_netSearchEnabled);

  void setNetSearch(bool value) {
    if (_disposed || sending || _netSearchEnabled == value) return;
    _netSearchEnabled = value;
    _notify();
  }

  void resolveAgentApproval(bool accepted, {GenAiPendingAgentApproval? expected}) {
    final pending = _pendingAgentApproval;
    if (pending == null || (expected != null && !identical(expected, pending))) return;
    _pendingAgentApproval = null;
    final current = !_disposed &&
        _agentOperation != null &&
        !_agentOperation!.isCancelled &&
        sessions.revision == _agentSessionRevision &&
        _agentScope?.call() == _agentScopeValue;
    if (!pending._result.isCompleted) {
      pending._result.complete(accepted && current);
    }
    _notify();
  }

  /// Leaving the main chat must not leave a hidden approval or agent running.
  /// Ordinary navigation preserves the visible transcript and mutation ledger.
  void cancelAgentForPageExit() {
    if (_active?.isAgent ?? false) stop();
  }

  Future<void> waitForPendingUploads() async {
    while (_pendingUploads.isNotEmpty) {
      await Future.wait(List.of(_pendingUploads));
    }
  }

  Future<void> retryAttachment(String id) async {
    final model = _selectedModel;
    if (_disposed || !connected || model == null) return;
    final index = _attachments.indexWhere((a) => a.id == id);
    if (index == -1) return;
    final attachment = _attachments[index];
    if (attachment.uploading) return;

    _attachments[index] = attachment.copyWith(
      uploading: true,
      clearError: true,
    );
    _notify();

    final uploadFuture = attachment.isImage
        ? _uploadImage(
            id,
            _attachments[index],
            attachment.name,
            attachment.bytes,
          )
        : _uploadDocument(
            id,
            _attachments[index],
            model.aiType,
            attachment.name,
            attachment.bytes,
          );
    _pendingUploads.add(uploadFuture);
    try {
      await uploadFuture;
    } finally {
      _pendingUploads.remove(uploadFuture);
    }
  }

  Future<void> addDocumentAttachment(String fileName, List<int> bytes) async {
    final model = _selectedModel;
    if (_disposed || !connected || model == null) return;
    final id = 'doc-${DateTime.now().microsecondsSinceEpoch}';
    final attachment = GenAiAttachment(
      id: id,
      name: fileName,
      bytes: bytes,
      uploading: true,
    );
    _attachments.add(attachment);
    _notify();
    final uploadFuture = _uploadDocument(id, attachment, model.aiType, fileName, bytes);
    _pendingUploads.add(uploadFuture);
    try {
      await uploadFuture;
    } finally {
      _pendingUploads.remove(uploadFuture);
    }
  }

  Future<void> _uploadDocument(
    String id,
    GenAiAttachment attachment,
    String aiType,
    String fileName,
    List<int> bytes,
  ) async {
    final operation = GenAiCancellation();
    _attachmentOperations[id] = operation;
    try {
      final uploaded = await _repository.uploadDocument(
        groupId: _groupId,
        aiType: aiType,
        fileName: fileName,
        bytes: bytes,
        c: operation,
      );
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = _attachments[index].copyWith(
          fileId: uploaded.fileId,
          documentContent: uploaded.content,
          uploading: false,
          clearError: true,
        );
      }
    } catch (e) {
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = _attachments[index].copyWith(
          uploading: false,
          error: switch (e) {
            GenAiDocumentUploadException() => e.message,
            GenAiFailure(kind: GenAiFailureKind.protocol) => '无法读取文档解析结果，请重新上传',
            _ => '上传失败，请重试；文档解析后不能超过 500,000 字符',
          },
        );
      }
    } finally {
      if (identical(_attachmentOperations[id], operation)) {
        _attachmentOperations.remove(id);
      }
      operation.cancel();
      _notify();
    }
  }

  Future<void> addImageAttachment(String fileName, List<int> bytes) async {
    if (_disposed || !connected) return;
    final id = 'img-${DateTime.now().microsecondsSinceEpoch}';
    final attachment = GenAiAttachment(
      id: id,
      name: fileName,
      bytes: bytes,
      isImage: true,
      uploading: true,
    );
    _attachments.add(attachment);
    _notify();
    final uploadFuture = _uploadImage(id, attachment, fileName, bytes);
    _pendingUploads.add(uploadFuture);
    try {
      await uploadFuture;
    } finally {
      _pendingUploads.remove(uploadFuture);
    }
  }

  Future<void> _uploadImage(
    String id,
    GenAiAttachment attachment,
    String fileName,
    List<int> bytes,
  ) async {
    final operation = GenAiCancellation();
    _attachmentOperations[id] = operation;
    try {
      final uploaded = await _repository.uploadVisionImage(
        fileName: fileName,
        bytes: bytes,
        c: operation,
      );
      final fullUrl = genAiImageUri(uploaded.url).toString();
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = _attachments[index].copyWith(
          imageUrl: fullUrl,
          uploading: false,
          clearError: true,
        );
      }
    } catch (e) {
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = _attachments[index].copyWith(
          uploading: false,
          error: '上传失败',
        );
      }
    } finally {
      if (identical(_attachmentOperations[id], operation)) {
        _attachmentOperations.remove(id);
      }
      operation.cancel();
      _notify();
    }
  }

  void removeAttachment(String id) {
    _attachmentOperations.remove(id)?.cancel();
    _attachments.removeWhere((a) => a.id == id);
    _notify();
  }

  void clearAttachments() {
    _cancelAttachments();
    _notify();
  }

  void _cancelAttachments() {
    for (final operation in _attachmentOperations.values) {
      operation.cancel();
    }
    _attachmentOperations.clear();
    _pendingUploads.clear();
    _attachments.clear();
  }

  Future<String?> transcribeAudio(String fileName, List<int> bytes) async {
    if (_disposed || !connected || _recognizingAudio) return null;
    _recognizingAudio = true;
    _notify();
    try {
      return await _repository.recognizeAudio(
        fileName: fileName,
        bytes: bytes,
        c: GenAiCancellation(),
      );
    } finally {
      _recognizingAudio = false;
      _notify();
    }
  }

  Future<List<int>> synthesizeSpeech(String text) async {
    if (_disposed || !connected) {
      throw const GenAiFailure(GenAiFailureKind.cancelled);
    }
    return _repository.convertTextToSpeech(
      text,
      GenAiCancellation(),
    );
  }

  static String createGroupId() {
    // The official client uses NanoID's 64-character alphabet and 21-byte
    // identifiers. The image endpoint rejects UUID-shaped group IDs with a
    // generic HTTP 500 even though chat requests may accept them.
    const alphabet = 'useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict';
    final random = Random.secure();
    return String.fromCharCodes(
      List<int>.generate(
        21,
        (_) => alphabet.codeUnitAt(random.nextInt(64)),
      ),
    );
  }

  Future<void> restore({bool reportAuthenticationRequired = false}) async {
    if (sessions.owner == null || _connecting || _disposed) return;
    _connecting = true;
    _notify();
    try {
      await sessions.requireSession();
    } on GenAiFailure catch (error) {
      if ((reportAuthenticationRequired || error.kind != GenAiFailureKind.authenticationRequired) &&
          error.kind != GenAiFailureKind.accountChanged) {
        _loginFailure = error;
      }
    } finally {
      _connecting = false;
      _notify();
    }
  }

  Future<void> connect(GenAiCredential credential) => connectUsing(() async {
        await sessions.connect(credential);
      });

  Future<void> connectUsing(Future<void> Function() operation) async {
    if (_connecting || _disposed) return;
    _connecting = true;
    _loginFailure = null;
    _notify();
    try {
      await operation();
    } on GenAiFailure catch (error) {
      if (error.kind != GenAiFailureKind.accountChanged) _loginFailure = error;
    } finally {
      _connecting = false;
      _notify();
    }
  }

  void _sessionChanged() {
    if (_disposed) return;
    final revisionChanged = _agentSessionRevision != sessions.revision;
    _agentSessionRevision = sessions.revision;
    if (_owner != sessions.owner) {
      _owner = sessions.owner;
      newConversation();
      _loginFailure = null;
      _agentRunner?.clear();
    } else if (revisionChanged && _agentRunner != null) {
      newConversation();
      _agentRunner?.clear();
    }
    final session = sessions.session;
    if (!identical(session, _catalogSession)) {
      _catalogSession = session;
      _catalogOperation?.cancel();
      _models = const [];
      _selectedModel = null;
      _loadingModels = false;
      _catalogFailure = null;
      if (session != null) unawaited(reloadModels());
    }
    _notify();
  }

  Future<void> reloadModels() async {
    if (!connected || _disposed) return;
    _catalogOperation?.cancel();
    final operation = GenAiCancellation();
    _catalogOperation = operation;
    _loadingModels = true;
    _catalogFailure = null;
    _notify();
    try {
      final models = await _repository.listModels(operation);
      if (_disposed || operation.isCancelled) return;
      final previous = _selectedModel;
      _models = models;
      // Paid-only catalogs require an explicit choice; no silent paid fallback.
      _selectedModel = models
              .where(
                (m) =>
                    !m.isImage &&
                    m.aiType == previous?.aiType &&
                    m.rootAiType == previous?.rootAiType,
              )
              .firstOrNull ??
          models.where((m) => !m.isImage && m.payType == 'FREE').firstOrNull;
    } on GenAiFailure catch (error) {
      if (!_disposed && !operation.isCancelled) _catalogFailure = error;
    } finally {
      if (identical(_catalogOperation, operation)) {
        _loadingModels = false;
        _catalogOperation = null;
      }
      operation.cancel();
      _notify();
    }
  }

  String? _currentArchiveScope() =>
      sessions.owner == null ? null : jsonEncode([sessions.owner!.storageId, _agentScopeValue]);

  String _archiveKey(String scope, String id) => '$scope:$id';

  GenAiConversationArchive _snapshot({Map<String, Object?>? mutations}) => GenAiConversationArchive(
        id: _groupId,
        title: title,
        updatedAt: DateTime.now(),
        turns: _turns,
        contextMemory: _repository.contextSnapshot(_groupId),
        agentEnabled: _agentEnabled,
        netSearchEnabled: _netSearchEnabled,
        thinkingEnabled: _thinkingEnabled,
        modelAiType: _selectedModel?.aiType,
        modelRootAiType: _selectedModel?.rootAiType,
        mutations: mutations ??
            (_ledgerNeedsRestore
                ? _restoredMutations
                : _agentRunner?.snapshotConversation(_groupId) ?? _restoredMutations),
      );

  void _scheduleArchive() {
    final scope = _archiveScope;
    if (scope == null || _turns.isEmpty) return;
    final key = _archiveKey(scope, _groupId);
    if (_deletingArchives.contains(key)) return;
    final version = (_archiveVersions[key] ?? 0) + 1;
    _archiveVersions[key] = version;
    // Streaming notifications only mark the current conversation dirty. Copy
    // its complete transcript once per batch, before any scope/turn reset.
    _dirtyArchive = (scope, _groupId, version);
    _pendingArchives.remove(key);
    _archiveTimer ??= Timer(const Duration(milliseconds: 100), _flushPendingArchives);
  }

  Future<void> _writeArchive(
    String scope,
    GenAiConversationArchive archive, {
    int? version,
    bool allowDeleting = false,
  }) {
    final key = _archiveKey(scope, archive.id);
    final writeVersion = version ?? (_archiveVersions[key] ?? 0) + 1;
    if (version == null) _archiveVersions[key] = writeVersion;
    final dirty = _dirtyArchive;
    if (dirty != null) {
      final (dirtyScope, id, dirtyVersion) = dirty;
      if (_archiveKey(dirtyScope, id) == key && dirtyVersion <= writeVersion) {
        _dirtyArchive = null;
      }
    }
    if ((_pendingArchives[key]?.$3 ?? 0) <= writeVersion) {
      _pendingArchives.remove(key);
    }
    final write = _archiveWrites.then((_) async {
      if (_deletingArchives.contains(key) && !allowDeleting) {
        throw const GenAiFailure(GenAiFailureKind.cancelled);
      }
      try {
        await _conversationStore.write(scope, archive);
        _archiveFailures.remove(key);
      } catch (_) {
        throw const GenAiFailure(GenAiFailureKind.storage);
      }
    });
    _archiveWrites = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        if (error is GenAiFailure && error.kind == GenAiFailureKind.cancelled) {
          return;
        }
        _archiveFailures[key] = scope;
        if (_archiveVersions[key] == writeVersion) {
          _pendingArchives.putIfAbsent(
            key,
            () => (scope, archive, writeVersion),
          );
        }
        if (!_disposed) notifyListeners();
      },
    );
    return write;
  }

  void _flushPendingArchives() {
    _archiveTimer?.cancel();
    _archiveTimer = null;
    final dirty = _dirtyArchive;
    if (dirty != null) {
      final (scope, id, version) = dirty;
      _dirtyArchive = null;
      final key = _archiveKey(scope, id);
      if (scope == _archiveScope && id == _groupId && !_deletingArchives.contains(key)) {
        _pendingArchives[key] = (scope, _snapshot(), version);
      }
    }
    final pending = _pendingArchives.values.toList();
    _pendingArchives.clear();
    for (final (scope, archive, version) in pending) {
      // _writeArchive attaches its own failure handler; a background save never
      // leaks an unhandled future and the UI exposes archiveFailure.
      unawaited(_writeArchive(scope, archive, version: version));
    }
  }

  Future<void> flushConversations() async {
    _flushPendingArchives();
    await _archiveWrites;
    final failure = archiveFailure;
    if (failure != null) throw failure;
  }

  Future<void> retrySaveConversations() async {
    await _archiveWrites;
    for (final entry in _pendingLocalDeletes.entries.toList()) {
      final (scope, id) = entry.value;
      await _conversationStore.delete(scope, id);
      _pendingLocalDeletes.remove(entry.key);
      _uncertainDeletions.remove(entry.key);
      _archiveFailures.remove(entry.key);
    }
    _scheduleArchive();
    await flushConversations();
    _notify();
  }

  void _checkArchiveScope(
    String scope,
    int revision, [
    GenAiCancellation? cancellation,
  ]) {
    cancellation?.throwIfCancelled();
    if (_disposed ||
        _archiveScope != scope ||
        sessions.revision != revision ||
        _agentScope?.call() != _agentScopeValue) {
      throw const GenAiFailure(GenAiFailureKind.accountChanged);
    }
  }

  Future<void> _restoreDeletionIntents() async {
    final scope = _archiveScope;
    if (scope == null || _disposed) return;
    try {
      final pending = await _conversationStore.pendingDeletionIds(scope);
      if (_disposed || _archiveScope != scope) return;
      _recordDeletionIntents(scope, pending);
      notifyListeners();
    } catch (_) {
      // Listing/export will surface storage failures with their normal retry
      // path. Never turn an unreadable deletion journal into a remote retry.
    }
  }

  void _recordDeletionIntents(String scope, Set<String> pending) {
    _uncertainDeletions.removeWhere((_, value) => value == scope);
    for (final id in pending) {
      final key = _archiveKey(scope, id);
      _deletingArchives.add(key);
      if (!_pendingLocalDeletes.containsKey(key)) {
        _uncertainDeletions[key] = scope;
      }
    }
  }

  Future<GenAiPageResult<GenAiConversationSummary>> listConversations(
    GenAiCancellation cancellation, {
    int page = 1,
    String query = '',
  }) async {
    _agentScopeChanged();
    final scope = _archiveScope;
    final revision = sessions.revision;
    if (scope == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    await flushConversations();
    final local = await _conversationStore.list(scope);
    _checkArchiveScope(scope, revision, cancellation);
    GenAiPageResult<GenAiConversationSummary> remote;
    try {
      remote = await _repository.listConversations(
        cancellation,
        page: page,
        query: query,
      );
    } on GenAiFailure catch (error) {
      _checkArchiveScope(scope, revision, cancellation);
      if (local.isEmpty ||
          error.kind == GenAiFailureKind.accountChanged ||
          error.kind == GenAiFailureKind.authenticationRequired ||
          error.kind == GenAiFailureKind.cancelled) {
        rethrow;
      }
      remote = GenAiPageResult(const [], page: page, hasMore: false);
    }
    cancellation.throwIfCancelled();
    if (_disposed || _archiveScope != scope || sessions.revision != revision) {
      throw const GenAiFailure(GenAiFailureKind.accountChanged);
    }
    // A remote listing can be slow. Renames, imports and deletions completed
    // meanwhile must win over the earlier local snapshot.
    final latestLocal = await _conversationStore.list(scope);
    final deleted = await _conversationStore.deletedIds(scope);
    final pendingDeletionIds = await _conversationStore.pendingDeletionIds(scope);
    _checkArchiveScope(scope, revision, cancellation);
    _recordDeletionIntents(scope, pendingDeletionIds);
    final localIds = latestLocal.map((item) => item.id).toSet();
    final queryLower = query.toLowerCase();
    return GenAiPageResult(
      [
        if (page == 1)
          ...latestLocal.where(
            (item) =>
                item.title.toLowerCase().contains(queryLower) &&
                !_deletingArchives.contains(_archiveKey(scope, item.id)),
          ),
        ...remote.records.where(
          (item) =>
              !localIds.contains(item.id) &&
              !deleted.contains(item.id) &&
              !_deletingArchives.contains(_archiveKey(scope, item.id)),
        ),
      ],
      page: page,
      hasMore: remote.hasMore,
    );
  }

  Future<void> deleteConversation(
    String id,
    GenAiCancellation cancellation,
  ) async {
    _agentScopeChanged();
    final revision = sessions.revision;
    final scope = _archiveScope;
    if (scope == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    final key = _archiveKey(scope, id);
    final current = _groupId == id;
    if (current) stop();
    final rollback = current && _turns.isNotEmpty ? _snapshot() : _pendingArchives[key]?.$2;
    _deletingArchives.add(key);
    _pendingArchives.remove(key);
    if (current) newConversation();
    var remoteDeleted = _pendingLocalDeletes.containsKey(key);
    var dispatched = false;
    var intentAttempted = false;
    var preexistingIntent = false;
    var localDeleted = false;
    try {
      await _archiveWrites;
      _checkArchiveScope(scope, revision, cancellation);
      final pending = await _conversationStore.pendingDeletionIds(scope);
      _checkArchiveScope(scope, revision, cancellation);
      preexistingIntent = pending.contains(id);
      if (preexistingIntent && !remoteDeleted) {
        _uncertainDeletions[key] = scope;
        throw const GenAiFailure(GenAiFailureKind.interrupted);
      }
      if (!remoteDeleted) {
        if (rollback != null) {
          await _writeArchive(scope, rollback, allowDeleting: true);
        }
        _checkArchiveScope(scope, revision, cancellation);
        // The intent is durable before any remote effect; restarting cannot
        // resurrect the local record or silently repeat an ambiguous DELETE.
        intentAttempted = true;
        await _conversationStore.beginDeletion(scope, id);
        _checkArchiveScope(scope, revision, cancellation);
        dispatched = true;
        await _repository.deleteConversation(id, cancellation);
        remoteDeleted = true;
      }
      await _conversationStore.delete(scope, id);
      localDeleted = true;
      _pendingLocalDeletes.remove(key);
      _uncertainDeletions.remove(key);
      _archiveFailures.remove(key);
      _checkArchiveScope(scope, revision, cancellation);
      _notify();
    } catch (error) {
      final definiteRejection = error is GenAiFailure &&
          (error.kind == GenAiFailureKind.authenticationRequired ||
              error.kind == GenAiFailureKind.rejected &&
                  const [400, 401, 403, 404, 422].contains(error.statusCode));
      if (!remoteDeleted && !preexistingIntent && (!dispatched || definiteRejection)) {
        if (intentAttempted) {
          await _conversationStore.rollbackDeletion(scope, id);
        }
        _deletingArchives.remove(key);
        _uncertainDeletions.remove(key);
      } else if (remoteDeleted && !localDeleted) {
        _pendingLocalDeletes[key] = (scope, id);
        _archiveFailures[key] = scope;
      } else if (!remoteDeleted) {
        _uncertainDeletions[key] = scope;
      }
      _notify();
      rethrow;
    }
  }

  /// Explicit recovery checks read server state; they never repeat DELETE.
  Future<void> reconcilePendingDeletions(GenAiCancellation cancellation) async {
    _agentScopeChanged();
    final scope = _archiveScope;
    final revision = sessions.revision;
    if (scope == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    final pending = await _conversationStore.pendingDeletionIds(scope);
    for (final id in pending) {
      _checkArchiveScope(scope, revision, cancellation);
      final rows = await _repository.loadConversation(id, cancellation);
      _checkArchiveScope(scope, revision, cancellation);
      final key = _archiveKey(scope, id);
      if (rows.isEmpty) {
        await _conversationStore.delete(scope, id);
      } else {
        await _conversationStore.rollbackDeletion(scope, id);
        _deletingArchives.remove(key);
      }
      _pendingLocalDeletes.remove(key);
      _uncertainDeletions.remove(key);
      _archiveFailures.remove(key);
    }
    _checkArchiveScope(scope, revision, cancellation);
    _notify();
  }

  Future<GenAiConversationArchive> conversationForExport(
    String id,
    GenAiCancellation cancellation,
  ) async {
    _agentScopeChanged();
    final scope = _archiveScope;
    final revision = sessions.revision;
    if (scope == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    await flushConversations();
    if (_deletingArchives.contains(_archiveKey(scope, id)) ||
        (await _conversationStore.deletedIds(scope)).contains(id)) {
      throw const GenAiFailure(GenAiFailureKind.rejected);
    }
    final local = await _conversationStore.read(scope, id);
    _checkArchiveScope(scope, revision, cancellation);
    final rows = local == null
        ? await _repository.loadConversation(id, cancellation)
        : const <GenAiSavedTurn>[];
    cancellation.throwIfCancelled();
    if (_disposed ||
        scope != _archiveScope ||
        revision != sessions.revision ||
        _deletingArchives.contains(_archiveKey(scope, id))) {
      throw const GenAiFailure(GenAiFailureKind.accountChanged);
    }
    if (local != null) return local;
    final imported = importGenAiLegacyConversation(rows);
    return GenAiConversationArchive(
      id: id,
      title: imported.firstOrNull?.prompt ?? '对话',
      updatedAt: DateTime.now(),
      turns: imported,
      agentEnabled: false,
      netSearchEnabled: false,
      thinkingEnabled: false,
      modelAiType: rows.firstOrNull?.aiType,
      modelRootAiType: null,
      mutations: const {'version': 1, 'effects': <String, Object?>{}},
    );
  }

  Future<void> renameConversation(String id, String name) async {
    _agentScopeChanged();
    final title = name.trim();
    if (title.isEmpty || title.length > 120) {
      throw ArgumentError.value(name, 'name');
    }
    final scope = _archiveScope;
    final revision = sessions.revision;
    if (scope == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    await flushConversations();
    var saved = await _conversationStore.read(scope, id);
    if (saved == null) {
      _checkArchiveScope(scope, revision);
      final rows = await _repository.loadConversation(id, GenAiCancellation());
      saved = GenAiConversationArchive(
        id: id,
        title: title,
        updatedAt: DateTime.now(),
        turns: importGenAiLegacyConversation(rows),
        agentEnabled: false,
        netSearchEnabled: false,
        thinkingEnabled: false,
        modelAiType: rows.firstOrNull?.aiType,
        modelRootAiType: null,
        mutations: const {'version': 1, 'effects': <String, Object?>{}},
      );
    }
    if (_disposed ||
        _archiveScope != scope ||
        sessions.revision != revision ||
        _deletingArchives.contains(_archiveKey(scope, id)) ||
        (await _conversationStore.deletedIds(scope)).contains(id)) {
      throw const GenAiFailure(GenAiFailureKind.accountChanged);
    }
    _checkArchiveScope(scope, revision);
    final current = _groupId == id;
    final previousTitle = _titleOverride;
    if (current) _titleOverride = title;
    final json = {
      ...(current ? _snapshot().toJson() : saved.toJson()),
      'title': title,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _writeArchive(scope, GenAiConversationArchive.fromJson(json));
    } catch (_) {
      if (current && _archiveScope == scope && _groupId == id) {
        _titleOverride = previousTitle;
      }
      rethrow;
    }
    if (!_disposed && _archiveScope == scope && _groupId == id) {
      _titleOverride = title;
      _notify();
    }
  }

  Future<bool> openConversation(
    String id,
    GenAiCancellation cancellation,
  ) async {
    if (_disposed) return false;
    _agentScopeChanged();
    if (_active?.isAgent ?? false) stop();
    if (sending) return false;
    final load = ++_conversationLoad;
    final generation = _generation;
    final scope = _archiveScope;
    final revision = sessions.revision;
    if (scope == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    await flushConversations();
    if (_deletingArchives.contains(_archiveKey(scope, id)) ||
        (await _conversationStore.deletedIds(scope)).contains(id)) {
      return false;
    }
    final archive = await _conversationStore.read(scope, id);
    _checkArchiveScope(scope, revision, cancellation);
    if (load != _conversationLoad || generation != _generation) return false;
    final rows = archive == null
        ? await _repository.loadConversation(id, cancellation)
        : const <GenAiSavedTurn>[];
    cancellation.throwIfCancelled();
    if (_disposed ||
        load != _conversationLoad ||
        generation != _generation ||
        revision != sessions.revision ||
        _archiveScope != scope ||
        _deletingArchives.contains(_archiveKey(scope, id))) {
      return false;
    }
    newConversation();
    _groupId = id;
    _archiveScope = scope;
    _turns.addAll(archive?.restoreTurns() ?? importGenAiLegacyConversation(rows));
    if (_turns.isEmpty) {
      _groupId = createGroupId();
    }
    if (archive != null) {
      _repository.restoreContext(id, archive.contextMemory);
      _titleOverride = archive.title;
      _agentEnabled = archive.agentEnabled;
      _netSearchEnabled = archive.netSearchEnabled;
      _thinkingEnabled = archive.thinkingEnabled;
      _restoredMutations = archive.mutations;
      _ledgerNeedsRestore = true;
    } else {
      // Remote rows carry tool traces, but no saved mode preferences. Never
      // inherit an unrelated conversation's search/thinking or approval state.
      _agentEnabled = _turns.lastOrNull?.isAgent ?? false;
      _netSearchEnabled = false;
      _thinkingEnabled = false;
    }
    final aiType = archive?.modelAiType ?? rows.firstOrNull?.aiType;
    final rootAiType = archive?.modelRootAiType;
    _selectedModel = models
            .where(
              (model) =>
                  model.aiType == aiType && (rootAiType == null || model.rootAiType == rootAiType),
            )
            .firstOrNull ??
        _selectedModel;
    _notify();
    return true;
  }

  void selectModel(GenAiModel model) {
    if (sending || !models.contains(model)) return;
    _selectedModel = model;
    _notify();
  }

  Future<void> send(String prompt) async {
    _agentScopeChanged();
    final model = _selectedModel;
    final generation = _generation;
    final revision = sessions.revision;
    if (_disposed || sending || !connected || model == null) {
      return;
    }
    if (_attachments.any((a) => a.uploading) || _pendingUploads.isNotEmpty) {
      await waitForPendingUploads();
    }
    if (_disposed ||
        sending ||
        !connected ||
        generation != _generation ||
        revision != sessions.revision) {
      return;
    }
    if (hasFailedUploads) {
      return;
    }
    if (prompt.trim().isEmpty && _attachments.isEmpty) {
      return;
    }
    final fileIds = _attachments.where((a) => a.fileId != null).map((a) => a.fileId!).toList();
    final imageAttachments = _attachments.where((a) => a.isImage).toList();
    final imageUrl = imageAttachments.where((a) => a.imageUrl != null).firstOrNull?.imageUrl;
    final imageUrls = imageAttachments.map((a) => a.imageUrl).whereType<String>().toList();
    final attachedFileNames = _attachments.where((a) => !a.isImage).map((a) => a.name).toList();
    final attachedImageBytes = imageAttachments.where((a) => a.bytes.isNotEmpty).firstOrNull != null
        ? Uint8List.fromList(
            imageAttachments.firstWhere((a) => a.bytes.isNotEmpty).bytes,
          )
        : null;
    final attachedImageBytesList = [
      for (final a in imageAttachments)
        if (a.bytes.isNotEmpty) Uint8List.fromList(a.bytes),
    ];
    final turn = GenAiConversationTurn(prompt.trim(), isAgent: _agentEnabled)
      ..thinkingStartTime = DateTime.now()
      ..isSearching = _netSearchEnabled
      ..attachedFileNames = attachedFileNames
      ..attachedFileIds = fileIds
      ..attachedFileContents = {
        for (final a in _attachments)
          if (a.fileId != null && a.documentContent != null) a.fileId!: a.documentContent!,
      }
      ..attachedImageUrl = imageUrl
      ..attachedImageUrls = imageUrls
      ..attachedImageBytes = attachedImageBytes
      ..attachedImageBytesList = attachedImageBytesList;
    _attachments.clear();
    if (turn.isAgent) {
      turn.isSearching = false;
      await _executeAgentTurn(turn, model);
    } else {
      await _executeSendTurn(turn, model);
    }
  }

  Future<void> retryTurn(int index) async {
    // A stale retry must not truncate later exchanges or cancel their work.
    // Editing an earlier turn needs an explicit branch, which this UI lacks.
    if (index < 0 || index != _turns.length - 1 || _turns[index].isHistoryGap) {
      return;
    }
    _agentScopeChanged();
    if (_active?.isAgent ?? false) stop();
    final model = _selectedModel;
    if (_disposed || sending || !connected || model == null) return;
    if (index < 0 || index >= _turns.length) return;

    final target = _turns[index];
    if (target.isAgent && (!agentAvailable || _attachments.isNotEmpty || hasPendingUploads)) {
      return;
    }
    final prompt = target.prompt;
    final fileNames = target.attachedFileNames;
    final fileIds = target.attachedFileIds;
    final fileContents = target.attachedFileContents;
    final imageUrl = target.attachedImageUrl;
    final imageUrls = target.attachedImageUrls;
    final imageBytes = target.attachedImageBytes;
    final imageBytesList = target.attachedImageBytesList;

    _turns.removeLast();

    final turn = GenAiConversationTurn(prompt, isAgent: target.isAgent)
      ..thinkingStartTime = DateTime.now()
      ..isSearching = _netSearchEnabled
      ..attachedFileNames = fileNames
      ..attachedFileIds = fileIds
      ..attachedFileContents = fileContents
      ..attachedImageUrl = imageUrl
      ..attachedImageUrls = imageUrls
      ..attachedImageBytes = imageBytes
      ..attachedImageBytesList = imageBytesList;

    if (turn.isAgent) {
      turn.isSearching = false;
      await _executeAgentTurn(turn, model);
    } else {
      await _executeSendTurn(turn, model);
    }
  }

  List<GenAiAgentHistoryEntry> _agentConversationTranscript() {
    var history = <GenAiAgentHistoryEntry>[];
    for (final turn in _turns) {
      if (turn.isHistoryGap) {
        history.clear();
        continue;
      }
      if (turn.isAgent && turn.agentTranscript.isNotEmpty) {
        if (turn.agentTranscriptIsDelta) {
          history.addAll(turn.agentTranscript);
        } else {
          history = List.of(turn.agentTranscript);
        }
      } else if (turn.phase == GenAiChatPhase.completed ||
          (turn.isAgent && turn.agentEvents.isNotEmpty)) {
        history.addAll(turn.evidenceEntries);
      }
    }
    return history;
  }

  void _captureAgentTranscript(
    GenAiConversationTurn turn,
    GenAiAgentRunner runner,
    String groupId,
    int transcriptStart,
  ) {
    turn.agentTranscript =
        runner.transcriptForConversation(groupId).skip(transcriptStart).toList(growable: false);
    turn.agentTranscriptIsDelta = true;
    // Checkpoints precede the next yielded UI event. Reconcile already-known
    // calls from the typed receipt so a crash cannot lose its successful image
    // URL or turn an already-dispatched operation back into an approval.
    for (final entry in turn.agentTranscript) {
      final result = entry.result;
      if (result == null) continue;
      final existing = turn.agentEvents.entries
          .where(
            (event) =>
                event.value.call?.id == result['call_id'] &&
                event.value.call?.name == result['name'],
          )
          .lastOrNull;
      if (existing == null) continue;
      final reconciled = GenAiAgentEvent(
        kind: GenAiAgentEventKind.toolFinished,
        turn: existing.value.turn,
        call: existing.value.call,
        prepared: existing.value.prepared,
        result: result,
      );
      turn.agentEvents[existing.key] = reconciled;
      if (turn.agentActivity.isNotEmpty) turn.recordAgentActivity(reconciled);
    }
  }

  Future<void> _executeAgentTurn(
    GenAiConversationTurn turn,
    GenAiModel model,
  ) async {
    final thinking = _thinkingEnabled && model.supportsThinking;
    final netSearch = _netSearchEnabled;
    final runner = _agentRunner;
    if (runner == null) return;
    final groupId = _groupId;
    final generation = ++_generation;
    final revision = sessions.revision;
    final scope = _agentScopeValue;
    final operation = GenAiCancellation();
    final previousRun = _agentDrain;
    final drained = Completer<void>();
    _agentDrain = drained.future;
    _agentOperation = operation;
    _turns.add(turn);
    _active = turn;
    turn.agentStatus = '正在处理';
    _notify();
    bool owned() =>
        !_disposed &&
        generation == _generation &&
        revision == sessions.revision &&
        _agentScope?.call() == scope &&
        identical(_active, turn) &&
        identical(_agentOperation, operation);
    bool current() => owned() && !operation.isCancelled;
    var transcriptStart = 0;
    try {
      // Stop permits another send immediately; wait for the cancelled runner's
      // finally block before using its session-scoped mutation ledger again.
      if (previousRun != null) await previousRun;
      if (!current()) return;
      if (_ledgerNeedsRestore) {
        runner.restoreConversation(groupId, _restoredMutations);
        _ledgerNeedsRestore = false;
      }
      final transcript = _agentConversationTranscript();
      transcriptStart = transcript.length;
      final attachments = _conversationAttachments(_turns);
      if (!current()) return;
      await for (final event in runner.run(
        request: GenAiChatRequest(
          chatGroupId: groupId,
          prompt: turn.prompt,
          aiType: model.aiType,
          rootAiType: model.rootAiType,
          history: const [],
          thinking: thinking,
          netGo: false,
          fileIds: attachments.fileIds,
          documentContents: attachments.documentContents,
          imageUrls: attachments.imageUrls,
          imageUrl: attachments.imageUrls.firstOrNull,
          maxTokens: 2048,
        ),
        cancellation: operation,
        isCurrent: current,
        transcript: transcript,
        additionalTools: [
          if (netSearch)
            genAiAgentWebSearch(
              repository: _repository,
              groupId: groupId,
              aiType: model.aiType,
              rootAiType: model.rootAiType,
            ),
        ],
        checkpoint: (mutations) async {
          if (!current()) throw const GenAiFailure(GenAiFailureKind.cancelled);
          final archiveScope = _archiveScope;
          if (archiveScope == null) {
            throw const GenAiFailure(GenAiFailureKind.accountChanged);
          }
          _captureAgentTranscript(turn, runner, groupId, transcriptStart);
          await _writeArchive(archiveScope, _snapshot(mutations: mutations));
          if (!current()) throw const GenAiFailure(GenAiFailureKind.cancelled);
        },
        approve: (tool, call, prepared) {
          if (!current()) return Future.value(false);
          final pending = GenAiPendingAgentApproval(call, prepared);
          _pendingAgentApproval = pending;
          _notify();
          return pending._result.future;
        },
      )) {
        if (!owned()) {
          // A stopped turn can finish unwinding after the next send starts.
          // Retain its tool outcome for follow-ups, but never revive a removed
          // conversation or copy data across account/session boundaries.
          if (!_disposed &&
              _turns.contains(turn) &&
              _groupId == groupId &&
              revision == sessions.revision &&
              _agentScope?.call() == scope &&
              (event.kind == GenAiAgentEventKind.cancelled ||
                  event.kind == GenAiAgentEventKind.failed)) {
            _captureAgentTranscript(turn, runner, groupId, transcriptStart);
            _scheduleArchive();
          }
          break;
        }
        if (operation.isCancelled &&
            event.kind != GenAiAgentEventKind.failed &&
            event.kind != GenAiAgentEventKind.cancelled) {
          break;
        }
        turn.recordAgentActivity(event);
        if (event.call != null) turn.agentEvents[event.call!.id] = event;
        if (event.call?.name == 'web_search') {
          turn.isSearching = event.kind == GenAiAgentEventKind.toolStarted;
          if (event.kind == GenAiAgentEventKind.toolFinished) {
            final result = event.result?['result'];
            if (result is Map && result['citations'] is List) {
              turn.citations = [
                ...turn.citations,
                for (final raw in result['citations'] as List)
                  if (raw is Map)
                    GenAiWebSearchCitation.fromJson(
                      Map<String, dynamic>.from(raw),
                    ),
              ];
            }
          }
        }
        if (event.kind != GenAiAgentEventKind.reasoningDelta &&
            event.kind != GenAiAgentEventKind.contextUsage) {
          _captureAgentTranscript(turn, runner, groupId, transcriptStart);
        }
        switch (event.kind) {
          case GenAiAgentEventKind.contextUsage:
            turn.contextUsage = event.contextUsage;
          case GenAiAgentEventKind.contextCompacted:
            turn.contextCompacted = true;
          case GenAiAgentEventKind.modelStarted:
            turn.contextUsage = null;
            turn.phase = GenAiChatPhase.streaming;
            turn.agentStatus = '正在处理 · 第 ${event.turn} 步';
            turn.isAgentThinking = thinking;
            if (turn.reasoning.isNotEmpty) turn.reasoning += '\n\n';
          case GenAiAgentEventKind.reasoningDelta:
            turn.isAgentThinking = true;
            turn.reasoning += event.text ?? '';
          case GenAiAgentEventKind.toolProposed:
            turn.isAgentThinking = false;
            turn.agentStatus = '准备使用工具';
          case GenAiAgentEventKind.approvalRequired:
            turn.agentStatus = '等待你的确认';
          case GenAiAgentEventKind.toolStarted:
            turn.agentStatus = '正在使用工具';
          case GenAiAgentEventKind.toolFinished:
            turn.agentStatus = '已收到工具结果，继续处理';
          case GenAiAgentEventKind.protocolError:
            turn.isAgentThinking = false;
            turn.agentStatus = '正在修正工具参数';
          case GenAiAgentEventKind.completed:
            turn.isAgentThinking = false;
            turn.answer = event.text ?? '';
            turn.agentStatus = '';
            turn.phase = GenAiChatPhase.completed;
          case GenAiAgentEventKind.failed:
          case GenAiAgentEventKind.cancelled:
            turn.contextUsage = null;
            turn.failure = event.failure;
            turn.agentStatus = event.text ?? '任务未完成，请检查工具记录后再继续。已提交的操作不要重复执行。';
            turn.phase = event.kind == GenAiAgentEventKind.cancelled
                ? GenAiChatPhase.cancelled
                : GenAiChatPhase.failed;
        }
        _notify();
      }
    } catch (error) {
      if (current()) {
        turn.contextUsage = null;
        turn.failure =
            error is GenAiFailure ? error : const GenAiFailure(GenAiFailureKind.protocol);
        turn.phase = GenAiChatPhase.failed;
        turn.agentStatus =
            turn.isSearching ? '联网搜索失败，请重试或关闭联网搜索后继续。' : '无法继续任务，请检查工具记录。已提交的操作不要重复执行。';
      }
    } finally {
      turn.isSearching = false;
      turn.isAgentThinking = false;
      operation.cancel();
      if (identical(_agentOperation, operation)) {
        resolveAgentApproval(false);
        _agentOperation = null;
      }
      if (generation == _generation && identical(_active, turn)) _active = null;
      drained.complete();
      if (identical(_agentDrain, drained.future)) _agentDrain = null;
      _notify();
      _flushPendingArchives();
      await _archiveWrites;
    }
  }

  /// Both chat modes carry the same attachment context. A missing-history row
  /// breaks that context; we must not associate earlier files with later tasks.
  ({
    List<String> fileIds,
    Map<String, String> documentContents,
    List<String> imageUrls,
  }) _conversationAttachments(Iterable<GenAiConversationTurn> turns) {
    final fileIds = <String>{};
    final documentContents = <String, String>{};
    final imageUrls = <String>{};
    for (final turn in turns) {
      if (turn.isHistoryGap) {
        fileIds.clear();
        documentContents.clear();
        imageUrls.clear();
      } else {
        fileIds.addAll(turn.attachedFileIds);
        documentContents.addAll(turn.attachedFileContents);
        imageUrls.addAll(turn.attachedImageUrls);
        if (turn.attachedImageUrl case final image? when image.isNotEmpty) {
          imageUrls.add(image);
        }
      }
    }
    return (
      fileIds: fileIds.toList(),
      documentContents: documentContents,
      imageUrls: imageUrls.toList(),
    );
  }

  Future<void> _executeSendTurn(
    GenAiConversationTurn turn,
    GenAiModel model,
  ) async {
    final history = <GenAiMessage>[];
    final attachments = _conversationAttachments([..._turns, turn]);
    for (final previous in _turns) {
      if (previous.isHistoryGap) {
        history.clear();
      } else if (previous.phase == GenAiChatPhase.completed ||
          (previous.isAgent && previous.agentEvents.isNotEmpty)) {
        history.addAll(previous.evidenceEntries.map((entry) => entry.message));
      }
    }
    final generation = ++_generation;
    final revision = sessions.revision;
    final groupId = _groupId;
    final thinking = _thinkingEnabled;
    final netSearch = _netSearchEnabled;
    final operation = GenAiCancellation();
    _sendOperation = operation;
    _turns.add(turn);
    _active = turn;
    _notify();

    try {
      if (netSearch) {
        try {
          final citations = await _repository.searchWeb(
            GenAiChatRequest(
              chatGroupId: groupId,
              prompt: turn.prompt,
              aiType: model.aiType,
              rootAiType: model.rootAiType,
              history: history,
              netGo: true,
            ),
            operation,
          );
          turn.citations = citations;
        } catch (_) {}
        turn.isSearching = false;
        _notify();
      }

      // Search cancellation/account changes must never start a fresh chat POST.
      if (_disposed ||
          operation.isCancelled ||
          generation != _generation ||
          revision != sessions.revision ||
          !identical(_active, turn)) {
        return;
      }
      await _chat.send(
        GenAiChatRequest(
          chatGroupId: groupId,
          prompt: turn.prompt,
          aiType: model.aiType,
          rootAiType: model.rootAiType,
          history: [
            GenAiMessage(
              role: GenAiRole.system,
              content: genAiSystemPrompt(
                campusTools: false,
                thinking: thinking,
                webSearch: netSearch,
                documents: attachments.fileIds.isNotEmpty,
                images: attachments.imageUrls.isNotEmpty,
              ),
            ),
            ...history,
          ],
          thinking: thinking,
          netGo: netSearch,
          fileIds: attachments.fileIds,
          documentContents: attachments.documentContents,
          imageUrl: attachments.imageUrls.firstOrNull,
          imageUrls: attachments.imageUrls,
        ),
      );
    } finally {
      operation.cancel();
      if (identical(_sendOperation, operation)) _sendOperation = null;
      if (generation == _generation && identical(_active, turn)) _active = null;
      _notify();
      _flushPendingArchives();
      await _archiveWrites;
    }
  }

  void _chatChanged() {
    final turn = _active;
    if (_disposed || turn == null || turn.isAgent) return;
    turn.contextCompacted = _chat.contextCompacted;
    turn.contextUsage = _chat.contextUsage;
    turn.answer = _chat.answer;
    turn.reasoning = _chat.reasoning;
    turn.phase = _chat.phase;
    turn.failure = _chat.failure;
    turn.finishReason = _chat.finishReason;
    if (turn.thinkingStartTime != null &&
        turn.thinkingDurationMs == null &&
        (_chat.answer.isNotEmpty || _chat.phase == GenAiChatPhase.completed)) {
      turn.thinkingDurationMs = DateTime.now().difference(turn.thinkingStartTime!).inMilliseconds;
    }
    _notify();
  }

  void stop() {
    _agentOperation?.cancel();
    _agentOperation = null;
    resolveAgentApproval(false);
    _sendOperation?.cancel();
    _sendOperation = null;
    _chat.stop();
    if (_active case final turn?) {
      turn.contextUsage = null;
      turn.isSearching = false;
      turn.isAgentThinking = false;
      turn.phase = GenAiChatPhase.cancelled;
      if (turn.isAgent) {
        turn.agentStatus = '已停止。已提交的预约或图片任务仍可能完成，请先查看记录。';
      }
    }
    _active = null;
    _generation++;
    _notify();
  }

  void newConversation() {
    _conversationRevision++;
    stop();
    _flushPendingArchives();
    _chat.clear();
    _turns.clear();
    _cancelAttachments();
    _groupId = createGroupId();
    _archiveScope = _currentArchiveScope();
    _titleOverride = null;
    _ledgerNeedsRestore = false;
    _restoredMutations = const {'version': 1, 'effects': <String, Object?>{}};
    _notify();
  }

  Future<void> disconnect() async {
    newConversation();
    try {
      await sessions.disconnect();
    } on GenAiFailure catch (error) {
      _loginFailure = error;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      imageStudio.updateScope((_archiveScope, sessions.revision));
      _scheduleArchive();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cancelAttachments();
    stop();
    _flushPendingArchives();
    _disposed = true;
    imageStudio.dispose();
    _agentOperation?.cancel();
    resolveAgentApproval(false);
    _agentScopeChanges?.removeListener(_agentScopeChanged);
    _agentRunner?.clear();
    _catalogOperation?.cancel();
    _sendOperation?.cancel();
    sessions.removeListener(_sessionChanged);
    _chat.removeListener(_chatChanged);
    if (sending) _chat.stop();
    super.dispose();
  }
}
