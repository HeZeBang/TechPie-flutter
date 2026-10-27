import '../domain/genai_cancellation.dart';

abstract interface class GenAiTransport {
  Future<GenAiResponse> send({
    required String method,
    required Uri uri,
    required GenAiCancellation cancellation,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
  });

  void dispose();
}

final class GenAiResponse {
  GenAiResponse({
    required this.statusCode,
    required Map<String, String> headers,
    required this.bytes,
    required this.close,
  }) : headers = Map.unmodifiable({
          for (final entry in headers.entries)
            entry.key.toLowerCase(): entry.value,
        });

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> bytes;
  final void Function() close;
}
