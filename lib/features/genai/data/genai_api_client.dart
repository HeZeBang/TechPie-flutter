import 'dart:convert';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../platform/genai_transport.dart';
import 'genai_multipart.dart';
import 'genai_request_signer.dart';
import 'genai_sse_decoder.dart';

/// Profile, chat and platform tools use the same verified credential.
/// The optional base URL must expose the same contract (for a future gateway).
final class GenAiApiClient {
  GenAiApiClient({
    required GenAiTransport transport,
    Uri? apiBase,
    DateTime Function()? now,
    GenAiRequestSigner? signer,
    this.maxJsonBytes = 2 * 1024 * 1024,
  })  : _transport = transport,
        _base = apiBase ?? Uri.https('genai.shanghaitech.edu.cn', '/htk/'),
        _now = now ?? DateTime.now,
        _signer = signer ??
            (const String.fromEnvironment('TECHPI_GENAI_SIGNING_SALT').isEmpty
                ? null
                : const GenAiRequestSigner(
                    String.fromEnvironment('TECHPI_GENAI_SIGNING_SALT'),
                  )) {
    final loopback =
        const ['localhost', '127.0.0.1', '::1'].contains(_base.host);
    if ((_base.scheme != 'https' && !(_base.scheme == 'http' && loopback)) ||
        !_base.path.endsWith('/') ||
        _base.userInfo.isNotEmpty ||
        _base.hasQuery ||
        _base.hasFragment) {
      throw ArgumentError('Invalid GenAI API base');
    }
  }

  final GenAiTransport _transport;
  final Uri _base;
  final DateTime Function() _now;
  final int maxJsonBytes;
  final GenAiRequestSigner? _signer;

  Future<GenAiProfile> verifyToken(
    String token,
    GenAiCancellation cancellation,
  ) async {
    _validateToken(token);
    final result = genAiObject(
      await _get(
        'user/info/${Uri.encodeComponent(token)}',
        token,
        {'_t': '${_now().millisecondsSinceEpoch}'},
        cancellation,
      ),
    );
    final user = genAiObject(result['userInfo']);
    return GenAiProfile(
      id: genAiRequiredString(user, 'id'),
      username: genAiRequiredString(user, 'username'),
    );
  }

  Future<List<GenAiModel>> listModels(
    String token,
    GenAiCancellation cancellation,
  ) async {
    final page = genAiObject(
      await _get(
        'ai/aiModel/list',
        token,
        {
          'pageNo': '1',
          'pageSize': '999',
          'showStatusList': '2,3',
          '_t': '${_now().millisecondsSinceEpoch}',
        },
        cancellation,
      ),
    );
    final records = page['records'];
    if (records is! List) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    return List.unmodifiable(
      records.map((Object? record) {
        final model = genAiObject(record);
        return GenAiModel(
          name: genAiRequiredString(model, 'aiName'),
          aiType: genAiRequiredString(model, 'aiType'),
          rootAiType: genAiRequiredString(model, 'rootAiType'),
          status: int.tryParse('${model['status']}'),
          payType:
              model['payType'] is String ? model['payType'] as String : null,
        );
      }),
    );
  }

  Future<GenAiPageResult<GenAiConversationSummary>> listConversations(
    String token,
    String userId,
    GenAiCancellation cancellation, {
    int page = 1,
    String query = '',
  }) async =>
      genAiPage(
        await _get(
          'ai/history/listByContentGroup',
          token,
          {
            'userId': userId,
            'pageNo': '$page',
            'pageSize': '20',
            'question': query,
          },
          cancellation,
        ),
        GenAiConversationSummary.fromJson,
        page: page,
        pageSize: 20,
      );

  Future<List<GenAiSavedTurn>> loadConversation(
    String token,
    String groupId,
    GenAiCancellation cancellation,
  ) async {
    final result = await _get(
      'ai/history/getByChatGroupId',
      token,
      {'chatGroupId': groupId, '_t': '${_now().millisecondsSinceEpoch}'},
      cancellation,
    );
    if (result is! List) throw const GenAiFailure(GenAiFailureKind.protocol);
    return List.unmodifiable(
      result.map((Object? row) => GenAiSavedTurn.fromJson(genAiObject(row))),
    );
  }

  Future<void> deleteConversation(
    String token,
    String id,
    GenAiCancellation cancellation,
  ) async {
    await _get(
      'ai/history/delete/groupId',
      token,
      {
        'id': id,
        '_t': '${_now().millisecondsSinceEpoch}',
      },
      cancellation,
    );
  }

  Future<List<Uri>> generateImage(
    String token,
    GenAiImageRequest request,
    GenAiCancellation cancellation,
  ) async {
    final result = genAiObject(
      await _jsonRequest(
        'chat/start/chat',
        token,
        cancellation,
        body: request.toJson(),
        raw: true,
      ),
    );
    final data = result['data'];
    if (data is! List || data.isEmpty) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    return List.unmodifiable(
      data.map(
        (Object? row) => genAiImageUri(
          genAiRequiredString(genAiObject(row), 'url'),
          baseOrigin: _base.origin,
        ),
      ),
    );
  }

  Future<GenAiPageResult<GenAiImageRecord>> listImages(
    String token,
    GenAiCancellation cancellation, {
    int page = 1,
  }) async =>
      genAiPage(
        await _get(
          'ai-image-history/list',
          token,
          {'pageNo': '$page', 'pageSize': '10'},
          cancellation,
        ),
        (json) => GenAiImageRecord.fromJson(json, baseOrigin: _base.origin),
        page: page,
        pageSize: 10,
      );

  Future<void> deleteImage(
    String token,
    String id,
    GenAiCancellation cancellation,
  ) async {
    _validateToken(token);
    final response = await _transport.send(
      method: 'DELETE',
      uri: _base.resolve('ai-image-history/delete').replace(
        queryParameters: {
          'id': id,
          '_t': '${_now().millisecondsSinceEpoch}',
        },
      ),
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
      },
    );
    try {
      _checkStatus(response.statusCode);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      genAiEnvelope(value);
    } finally {
      response.close();
    }
  }

  Future<List<GenAiWebSearchCitation>> searchWeb(
    String token,
    GenAiChatRequest request,
    GenAiCancellation cancellation,
  ) async {
    final result = genAiObject(
      await _jsonRequest(
        'chat/net/search',
        token,
        cancellation,
        body: request.toJson(),
        signed: true,
      ),
    );
    final links = result['links'];
    if (links is! List) return const [];
    return List.unmodifiable(
      links.map(
        (Object? item) => GenAiWebSearchCitation.fromJson(genAiObject(item)),
      ),
    );
  }

  Future<GenAiUploadedFile> uploadDocument(
    String token, {
    required String groupId,
    required String aiType,
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation cancellation,
  }) async {
    _validateToken(token);
    final multipart = GenAiMultipartData.create(
      fields: {'biz': 'temp'},
      fileFieldName: 'file',
      fileName: fileName,
      fileBytes: bytes,
    );
    final uri = _base.resolve('chat/upload/chat/file').replace(
      queryParameters: {
        'chatGroupId': groupId,
        'aiType': aiType,
      },
    );
    final response = await _transport.send(
      method: 'POST',
      uri: uri,
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': multipart.contentType,
      },
      bodyBytes: multipart.bytes,
    );
    try {
      _checkStatus(response.statusCode);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      return GenAiUploadedFile.fromJson(genAiObject(genAiEnvelope(value)));
    } finally {
      response.close();
    }
  }

  Future<GenAiUploadedImage> uploadVisionImage(
    String token, {
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation cancellation,
  }) async {
    _validateToken(token);
    final multipart = GenAiMultipartData.create(
      fileFieldName: 'file',
      fileName: fileName,
      fileBytes: bytes,
      fileContentType:
          fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
    );
    final host = _base.host == 'genai.shanghaitech.edu.cn'
        ? 'genaipic.shanghaitech.edu.cn'
        : _base.host;
    final uri = _base.replace(
      host: host,
      path: '/sys/common/upload',
      queryParameters: null,
    );
    final response = await _transport.send(
      method: 'POST',
      uri: uri,
      cancellation: cancellation,
      headers: {
        'x-access-token': token,
        'X-Access-Token': token,
        'token': '2ea38f293adb4abca21132feba61eaa3',
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': multipart.contentType,
      },
      bodyBytes: multipart.bytes,
    );
    try {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GenAiFailure(
          GenAiFailureKind.rejected,
          statusCode: response.statusCode,
        );
      }
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      return GenAiUploadedImage.fromJson(genAiObject(genAiEnvelope(value)));
    } finally {
      response.close();
    }
  }

  Future<List<int>> convertTextToSpeech(
    String token, {
    required String text,
    int speed = 1,
    String language = 'ZH',
    String speakerId = 'ZH',
    required GenAiCancellation cancellation,
  }) async {
    _validateToken(token);
    final uri = _base.resolve('chat/convert2wav');
    final response = await _transport.send(
      method: 'POST',
      uri: uri,
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'audio/*, application/json, */*',
      },
      body: jsonEncode({
        'text': text,
        'speed': speed,
        'language': language,
        'speaker_id': speakerId,
      }),
    );
    try {
      _checkStatus(response.statusCode);
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (contentType != null && contentType.startsWith('audio/')) {
        final bytes = <int>[];
        await for (final chunk in response.bytes) {
          cancellation.throwIfCancelled();
          bytes.addAll(chunk);
        }
        return bytes;
      }
      final value = await _readJson(response);
      genAiEnvelope(value);
      throw const GenAiFailure(GenAiFailureKind.protocol);
    } finally {
      response.close();
    }
  }

  Future<String> recognizeAudio(
    String token, {
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation cancellation,
  }) async {
    _validateToken(token);
    final multipart = GenAiMultipartData.create(
      fileFieldName: 'file',
      fileName: fileName,
      fileBytes: bytes,
      fileContentType: 'audio/wav',
    );
    final uri = _base.resolve('chat/recognize');
    final response = await _transport.send(
      method: 'POST',
      uri: uri,
      cancellation: cancellation,
      headers: {
        'x-access-token': token,
        'X-Access-Token': token,
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': multipart.contentType,
      },
      bodyBytes: multipart.bytes,
    );
    try {
      _checkStatus(response.statusCode);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      final envelope = genAiObject(genAiEnvelope(value));
      return GenAiAudioTranscription.fromJson(envelope).text;
    } finally {
      response.close();
    }
  }

  Future<GenAiUsageSummary> usageSummary(
    String token,
    GenAiCancellation cancellation,
  ) async =>
      GenAiUsageSummary.fromJson(
        genAiObject(
          await _jsonRequest(
            'ai-api-gateway/my/summary',
            token,
            cancellation,
            signed: true,
          ),
        ),
      );

  Future<GenAiPageResult<GenAiUsageOrder>> usageOrders(
    String token,
    GenAiCancellation cancellation, {
    int page = 1,
  }) async =>
      genAiPage(
        await _jsonRequest(
          'ai-trade-order/my/list',
          token,
          cancellation,
          signed: true,
          query: {'pageNo': '$page', 'pageSize': '10'},
        ),
        GenAiUsageOrder.fromJson,
        page: page,
        pageSize: 10,
      );

  Future<Object?> _jsonRequest(
    String path,
    String token,
    GenAiCancellation cancellation, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    bool signed = false,
    bool raw = false,
  }) async {
    _validateToken(token);
    final uri = _base
        .resolve(path)
        .replace(queryParameters: query.isEmpty ? null : query);
    final signer = _signer;
    if (signed && signer == null) {
      throw const GenAiFailure(GenAiFailureKind.rejected);
    }
    final wireBody = body == null ? null : signer?.prepareBody(body) ?? body;
    final response = await _transport.send(
      method: wireBody == null ? 'GET' : 'POST',
      uri: uri,
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
        if (wireBody != null) 'Content-Type': 'application/json; charset=utf-8',
        if (signer != null && (signed || body != null))
          ...signer.headers(uri, wireBody ?? const {}, _now()),
      },
      body: wireBody == null ? null : jsonEncode(wireBody),
    );
    try {
      _checkStatus(response.statusCode);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      if (raw) {
        final image = genAiObject(value);
        if (image['success'] == false ||
            image['code'] == 401 ||
            (image['code'] is int &&
                image['code'] != 0 &&
                image['code'] != 200)) {
          genAiEnvelope(image);
        }
        // The image API also returns {success: true, data: [...]} without the
        // Jeecg envelope's code/result fields; the official image UI accepts it.
        if (image.containsKey('data')) return image;
        if (!image.containsKey('success')) return image;
      }
      return genAiEnvelope(value);
    } finally {
      response.close();
    }
  }

  Future<Object?> _get(
    String path,
    String token,
    Map<String, String> query,
    GenAiCancellation cancellation,
  ) async {
    _validateToken(token);
    final response = await _transport.send(
      method: 'GET',
      uri: _base.resolve(path).replace(queryParameters: query),
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
      },
    );
    try {
      _checkStatus(response.statusCode);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      return genAiEnvelope(value);
    } finally {
      response.close();
    }
  }

  Stream<GenAiChatEvent> streamChat(
    GenAiChatRequest request,
    String token,
    GenAiCancellation cancellation,
  ) async* {
    _validateToken(token);
    final response = await _transport.send(
      method: 'POST',
      uri: _base.resolve('chat/start/chat'),
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'text/event-stream',
      },
      body: jsonEncode(request.toJson()),
    );
    try {
      _checkStatus(response.statusCode);
      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (contentType != 'text/event-stream') {
        // Some business/auth failures arrive as a JSON envelope with HTTP 200.
        genAiEnvelope(await _readJson(response));
        throw const GenAiFailure(GenAiFailureKind.protocol);
      }
      await for (final event
          in const GenAiSseDecoder().decode(response.bytes)) {
        cancellation.throwIfCancelled();
        if (event.type == 'error') {
          throw const GenAiFailure(GenAiFailureKind.rejected);
        }
        if (event.data.trim() == '[DONE]') {
          yield const GenAiChatFinished(GenAiFinishReason.done);
          return;
        }
        final Map<String, dynamic> chunk;
        try {
          chunk = genAiObject(jsonDecode(event.data));
        } on FormatException {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (chunk.containsKey('success')) {
          genAiEnvelope(chunk);
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (chunk.containsKey('error')) {
          throw const GenAiFailure(GenAiFailureKind.rejected);
        }
        final choices = chunk['choices'];
        if (choices is! List) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (choices.isEmpty && chunk['usage'] is Map) continue;
        if (choices.length != 1) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        final choice = genAiObject(choices.single);
        final delta = genAiObject(choice['delta']);
        for (final field in ['reasoning_content', 'content']) {
          final value = delta[field];
          if (value != null && value is! String) {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          if (value is String && value.isNotEmpty) {
            yield field == 'content'
                ? GenAiTextDelta(value)
                : GenAiReasoningDelta(value);
          }
        }
        final finish = choice['finish_reason'];
        if (finish != null) {
          if (finish is! String || finish.isEmpty) {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          yield GenAiChatFinished(
            switch (finish) {
              'stop' => GenAiFinishReason.stop,
              'length' => GenAiFinishReason.length,
              'content_filter' => GenAiFinishReason.contentFilter,
              _ => GenAiFinishReason.other,
            },
          );
          return;
        }
      }
      cancellation.throwIfCancelled();
      throw const GenAiFailure(GenAiFailureKind.interrupted);
    } finally {
      response.close();
    }
  }

  Future<Object?> _readJson(GenAiResponse response) async {
    final contentType =
        response.headers['content-type']?.split(';').first.trim().toLowerCase();
    if (contentType != 'application/json' &&
        !(contentType?.endsWith('+json') ?? false)) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    final bytes = <int>[];
    await for (final chunk in response.bytes) {
      if (bytes.length + chunk.length > maxJsonBytes) {
        throw const GenAiFailure(GenAiFailureKind.protocol);
      }
      bytes.addAll(chunk);
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
  }

  void _checkStatus(int status) {
    if (status == 401) {
      throw GenAiFailure(
        GenAiFailureKind.authenticationRequired,
        statusCode: status,
      );
    }
    if (status < 200 || status >= 300) {
      throw GenAiFailure(GenAiFailureKind.rejected, statusCode: status);
    }
  }

  void _validateToken(String token) {
    if (token.isEmpty || !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token)) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
  }
}
