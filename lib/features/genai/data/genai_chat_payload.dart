import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../platform/genai_transport.dart';
import 'genai_http_failure.dart';

/// Image bytes belong to inference context, never to the persisted imageUrl
/// fields or chatInfo. The latter retains TechPie's canonical attachment URLs
/// and tool receipts, so another device can build this payload again.
Future<Map<String, Object?>> genAiChatPayload(
  GenAiChatRequest request, {
  required GenAiTransport transport,
  required GenAiCancellation cancellation,
  required Uri Function(String) imageUri,
}) async {
  final payload = request.toJson();
  final urls = <String>{
    ...request.imageUrls,
    if (request.imageUrl case final url? when url.isNotEmpty) url,
  };
  if (urls.isEmpty) return payload;

  // The active selection is authoritative. Historical imageUrl extensions are
  // ignored by Kimi; attaching every old image would also defeat inspect_image.
  final messages = (payload['messages']! as List<Map<String, Object?>>)
      .map(
        (message) => Map<String, Object?>.of(message)
          ..remove('imageUrl')
          ..remove('imageUrls'),
      )
      .toList();
  final parts = <Map<String, Object?>>[];
  const maxImageBytes = 10 * 1024 * 1024;
  const maxTotalBytes = 25 * 1024 * 1024;
  var totalBytes = 0;
  // Validate the complete selection before fetching anything. CDN requests must
  // never carry the campus token or follow arbitrary model-authored URLs.
  final canonical = {for (final url in urls) genAiImageUri(url)};
  for (final url in canonical) {
    cancellation.throwIfCancelled();
    final download = GenAiCancellation();
    final remove = cancellation.onCancel(download.cancel);
    final timer = Timer(const Duration(seconds: 30), () {
      download.cancel(GenAiFailureKind.timeout);
    });
    GenAiResponse? response;
    try {
      response = await transport.send(
        method: 'GET',
        uri: imageUri(url.toString()),
        cancellation: download,
        headers: const {'Accept': 'image/png,image/jpeg,image/webp,image/gif'},
      );
      download.throwIfCancelled();
      await checkGenAiHttpStatus(
        statusCode: response.statusCode,
        contentType: response.headers['content-type'],
        bytes: response.bytes,
        cancellation: download,
      );
      final mime = response.headers['content-type']?.split(';').first.trim().toLowerCase();
      if (!const {'image/png', 'image/jpeg', 'image/webp', 'image/gif'}.contains(mime)) {
        throw const GenAiFailure(GenAiFailureKind.protocol);
      }
      final bytes = BytesBuilder(copy: false);
      final iterator = StreamIterator(response.bytes);
      var completed = false;
      try {
        while (await download.race(iterator.moveNext())) {
          final chunk = iterator.current;
          totalBytes += chunk.length;
          if (bytes.length + chunk.length > maxImageBytes || totalBytes > maxTotalBytes) {
            throw const GenAiFailure(GenAiFailureKind.messageTooLarge);
          }
          bytes.add(chunk);
        }
        completed = true;
      } finally {
        if (!completed) await iterator.cancel();
      }
      download.throwIfCancelled();
      if (bytes.isEmpty) throw const GenAiFailure(GenAiFailureKind.protocol);
      parts.add({'type': 'text', 'text': 'Image: $url'});
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes.takeBytes())}'},
      });
    } finally {
      response?.close();
      timer.cancel();
      remove();
      download.cancel();
    }
  }
  cancellation.throwIfCancelled();
  // Keep the tool-call guide immediately before chatInfo. No extra model call,
  // auxiliary conversation, cached image store or duplicated durable record.
  messages.insert(messages.length - (request.guideMessage == null ? 0 : 1), {
    'role': 'user',
    'content': parts,
  });
  return payload
    ..remove('imageUrl')
    ..remove('imageUrls')
    ..['messages'] = messages;
}
