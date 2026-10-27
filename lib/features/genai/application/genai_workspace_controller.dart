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
import 'genai_chat_service.dart';
import 'genai_conversation_archive.dart';
import 'genai_conversation_turn.dart';
import 'genai_image_studio_controller.dart';
import 'genai_remote_history.dart';
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

/// Transient UI and execution state reconstructed from GenAI server records.
final class GenAiWorkspaceController extends ChangeNotifier {
  GenAiWorkspaceController({
    required this.sessions,
    required GenAiRepository repository,
    required GenAiChatService chat,
  })  : _repository = repository,
        _chat = chat {
    _owner = sessions.owner;
    _draftTitles.clear();
    _uncertainDeletions.clear();
    _agentSessionRevision = sessions.revision;
    _archiveScope = _currentArchiveScope();
    sessions.addListener(_sessionChanged);
    _chat.addListener(_chatChanged);
    _sessionChanged();
  }

  final GenAiSessionService sessions;
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
  final _draftTitles = <String, String>{};
  final _interruptedTurns = <String, Map<String, Object?>>{};
  final _uncertainDeletions = <String, String>{};
  GenAiCancellation? _refreshOperation;
  GenAiFailure? _recoveryFailure;
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
  Object? get accountScope => (_archiveScope, _agentScopeValue);
  Object get _archiveRevision => (sessions.revision, _agentScopeValue);
  GenAiModel? get selectedModel => _selectedModel;
  GenAiFailure? get loginFailure => _loginFailure;
  GenAiFailure? get catalogFailure => _catalogFailure;
  GenAiFailure? get archiveFailure => _recoveryFailure;
  int get uncertainDeletionCount =>
      _uncertainDeletions.values.where((scope) => scope == _archiveScope).length;
  bool get connecting => _connecting;
  bool get loadingModels => _loadingModels;
  bool get sending => _active != null || _refreshOperation != null;
  bool get connected => sessions.session != null;
  bool get thinkingEnabled => _thinkingEnabled && (_selectedModel?.supportsThinking ?? false);
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
    _agentRunner = runner;
    _agentScope = scope;
    _agentScopeValue = nextScope;
    _archiveScope = _currentArchiveScope();
    _agentScopeChanges = scopeChanges;
    _agentSessionRevision = sessions.revision;
    scopeChanges?.addListener(_agentScopeChanged);
  }

  void _agentScopeChanged() {
    if (_disposed || _agentRunner == null) return;
    final scope = _agentScope?.call();
    if (scope == _agentScopeValue) return;
    _agentScopeValue = scope;
    newConversation();
    _agentRunner?.clear();
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
      _draftTitles.clear();
      _uncertainDeletions.clear();
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
      sessions.owner == null ? null : jsonEncode([sessions.owner!.storageId, null]);

  void _checkArchiveScope(String scope, Object revision, [GenAiCancellation? cancellation]) {
    cancellation?.throwIfCancelled();
    if (_disposed ||
        _archiveScope != scope ||
        _archiveRevision != revision ||
        _agentScope?.call() != _agentScopeValue) {
      throw const GenAiFailure(GenAiFailureKind.accountChanged);
    }
  }

  Future<GenAiRemoteHistory> _readConversation(String id, GenAiCancellation cancellation) async {
    final scope = _archiveScope;
    final revision = _archiveRevision;
    if (scope == null) throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    final rows = await _repository.loadConversation(id, cancellation);
    _checkArchiveScope(scope, revision, cancellation);
    return decodeGenAiConversation(id, rows);
  }

  Future<GenAiPageResult<GenAiConversationSummary>> listConversations(
    GenAiCancellation cancellation, {
    int page = 1,
    String query = '',
  }) async {
    final scope = _archiveScope;
    final revision = _archiveRevision;
    if (scope == null) throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    final remote = await _repository.listConversations(cancellation, page: page, query: query);
    _checkArchiveScope(scope, revision, cancellation);
    // The server title/time may describe a tool continuation or housekeeping
    // exchange. Derive both from logical user turns, not last-open timestamps.
    final summaries = <GenAiConversationSummary>[];
    for (final item in remote.records) {
      final history = await _readConversation(item.id, cancellation);
      final summary = history.archive.summary;
      summaries.add(
        GenAiConversationSummary(
          id: item.id,
          title: _draftTitles[item.id] ??
              (history.archive.restoreTurns().isEmpty ? item.title : summary.title),
          time: history.archive.restoreTurns().isEmpty ? item.time : summary.time,
        ),
      );
    }
    return GenAiPageResult(
      summaries..sort(GenAiConversationSummary.newestFirst),
      page: page,
      hasMore: remote.hasMore,
    );
  }

  Future<void> deleteConversation(String id, GenAiCancellation cancellation) async {
    final scope = _archiveScope;
    final revision = _archiveRevision;
    if (scope == null) throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    if (_uncertainDeletions.containsKey(id)) {
      throw const GenAiFailure(GenAiFailureKind.interrupted);
    }
    if (_groupId == id) stop();
    _uncertainDeletions[id] = scope;
    try {
      await _repository.deleteConversation(id, cancellation);
      _checkArchiveScope(scope, revision, cancellation);
      _uncertainDeletions.remove(id);
      _draftTitles.remove(id);
      if (_groupId == id) newConversation();
    } finally {
      _notify();
    }
  }

  /// Reconciliation reads only. An ambiguous DELETE is never repeated.
  Future<void> reconcilePendingDeletions(GenAiCancellation cancellation) async {
    for (final entry in _uncertainDeletions.entries.toList()) {
      if (entry.value != _archiveScope) continue;
      final remote = await _readConversation(entry.key, cancellation);
      if (remote.archive.restoreTurns().isEmpty && _groupId == entry.key) newConversation();
      _uncertainDeletions.remove(entry.key);
    }
    _notify();
  }

  Future<GenAiConversationArchive> conversationForExport(
    String id,
    GenAiCancellation cancellation,
  ) async =>
      (await _readConversation(id, cancellation)).archive;

  /// Rename is draft metadata until the next normal exchange. No hidden model
  /// generation is made merely to persist a label.
  Future<void> renameConversation(String id, String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 120) throw ArgumentError.value(name, 'name');
    _draftTitles[id] = value;
    if (_groupId == id) _titleOverride = value;
    _notify();
  }

  void _applyRemote(GenAiConversationArchive archive, {bool restoreModes = true}) {
    _turns
      ..clear()
      ..addAll(archive.restoreTurns());
    _titleOverride = _draftTitles[archive.id] ?? archive.title;
    _repository.restoreContext(archive.id, archive.contextMemory);
    _restoredMutations = archive.mutations;
    _ledgerNeedsRestore = true;
    if (restoreModes) {
      _agentEnabled = archive.agentEnabled;
      _thinkingEnabled = archive.thinkingEnabled;
      _selectedModel = models
              .where(
                (m) =>
                    m.aiType == archive.modelAiType &&
                    (archive.modelRootAiType == null || m.rootAiType == archive.modelRootAiType),
              )
              .firstOrNull ??
          _selectedModel;
    }
  }

  Future<bool> openConversation(String id, GenAiCancellation cancellation) async {
    if (_disposed || sending) return false;
    final load = ++_conversationLoad;
    final generation = _generation;
    final remote = await _readConversation(id, cancellation);
    if (_disposed || load != _conversationLoad || generation != _generation || sending) {
      return false;
    }
    newConversation();
    _groupId = id;
    _applyRemote(remote.archive);
    _notify();
    return true;
  }

  /// Refresh the authoritative path before continuing, without discarding an
  /// unsaved exchange after a dropped connection. The user can explicitly open
  /// server history or start a new chat in that case.
  Future<bool> _refreshBeforeSend() async {
    if (_turns.isEmpty) return true;
    final operation = GenAiCancellation();
    final generation = _generation;
    _refreshOperation = operation;
    _notify();
    try {
      final remote = await _readConversation(_groupId, operation);
      if (generation != _generation || operation.isCancelled) return false;
      final recovered = remote.archive.restoreTurns();
      final missing = _turns.where((t) => !recovered.any((r) => r.id == t.id)).toList();
      if (missing.any((t) => t.phase == GenAiChatPhase.completed)) {
        _recoveryFailure = const GenAiFailure(GenAiFailureKind.interrupted);
        return false;
      }
      // Explicitly stopped/failed exchanges are inert records, carried once by
      // the next real request. No metadata-only model call is needed.
      final interrupted = _turns
          .where(
            (t) =>
                t.phase == GenAiChatPhase.cancelled ||
                t.phase == GenAiChatPhase.interrupted ||
                t.phase == GenAiChatPhase.failed,
          )
          .toList();
      for (final turn in interrupted) {
        _interruptedTurns[turn.id] = turn.toInterruptedRecord();
      }
      _interruptedTurns.removeWhere(
        (id, _) => recovered.any(
          (r) => r.id == id && r.phase == GenAiChatPhase.cancelled,
        ),
      );
      _applyRemote(remote.archive, restoreModes: false);
      for (final turn in interrupted) {
        final index = _turns.indexWhere((t) => t.id == turn.id);
        if (index >= 0) {
          _turns[index] = turn;
        } else {
          _turns.add(turn);
        }
      }
      _recoveryFailure = null;
      return true;
    } on GenAiFailure catch (error) {
      if (!operation.isCancelled) _recoveryFailure = error;
      return false;
    } finally {
      if (identical(_refreshOperation, operation)) _refreshOperation = null;
      operation.cancel();
      _notify();
    }
  }

  Future<void> retrySaveConversations() async {
    // This action reconciles existing server data; it never resends a POST.
    if (!sending) await _refreshBeforeSend();
  }

  Map<String, Object?> _recordFor(GenAiConversationTurn turn, GenAiModel model) => {
        'step_id': createGroupId(),
        'turn': turn.toRemoteInput(),
        if (_interruptedTurns.isNotEmpty) 'interrupted': _interruptedTurns.values.toList(),
        'agent': turn.isAgent,
        'thinking': thinkingEnabled,
        'search': false,
        'aiType': model.aiType,
        'rootAiType': model.rootAiType,
        if (_titleOverride != null) 'title': _titleOverride,
      };

  void selectModel(GenAiModel model) {
    if (sending || !models.contains(model)) return;
    _selectedModel = model;
    _notify();
  }

  Future<void> send(String prompt) async {
    _agentScopeChanged();
    final model = _selectedModel;
    final generation = _generation;
    final revision = _archiveRevision;
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
        revision != _archiveRevision) {
      return;
    }
    if (_turns.isNotEmpty && !await _refreshBeforeSend()) return;
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
    final turn = GenAiConversationTurn(
      prompt.trim(),
      id: createGroupId(),
      parentId: _turns.lastOrNull?.id,
      isAgent: _agentEnabled,
    )
      ..thinkingStartTime = DateTime.now()
      ..isSearching = false
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

    if (_turns.isNotEmpty && !await _refreshBeforeSend()) return;
    if (index != _turns.length - 1) return;
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

    final turn = GenAiConversationTurn(
      prompt,
      id: createGroupId(),
      parentId: target.parentId,
      actionScopeId: target.actionScopeId ?? target.id,
      isAgent: target.isAgent,
    )
      ..approvalBudget.addAll(target.approvalBudget)
      ..thinkingStartTime = DateTime.now()
      ..isSearching = false
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
    final history = <GenAiAgentHistoryEntry>[];
    for (final turn in _turns) {
      if (turn.isHistoryGap) {
        history.clear();
      } else if (turn.phase == GenAiChatPhase.completed || turn.agentEvents.isNotEmpty) {
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
        for (final savedTurn in _turns) {
          runner.recoverCalls(
            groupId,
            savedTurn.agentEvents.values,
            turnId: savedTurn.actionScopeId ?? savedTurn.id,
          );
        }
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
          record: _recordFor(turn, model),
          aiType: model.aiType,
          rootAiType: model.rootAiType,
          history: const [],
          thinking: thinking,
          fileIds: attachments.fileIds,
          documentContents: attachments.documentContents,
          imageUrls: attachments.imageUrls,
          imageUrl: attachments.imageUrls.lastOrNull,
          maxTokens: 2048,
        ),
        cancellation: operation,
        isCurrent: current,
        transcript: transcript,
        approvalBudget: turn.approvalBudget,
        checkpoint: (mutations) async {
          if (!current()) throw const GenAiFailure(GenAiFailureKind.cancelled);
          _captureAgentTranscript(turn, runner, groupId, transcriptStart);
          final step = _repository.lastStepFor(groupId);
          if (step == null) throw const GenAiFailure(GenAiFailureKind.storage);
          await _repository.confirmStep(groupId, step, operation);
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
        if (event.kind != GenAiAgentEventKind.reasoningDelta &&
            event.kind != GenAiAgentEventKind.answerDelta &&
            event.kind != GenAiAgentEventKind.contextUsage) {
          _captureAgentTranscript(turn, runner, groupId, transcriptStart);
        }
        switch (event.kind) {
          case GenAiAgentEventKind.contextUsage:
            turn.contextUsage = event.contextUsage;
          case GenAiAgentEventKind.contextCompacted:
            turn.contextCompacted = true;
          case GenAiAgentEventKind.modelStarted:
            turn.answer = '';
            turn.contextUsage = null;
            turn.phase = GenAiChatPhase.streaming;
            turn.agentStatus = '正在处理 · 第 ${event.turn} 步';
            turn.isAgentThinking = thinking;
            if (turn.reasoning.isNotEmpty) turn.reasoning += '\n\n';
          case GenAiAgentEventKind.answerDelta:
            turn.isAgentThinking = false;
            turn.answer += event.text ?? '';
            turn.agentStatus = '';
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
            turn.answer = '';
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
        turn.agentStatus = '无法继续任务，请检查工具记录。已提交的操作不要重复执行。';
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
        for (final image in [
          if (turn.attachedImageUrl case final image? when image.isNotEmpty) image,
          ...turn.attachedImageUrls,
          for (final event in turn.agentEvents.values) ...genAiGeneratedImages(event.result),
        ]) {
          imageUrls.remove(image);
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
    final thinking = thinkingEnabled;
    final operation = GenAiCancellation();
    _sendOperation = operation;
    _turns.add(turn);
    _active = turn;
    _notify();

    try {
      // Cancellation/account changes must never start a fresh chat POST.
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
          record: _recordFor(turn, model),
          aiType: model.aiType,
          rootAiType: model.rootAiType,
          history: [
            GenAiMessage(
              role: GenAiRole.system,
              content: genAiSystemPrompt(
                campusTools: false,
                thinking: thinking,
                documents: attachments.fileIds.isNotEmpty,
                images: attachments.imageUrls.isNotEmpty,
              ),
            ),
            ...history,
          ],
          thinking: thinking,
          fileIds: attachments.fileIds,
          documentContents: attachments.documentContents,
          imageUrl: attachments.imageUrls.lastOrNull,
          imageUrls: attachments.imageUrls,
        ),
      );
    } finally {
      operation.cancel();
      if (identical(_sendOperation, operation)) _sendOperation = null;
      if (generation == _generation && identical(_active, turn)) _active = null;
      _notify();
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
    _refreshOperation?.cancel();
    _refreshOperation = null;
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
    _chat.clear();
    _turns.clear();
    _interruptedTurns.clear();
    _cancelAttachments();
    _groupId = createGroupId();
    _archiveScope = _currentArchiveScope();
    _titleOverride = null;
    _recoveryFailure = null;
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
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cancelAttachments();
    stop();
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
