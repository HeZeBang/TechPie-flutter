import '../data/genai_api_client.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'genai_session_service.dart';

final class GenAiRepository {
  const GenAiRepository({
    required GenAiApiClient api,
    required GenAiSessionService sessions,
  })  : _api = api,
        _sessions = sessions;

  final GenAiApiClient _api;
  final GenAiSessionService _sessions;

  Uri imageDisplayUri(String url) => _api.imageDisplayUri(url);

  Future<T> _authorized<T>(
    GenAiCancellation cancellation,
    Future<T> Function(GenAiSession) action,
  ) async {
    cancellation.throwIfCancelled();
    final revision = _sessions.revision;
    void checkOwner() {
      if (_sessions.revision != revision) {
        cancellation.cancel(GenAiFailureKind.accountChanged);
      }
    }

    _sessions.addListener(checkOwner);
    GenAiSession? session;
    try {
      final active = await cancellation.race(_sessions.requireSession());
      session = active;
      cancellation.throwIfCancelled();
      final value = await cancellation.race(action(active));
      cancellation.throwIfCancelled();
      return value;
    } on GenAiFailure catch (error) {
      if (session != null &&
          error.kind == GenAiFailureKind.authenticationRequired) {
        await _sessions.reject(session);
      }
      rethrow;
    } finally {
      _sessions.removeListener(checkOwner);
    }
  }

  Future<GenAiPageResult<GenAiConversationSummary>> listConversations(
    GenAiCancellation c, {
    int page = 1,
    String query = '',
  }) =>
      _authorized(
        c,
        (s) => _api.listConversations(
          s.credential.token,
          s.profile.id,
          c,
          page: page,
          query: query,
        ),
      );
  Future<List<GenAiSavedTurn>> loadConversation(
    String id,
    GenAiCancellation c,
  ) =>
      _authorized(c, (s) => _api.loadConversation(s.credential.token, id, c));
  Future<void> deleteConversation(String id, GenAiCancellation c) =>
      _authorized(c, (s) => _api.deleteConversation(s.credential.token, id, c));
  Future<List<Uri>> generateImage(
    GenAiImageRequest request,
    GenAiCancellation c,
  ) =>
      _authorized(c, (s) => _api.generateImage(s.credential.token, request, c));
  Future<GenAiPageResult<GenAiImageRecord>> listImages(
    GenAiCancellation c, {
    int page = 1,
  }) =>
      _authorized(c, (s) => _api.listImages(s.credential.token, c, page: page));
  Future<void> deleteImage(String id, GenAiCancellation c) =>
      _authorized(c, (s) => _api.deleteImage(s.credential.token, id, c));
  Future<GenAiUsageSummary> usageSummary(GenAiCancellation c) =>
      _authorized(c, (s) => _api.usageSummary(s.credential.token, c));
  Future<GenAiPageResult<GenAiUsageOrder>> usageOrders(
    GenAiCancellation c, {
    int page = 1,
  }) =>
      _authorized(
        c,
        (s) => _api.usageOrders(s.credential.token, c, page: page),
      );

  Future<List<GenAiWebSearchCitation>> searchWeb(
    GenAiChatRequest request,
    GenAiCancellation c,
  ) =>
      _authorized(c, (s) => _api.searchWeb(s.credential.token, request, c));

  Future<GenAiUploadedFile> uploadDocument({
    required String groupId,
    required String aiType,
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation c,
  }) =>
      _authorized(
        c,
        (s) => _api.uploadDocument(
          s.credential.token,
          groupId: groupId,
          aiType: aiType,
          fileName: fileName,
          bytes: bytes,
          cancellation: c,
        ),
      );

  Future<GenAiUploadedImage> uploadVisionImage({
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation c,
  }) =>
      _authorized(
        c,
        (s) => _api.uploadVisionImage(
          s.credential.token,
          fileName: fileName,
          bytes: bytes,
          cancellation: c,
        ),
      );

  Future<List<int>> convertTextToSpeech(
    String text,
    GenAiCancellation c, {
    int speed = 1,
    String language = 'ZH',
    String speakerId = 'ZH',
  }) =>
      _authorized(
        c,
        (s) => _api.convertTextToSpeech(
          s.credential.token,
          text: text,
          speed: speed,
          language: language,
          speakerId: speakerId,
          cancellation: c,
        ),
      );

  Future<String> recognizeAudio({
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation c,
  }) =>
      _authorized(
        c,
        (s) => _api.recognizeAudio(
          s.credential.token,
          fileName: fileName,
          bytes: bytes,
          cancellation: c,
        ),
      );

  Stream<GenAiChatEvent> streamChat(
    GenAiChatRequest request,
    GenAiCancellation cancellation,
  ) async* {
    final revision = _sessions.revision;
    final operation = GenAiCancellation();
    final removeCaller = cancellation.onCancel(operation.cancel);
    void checkOwner() {
      if (_sessions.revision != revision) {
        operation.cancel(GenAiFailureKind.accountChanged);
      }
    }

    _sessions.addListener(checkOwner);
    try {
      operation.throwIfCancelled();
      final session = await operation.race(_sessions.requireSession());
      operation.throwIfCancelled();
      try {
        await for (final event
            in _api.streamChat(request, session.credential.token, operation)) {
          yield event;
        }
      } on GenAiFailure catch (error) {
        if (error.kind == GenAiFailureKind.authenticationRequired) {
          await _sessions.reject(session);
        }
        // A generation POST is never replayed, including HTTP/business 401.
        rethrow;
      }
    } finally {
      removeCaller();
      _sessions.removeListener(checkOwner);
      operation.cancel();
    }
  }

  Future<List<GenAiModel>> listModels(GenAiCancellation cancellation) async {
    cancellation.throwIfCancelled();
    final revision = _sessions.revision;
    final session = await cancellation.race(_sessions.requireSession());
    cancellation.throwIfCancelled();
    if (revision != _sessions.revision) {
      throw const GenAiFailure(GenAiFailureKind.accountChanged);
    }
    void checkOwner() {
      if (revision != _sessions.revision) {
        cancellation.cancel(GenAiFailureKind.accountChanged);
      }
    }

    _sessions.addListener(checkOwner);
    try {
      return await _api.listModels(session.credential.token, cancellation);
    } on GenAiFailure catch (error) {
      if (error.kind == GenAiFailureKind.authenticationRequired) {
        await _sessions.reject(session);
      }
      rethrow;
    } finally {
      _sessions.removeListener(checkOwner);
    }
  }
}
