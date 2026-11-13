import 'dart:convert';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_document_upload.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../platform/genai_transport.dart';
import 'genai_chat_payload.dart';
import 'genai_http_failure.dart';
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
    this.maxJsonBytes = 64 * 1024 * 1024,
  }) : _transport = transport,
       _base = apiBase ?? Uri.https('genai.shanghaitech.edu.cn', '/htk/'),
       _now = now ?? DateTime.now,
       _signer =
           signer ??
           (const String.fromEnvironment('TECHPI_GENAI_SIGNING_SALT').isEmpty
               ? null
               : const GenAiRequestSigner(String.fromEnvironment('TECHPI_GENAI_SIGNING_SALT'))) {
    final loopback = const ['localhost', '127.0.0.1', '::1'].contains(_base.host);
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

  /// Resolve only for display; chat requests retain canonical university URLs.
  Uri imageDisplayUri(String url) => genAiImageUri(url, baseOrigin: _base.origin);

  Future<GenAiProfile> verifyToken(String token, GenAiCancellation cancellation) async {
    _validateToken(token);
    final result = genAiObject(
      await _get('user/info/${Uri.encodeComponent(token)}', token, {
        '_t': '${_now().millisecondsSinceEpoch}',
      }, cancellation),
    );
    final user = genAiObject(result['userInfo']);
    return GenAiProfile(
      id: genAiRequiredString(user, 'id'),
      username: genAiRequiredString(user, 'username'),
    );
  }

  Future<List<GenAiModel>> listModels(String token, GenAiCancellation cancellation) async {
    final page = genAiObject(
      await _get('ai/aiModel/list', token, {
        'pageNo': '1',
        'pageSize': '999',
        'showStatusList': '2,3',
        '_t': '${_now().millisecondsSinceEpoch}',
      }, cancellation),
    );
    final records = page['records'];
    if (records is! List) throw const GenAiFailure(GenAiFailureKind.protocol);
    final byModel = <String, Map<String, dynamic>>{};
    bool hasText(Object? value) => value is String && value.trim().isNotEmpty;
    void merge(List<dynamic> records, {bool supplemental = false}) {
      for (final record in records) {
        if (record is! Map<String, dynamic>) continue;
        // Registry V2 includes unassigned rows without a provider. They cannot
        // be invoked; never guess a provider or discard the valid catalog.
        if (!hasText(record['rootAiType']) || !hasText(record['aiType'])) continue;
        final key = '${record['rootAiType']}:${record['aiType']}';
        final previous = byModel[key];
        final status = int.tryParse('${record['status']}');
        // V2 is not reliably curated: it also returns ASR/TTS/search and old
        // registry entries. Only declared chat/image rows may add new routes.
        if (supplemental &&
            ((status != null && status != 2 && status != 3) ||
                (previous == null && status == null))) {
          continue;
        }
        final name = hasText(record['aiName']) ? record['aiName'] : previous?['aiName'];
        if (!hasText(name)) continue;
        byModel[key] = {
          ...?previous,
          for (final entry in record.entries)
            if (entry.value != null) entry.key: entry.value,
          'aiName': name,
        };
      }
    }

    merge(records);
    try {
      final enterprise = genAiObject(
        await _get('ai/aiModel/list/V2', token, {
          'pageNo': '1',
          'pageSize': '999',
          'showStatusList': '2,3',
        }, cancellation),
      );
      final records = enterprise['records'];
      if (records is! List) throw const GenAiFailure(GenAiFailureKind.protocol);
      merge(records, supplemental: true);
    } on GenAiFailure catch (error) {
      // Older deployments may expose only the complete registry. Campus denial
      // is also HTTP 404; it must never be treated as an unavailable V2 route.
      if (error.statusCode != 404 || error.kind == GenAiFailureKind.campusNetworkRequired) rethrow;
    }
    if (records.isNotEmpty && byModel.isEmpty) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    return List.unmodifiable(
      byModel.values.map((record) {
        final model = genAiObject(record);
        return GenAiModel(
          name: genAiRequiredString(model, 'aiName'),
          aiType: genAiRequiredString(model, 'aiType'),
          rootAiType: genAiRequiredString(model, 'rootAiType'),
          status: int.tryParse('${model['status']}'),
          enableDeepThink:
              model['enableDeepThink'] == true ||
              model['enableDeepThink'] == 1 ||
              model['enableDeepThink'] == '1',
          payType: model['payType'] is String ? model['payType'] as String : null,
          promptPrice: model['promptPrice']?.toString(),
          completionPrice: model['completionPrice']?.toString(),
          cacheTokenPrice: model['cacheTokenPrice']?.toString(),
          longContextTokenThreshold: int.tryParse('${model['longContextTokenThreshold']}'),
          thinkingField: model['thinkingField'] is String ? model['thinkingField'] as String : null,
          thinkingFieldValue: model['thinkingFieldValue'] is String
              ? model['thinkingFieldValue'] as String
              : null,
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
  }) async => genAiPage(
    await _get('ai/history/listByContentGroup', token, {
      'userId': userId,
      'pageNo': '$page',
      'pageSize': '20',
      'question': query,
    }, cancellation),
    GenAiConversationSummary.fromJson,
    page: page,
    pageSize: 20,
  );

  Future<List<GenAiSavedTurn>> loadConversation(
    String token,
    String groupId,
    GenAiCancellation cancellation,
  ) async {
    final result = await _get('ai/history/getByChatGroupId', token, {
      'chatGroupId': groupId,
      '_t': '${_now().millisecondsSinceEpoch}',
    }, cancellation);
    if (result is! List) throw const GenAiFailure(GenAiFailureKind.protocol);
    final turns = <GenAiSavedTurn>[];
    for (final Object? row in result) {
      try {
        turns.add(GenAiSavedTurn.fromJson(genAiObject(row)));
      } catch (_) {
        // Preserve the missing position: skipping it can join unrelated tool
        // calls/results and incorrectly present an incomplete task as complete.
        turns.add(
          GenAiSavedTurn(
            prompt: '',
            answer: '',
            isHistoryGap: true,
            recordId: row is Map ? row['id']?.toString() : null,
          ),
        );
      }
    }
    return List.unmodifiable(turns);
  }

  Future<void> deleteMessages(
    String token,
    List<String> ids,
    GenAiCancellation cancellation,
  ) async {
    if (ids.any((id) => id.isEmpty || id.contains(','))) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    // Bound GET URL length. Delete newest batches first so a partial failure
    // leaves a prefix rather than dangling continuations where possible.
    for (var end = ids.length; end > 0;) {
      final start = (end - 50).clamp(0, end);
      await _get('ai/history/delete/batch', token, {
        'ids': ids.sublist(start, end).join(','),
        '_t': '${_now().millisecondsSinceEpoch}',
      }, cancellation);
      end = start;
    }
  }

  Future<void> deleteConversation(String token, String id, GenAiCancellation cancellation) async {
    await _get('ai/history/delete/groupId', token, {
      'id': id,
      '_t': '${_now().millisecondsSinceEpoch}',
    }, cancellation);
  }

  Future<void> renameConversation(
    String token,
    String id,
    String title,
    GenAiCancellation cancellation,
  ) async {
    await _jsonRequest(
      'ai/history/group/rename',
      token,
      cancellation,
      body: {'chatGroupId': id, 'title': title},
    );
  }

  Future<void> pinConversations(
    String token,
    List<String> ids,
    bool pinned,
    GenAiCancellation cancellation,
  ) async {
    if (ids.isEmpty) return;
    await _jsonRequest(
      'ai/history/group/pin',
      token,
      cancellation,
      body: {'chatGroupIds': ids, 'pinned': pinned},
    );
  }

  Future<void> deleteConversations(
    String token,
    List<String> ids,
    GenAiCancellation cancellation,
  ) async {
    if (ids.isEmpty) return;
    await _jsonRequest('ai/history/group/delete', token, cancellation, body: {'chatGroupIds': ids});
  }

  Future<List<Uri>> generateImage(
    String token,
    GenAiImageRequest request,
    GenAiCancellation cancellation,
  ) async {
    final result = genAiObject(
      await _jsonRequest('chat/start/chat', token, cancellation, body: request.toJson(), raw: true),
    );
    final data = result['data'];
    if (data is! List || data.isEmpty) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    return List.unmodifiable(
      data.map((Object? row) => genAiImageUri(genAiRequiredString(genAiObject(row), 'url'))),
    );
  }

  Future<GenAiPageResult<GenAiImageRecord>> listImages(
    String token,
    GenAiCancellation cancellation, {
    int page = 1,
  }) async => genAiPage(
    await _get('ai-image-history/list', token, {'pageNo': '$page', 'pageSize': '10'}, cancellation),
    GenAiImageRecord.fromJson,
    page: page,
    pageSize: 10,
  );

  Future<void> deleteImage(String token, String id, GenAiCancellation cancellation) async {
    await _jsonRequest(
      'ai-image-history/delete',
      token,
      cancellation,
      method: 'DELETE',
      query: {'id': id, '_t': '${_now().millisecondsSinceEpoch}'},
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
    final uploadName = GenAiDocumentUpload.prepareFileName(fileName, bytes);
    final multipart = GenAiMultipartData.create(
      fields: {'biz': 'temp'},
      fileFieldName: 'file',
      fileName: uploadName,
      fileBytes: bytes,
    );
    final uri = _base
        .resolve('chat/upload/chat/file')
        .replace(queryParameters: {'chatGroupId': groupId, 'aiType': aiType});
    final value = await _postMultipart(uri, token, multipart, cancellation);
    return GenAiUploadedFile.fromJson(genAiObject(value));
  }

  Future<GenAiUploadedImage> uploadVisionImage(
    String token, {
    required String fileName,
    required List<int> bytes,
    required GenAiCancellation cancellation,
  }) async {
    _validateToken(token);
    final lower = fileName.toLowerCase();
    final contentType = lower.endsWith('.png')
        ? 'image/png'
        : (lower.endsWith('.gif')
              ? 'image/gif'
              : (lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg'));
    final multipart = GenAiMultipartData.create(
      fields: const {'biz': 'temp', 'uploadType': 'local'},
      fileFieldName: 'file',
      fileName: fileName,
      fileBytes: bytes,
      fileContentType: contentType,
    );
    final host = _base.host == 'genai.shanghaitech.edu.cn'
        ? 'genaipic.shanghaitech.edu.cn'
        : _base.host;
    final uri = _base.replace(host: host, path: '/sys/common/upload', queryParameters: null);
    final value = await _postMultipart(
      uri,
      token,
      multipart,
      cancellation,
      headers: {
        'x-access-token': token,
        'X-Access-Token': token,
        'token': const String.fromEnvironment(
          'TECHPI_GENAI_VISION_TOKEN',
          defaultValue: '2ea38f293adb4abca21132feba61eaa3',
        ),
      },
    );
    return GenAiUploadedImage.fromJson(genAiObject(value));
  }

  Future<Object?> _postMultipart(
    Uri uri,
    String token,
    GenAiMultipartData multipart,
    GenAiCancellation cancellation, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _transport.send(
      method: 'POST',
      uri: uri,
      cancellation: cancellation,
      headers: {
        'X-Access-Token': token,
        'tenant-id': '0',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': multipart.contentType,
        ...headers,
      },
      bodyBytes: multipart.bytes,
    );
    try {
      await _checkStatus(response, cancellation);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      return genAiEnvelope(value);
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
      await _checkStatus(response, cancellation);
      final contentType = response.headers['content-type']?.split(';').first.trim().toLowerCase();
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
    final value = await _postMultipart(
      _base.resolve('chat/recognize'),
      token,
      multipart,
      cancellation,
      headers: {'x-access-token': token},
    );
    return genAiTranscriptionText(genAiObject(value));
  }

  Future<GenAiUsageSummary> usageSummary(String token, GenAiCancellation cancellation) async =>
      GenAiUsageSummary.fromJson(
        genAiObject(
          await _jsonRequest('ai-api-gateway/my/summary', token, cancellation, signed: true),
        ),
      );

  Future<GenAiPageResult<GenAiUsageOrder>> usageOrders(
    String token,
    GenAiCancellation cancellation, {
    int page = 1,
  }) async => genAiPage(
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
    String? method,
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    bool signed = false,
    bool raw = false,
  }) async {
    _validateToken(token);
    final uri = _base.resolve(path).replace(queryParameters: query.isEmpty ? null : query);
    final signer = _signer;
    if (signed && signer == null) {
      throw const GenAiFailure(GenAiFailureKind.rejected);
    }
    final wireBody = body == null ? null : signer?.prepareBody(body) ?? body;
    final response = await _transport.send(
      method: method ?? (wireBody == null ? 'GET' : 'POST'),
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
      await _checkStatus(response, cancellation);
      final value = await _readJson(response);
      cancellation.throwIfCancelled();
      if (raw) {
        final image = genAiObject(value);
        if (image['success'] == false ||
            image['code'] == 401 ||
            (image['code'] is int && image['code'] != 0 && image['code'] != 200)) {
          try {
            genAiEnvelope(image);
          } on GenAiFailure catch (failure) {
            // Generic business errors can arrive after dispatch. Only recognized
            // quota validation responses prove that generation was refused.
            final message = image['message'] ?? image['errMsg'];
            if (failure.kind == GenAiFailureKind.rejected &&
                const {'账户额度不足', '额度不足', '余额不足'}.contains(message)) {
              throw const GenAiFailure(GenAiFailureKind.rejected, effectNotDispatched: true);
            }
            rethrow;
          }
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
  ) => _jsonRequest(path, token, cancellation, query: query);

  Stream<GenAiChatEvent> streamChat(
    GenAiChatRequest request,
    String token,
    GenAiCancellation cancellation,
  ) async* {
    _validateToken(token);
    final payload = await genAiChatPayload(
      request,
      transport: _transport,
      cancellation: cancellation,
      imageUri: imageDisplayUri,
    );
    cancellation.throwIfCancelled();
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
      body: jsonEncode(payload),
    );
    try {
      await _checkStatus(response, cancellation);
      final contentType = response.headers['content-type']?.split(';').first.trim().toLowerCase();
      if (contentType != 'text/event-stream') {
        // Some business/auth failures arrive as a JSON envelope with HTTP 200.
        genAiEnvelope(await _readJson(response));
        throw const GenAiFailure(GenAiFailureKind.protocol);
      }
      final azure = request.rootAiType == 'azure';
      GenAiFinishReason? finishReason;
      await for (final event in const GenAiSseDecoder().decode(response.bytes)) {
        cancellation.throwIfCancelled();
        if (event.type == 'error') {
          throw const GenAiFailure(GenAiFailureKind.rejected);
        }
        if (event.data.trim() == '[DONE]') {
          // Azure sends the school persistence receipt after the model's DONE.
          if (azure) continue;
          yield GenAiChatFinished(finishReason ?? GenAiFinishReason.done);
          return;
        }
        final Map<String, dynamic> chunk;
        try {
          chunk = genAiObject(jsonDecode(event.data));
        } on FormatException {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (chunk.containsKey('success') || chunk.containsKey('code')) {
          genAiEnvelope(chunk);
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (chunk.containsKey('error')) {
          throw const GenAiFailure(GenAiFailureKind.rejected);
        }
        if (chunk.containsKey('other')) {
          final Object? receipt;
          try {
            final other = chunk['other'];
            receipt = other is String ? jsonDecode(other) : other;
          } on FormatException {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          final metadata = genAiObject(receipt);
          final answerId = metadata['answerGroupId'];
          if (azure && !((answerId is String && answerId.trim().isNotEmpty) || answerId is int)) {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          yield GenAiChatFinished(finishReason ?? GenAiFinishReason.done);
          return;
        }
        final ended = chunk['isEnd'] == 1 || chunk['is_end'] == 1;
        final choices = chunk['choices'];
        if (choices == null && ended && !azure) {
          yield GenAiChatFinished(finishReason ?? GenAiFinishReason.stop);
          return;
        }
        if (choices is! List) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        if (choices.isEmpty &&
            (chunk['usage'] is Map ||
                (azure &&
                    (chunk['prompt_filter_results'] is List ||
                        chunk['prompt_annotations'] is List)))) {
          continue;
        }
        if (choices.length != 1) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        final choice = genAiObject(choices.single);
        // Azure can also send annotation-only choices without a text delta.
        final delta = azure && choice['delta'] == null && choice['content_filter_results'] is Map
            ? <String, dynamic>{}
            : genAiObject(choice['delta']);
        for (final field in ['reasoning_content', 'content']) {
          final value = delta[field];
          if (value != null && value is! String) {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          if (value is String && value.isNotEmpty) {
            yield field == 'content' ? GenAiTextDelta(value) : GenAiReasoningDelta(value);
          }
        }
        if (ended && finishReason == null) finishReason = GenAiFinishReason.stop;
        final finish = choice['finish_reason'];
        if (finish != null) {
          if (finish is! String || finish.isEmpty) {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          // The school can report a save failure after the model's stop chunk.
          // Keep streaming text; Azure additionally requires the school receipt.
          finishReason = switch (finish) {
            'stop' => GenAiFinishReason.stop,
            'length' => GenAiFinishReason.length,
            'content_filter' => GenAiFinishReason.contentFilter,
            _ => GenAiFinishReason.other,
          };
        }
      }
      cancellation.throwIfCancelled();
      if (!azure && finishReason != null) {
        yield GenAiChatFinished(finishReason);
        return;
      }
      throw const GenAiFailure(GenAiFailureKind.interrupted);
    } finally {
      response.close();
    }
  }

  Future<Object?> _readJson(GenAiResponse response) async {
    final contentType = response.headers['content-type']?.split(';').first.trim().toLowerCase();
    if (contentType != 'application/json' && !(contentType?.endsWith('+json') ?? false)) {
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

  Future<void> _checkStatus(GenAiResponse response, GenAiCancellation cancellation) =>
      checkGenAiHttpStatus(
        statusCode: response.statusCode,
        contentType: response.headers['content-type'],
        bytes: response.bytes,
        cancellation: cancellation,
      );

  void _validateToken(String token) {
    if (token.isEmpty || !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token)) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
  }
}
