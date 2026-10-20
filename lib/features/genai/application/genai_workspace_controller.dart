import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'genai_chat_service.dart';
import 'genai_repository.dart';
import 'genai_session_service.dart';

final class GenAiConversationTurn {
  GenAiConversationTurn(this.prompt);

  final String prompt;
  String answer = '';
  String reasoning = '';
  int? thinkingDurationMs;
  DateTime? thinkingStartTime;
  bool isSearching = false;
  List<GenAiWebSearchCitation> citations = const [];
  List<String> attachedFileNames = const [];
  String? attachedImageUrl;
  List<String> attachedImageUrls = const [];
  Uint8List? attachedImageBytes;
  List<Uint8List> attachedImageBytesList = const [];
  GenAiChatPhase phase = GenAiChatPhase.preparing;
  GenAiFailure? failure;
  GenAiFinishReason? finishReason;
}

final class GenAiAttachment {
  const GenAiAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    this.fileId,
    this.isImage = false,
    this.imageUrl,
    this.uploading = false,
    this.error,
  });

  final String id;
  final String name;
  final List<int> bytes;
  final String? fileId;
  final bool isImage;
  final String? imageUrl;
  final bool uploading;
  final String? error;

  GenAiAttachment copyWith({
    String? fileId,
    String? imageUrl,
    bool? uploading,
    String? error,
  }) =>
      GenAiAttachment(
        id: id,
        name: name,
        bytes: bytes,
        fileId: fileId ?? this.fileId,
        isImage: isImage,
        imageUrl: imageUrl ?? this.imageUrl,
        uploading: uploading ?? this.uploading,
        error: error ?? this.error,
      );
}

/// Owns the current in-memory conversation. The app runtime retains it across
/// page navigation; server history is a separate feature.
final class GenAiWorkspaceController extends ChangeNotifier {
  GenAiWorkspaceController({
    required this.sessions,
    required GenAiRepository repository,
    required GenAiChatService chat,
  })  : _repository = repository,
        _chat = chat {
    _owner = sessions.owner;
    sessions.addListener(_sessionChanged);
    _chat.addListener(_chatChanged);
    _sessionChanged();
  }

  final GenAiSessionService sessions;
  final GenAiRepository _repository;
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
  int _generation = 0;
  String _groupId = createGroupId();

  List<GenAiConversationTurn> get turns => List.unmodifiable(_turns);
  List<GenAiModel> get models =>
      List.unmodifiable(_models.where((m) => !m.isImage));
  List<GenAiModel> get imageModels =>
      List.unmodifiable(_models.where((m) => m.isImage));
  GenAiRepository get repository => _repository;
  GenAiModel? get selectedModel => _selectedModel;
  GenAiFailure? get loginFailure => _loginFailure;
  GenAiFailure? get catalogFailure => _catalogFailure;
  bool get connecting => _connecting;
  bool get loadingModels => _loadingModels;
  bool get sending => _active != null;
  bool get connected => sessions.session != null;
  bool get thinkingEnabled => _thinkingEnabled;
  bool get netSearchEnabled => _netSearchEnabled;
  bool get recognizingAudio => _recognizingAudio;
  List<GenAiAttachment> get attachments => List.unmodifiable(_attachments);
  bool get hasPendingUploads =>
      _attachments.any((a) => a.uploading) || _pendingUploads.isNotEmpty;
  String get groupId => _groupId;
  String get title => _turns.isEmpty ? '新的对话' : _turns.first.prompt;

  void toggleThinking() {
    _thinkingEnabled = !_thinkingEnabled;
    _notify();
  }

  void setThinking(bool value) {
    if (_thinkingEnabled == value) return;
    _thinkingEnabled = value;
    _notify();
  }

  void toggleNetSearch() {
    _netSearchEnabled = !_netSearchEnabled;
    _notify();
  }

  void setNetSearch(bool value) {
    if (_netSearchEnabled == value) return;
    _netSearchEnabled = value;
    _notify();
  }

  Future<void> waitForPendingUploads() async {
    while (_pendingUploads.isNotEmpty) {
      await Future.wait(List.of(_pendingUploads));
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
    final uploadFuture =
        _uploadDocument(id, attachment, model.aiType, fileName, bytes);
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
    try {
      final uploaded = await _repository.uploadDocument(
        groupId: _groupId,
        aiType: aiType,
        fileName: fileName,
        bytes: bytes,
        c: GenAiCancellation(),
      );
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = attachment.copyWith(
          fileId: uploaded.fileId,
          uploading: false,
        );
      }
    } catch (e) {
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = attachment.copyWith(
          uploading: false,
          error: '上传失败',
        );
      }
    } finally {
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
    try {
      final uploaded = await _repository.uploadVisionImage(
        fileName: fileName,
        bytes: bytes,
        c: GenAiCancellation(),
      );
      final fullUrl = genAiImageUri(uploaded.url).toString();
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = attachment.copyWith(
          imageUrl: fullUrl,
          uploading: false,
        );
      }
    } catch (e) {
      final index = _attachments.indexWhere((a) => a.id == id);
      if (index != -1) {
        _attachments[index] = attachment.copyWith(
          uploading: false,
          error: '上传失败',
        );
      }
    } finally {
      _notify();
    }
  }

  void removeAttachment(String id) {
    _attachments.removeWhere((a) => a.id == id);
    _notify();
  }

  void clearAttachments() {
    _attachments.clear();
    _notify();
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
    const alphabet =
        'useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict';
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
      if ((reportAuthenticationRequired ||
              error.kind != GenAiFailureKind.authenticationRequired) &&
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
    if (_owner != sessions.owner) {
      _owner = sessions.owner;
      newConversation();
      _loginFailure = null;
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

  Future<void> openConversation(
    String id,
    GenAiCancellation cancellation,
  ) async {
    if (sending || _disposed) return;
    final turns = await _repository.loadConversation(id, cancellation);
    cancellation.throwIfCancelled();
    if (_disposed) return;
    newConversation();
    _groupId = id;
    for (final saved in turns) {
      final turn = GenAiConversationTurn(saved.prompt)
        ..answer = saved.answer
        ..reasoning = saved.reasoning
        ..phase = saved.answer.isEmpty
            ? GenAiChatPhase.interrupted
            : GenAiChatPhase.completed;
      _turns.add(turn);
    }
    final aiType = turns.firstOrNull?.aiType;
    final model = models.where((m) => m.aiType == aiType).firstOrNull;
    // An unavailable historical model requires an explicit new choice.
    _selectedModel = model;
    _notify();
  }

  void selectModel(GenAiModel model) {
    if (sending || !models.contains(model)) return;
    _selectedModel = model;
    _notify();
  }

  Future<void> send(String prompt) async {
    final model = _selectedModel;
    if (_disposed || sending || !connected || model == null) {
      return;
    }
    if (_attachments.any((a) => a.uploading) || _pendingUploads.isNotEmpty) {
      await waitForPendingUploads();
    }
    if (prompt.trim().isEmpty && _attachments.isEmpty) {
      return;
    }
    final history = <GenAiMessage>[
      for (final turn
          in _turns.where((t) => t.phase == GenAiChatPhase.completed)) ...[
        GenAiMessage(role: GenAiRole.user, content: turn.prompt),
        GenAiMessage(role: GenAiRole.assistant, content: turn.answer),
      ],
    ];
    final fileIds = _attachments
        .where((a) => a.fileId != null)
        .map((a) => a.fileId!)
        .toList();
    final imageAttachments = _attachments.where((a) => a.isImage).toList();
    final imageUrl =
        imageAttachments.where((a) => a.imageUrl != null).firstOrNull?.imageUrl;
    final imageUrls =
        imageAttachments.map((a) => a.imageUrl).whereType<String>().toList();
    final attachedFileNames =
        _attachments.where((a) => !a.isImage).map((a) => a.name).toList();
    final attachedImageBytes =
        imageAttachments.where((a) => a.bytes.isNotEmpty).firstOrNull != null
            ? Uint8List.fromList(
                imageAttachments.firstWhere((a) => a.bytes.isNotEmpty).bytes,
              )
            : null;
    final attachedImageBytesList = [
      for (final a in imageAttachments)
        if (a.bytes.isNotEmpty) Uint8List.fromList(a.bytes),
    ];
    final turn = GenAiConversationTurn(prompt.trim())
      ..thinkingStartTime = DateTime.now()
      ..isSearching = _netSearchEnabled
      ..attachedFileNames = attachedFileNames
      ..attachedImageUrl = imageUrl
      ..attachedImageUrls = imageUrls
      ..attachedImageBytes = attachedImageBytes
      ..attachedImageBytesList = attachedImageBytesList;
    _attachments.clear();
    final generation = _generation;
    _turns.add(turn);
    _active = turn;
    _notify();

    if (_netSearchEnabled) {
      try {
        final citations = await _repository.searchWeb(
          GenAiChatRequest(
            chatGroupId: _groupId,
            prompt: turn.prompt,
            aiType: model.aiType,
            rootAiType: model.rootAiType,
            history: history,
            netGo: true,
          ),
          GenAiCancellation(),
        );
        turn.citations = citations;
      } catch (_) {}
      turn.isSearching = false;
      _notify();
    }

    try {
      await _chat.send(
        GenAiChatRequest(
          chatGroupId: _groupId,
          prompt: turn.prompt,
          aiType: model.aiType,
          rootAiType: model.rootAiType,
          history: history,
          thinking: _thinkingEnabled,
          netGo: _netSearchEnabled,
          fileIds: fileIds,
          imageUrl: imageUrl,
          imageUrls: imageUrls.isNotEmpty
              ? imageUrls
              : [if (imageUrl != null && imageUrl.isNotEmpty) imageUrl],
        ),
      );
    } finally {
      if (generation == _generation && identical(_active, turn)) _active = null;
      _notify();
    }
  }

  void _chatChanged() {
    final turn = _active;
    if (_disposed || turn == null) return;
    turn.answer = _chat.answer;
    turn.reasoning = _chat.reasoning;
    turn.phase = _chat.phase;
    turn.failure = _chat.failure;
    turn.finishReason = _chat.finishReason;
    if (turn.thinkingStartTime != null &&
        turn.thinkingDurationMs == null &&
        (_chat.answer.isNotEmpty || _chat.phase == GenAiChatPhase.completed)) {
      turn.thinkingDurationMs =
          DateTime.now().difference(turn.thinkingStartTime!).inMilliseconds;
    }
    _notify();
  }

  void stop() {
    _chat.stop();
    _active = null;
    _generation++;
    _notify();
  }

  void newConversation() {
    stop();
    _chat.clear();
    _turns.clear();
    _attachments.clear();
    _groupId = createGroupId();
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
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _catalogOperation?.cancel();
    sessions.removeListener(_sessionChanged);
    _chat.removeListener(_chatChanged);
    if (sending) _chat.stop();
    super.dispose();
  }
}
