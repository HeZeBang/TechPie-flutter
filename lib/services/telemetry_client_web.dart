import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createTelemetryClient() => _AnonymousClient();

/// The browser's same-origin default would attach cookies to a telemetry POST.
class _AnonymousClient extends http.BaseClient {
  final _abort = web.AbortController();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final headers = web.Headers();
    for (final entry in request.headers.entries) {
      headers.set(entry.key, entry.value);
    }
    final response = await web.window
        .fetch(
          request.url.toString().toJS,
          web.RequestInit(
            method: request.method,
            headers: headers,
            body: body.toJS,
            credentials: 'omit',
            referrerPolicy: 'no-referrer',
            redirect: 'error',
            signal: _abort.signal,
          ),
        )
        .toDart
        .catchError(
          (Object error) => throw http.ClientException('Telemetry request failed', request.url),
        );
    return http.StreamedResponse(const Stream.empty(), response.status);
  }

  @override
  void close() => _abort.abort();
}
