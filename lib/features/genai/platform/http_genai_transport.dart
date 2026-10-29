import 'dart:async';

import 'package:http/http.dart' as http;

import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import 'genai_transport.dart';

/// Uses IOClient on native platforms and Fetch-backed BrowserClient on web.
/// Each request owns a client: closing a chat cannot abort another operation.
final class HttpGenAiTransport implements GenAiTransport {
  HttpGenAiTransport({
    http.Client Function()? createClient,
    this.headerTimeout = const Duration(seconds: 20),
    this.chatHeaderTimeout = const Duration(minutes: 3),
    this.chatIdleTimeout = const Duration(minutes: 3),
    this.idleTimeout = const Duration(seconds: 60),
    this.imageTimeout = const Duration(minutes: 5),
  }) : _createClient = createClient ?? http.Client.new;

  final http.Client Function() _createClient;
  final Duration headerTimeout;
  // Vision preprocessing and reasoning can delay the first SSE headers.
  final Duration chatHeaderTimeout;
  // Some gateways flush headers before long-context prefill/reasoning starts.
  final Duration chatIdleTimeout;
  final Duration idleTimeout;
  final Duration imageTimeout;
  final _active = <void Function()>{};
  bool _disposed = false;

  @override
  Future<GenAiResponse> send({
    required String method,
    required Uri uri,
    required GenAiCancellation cancellation,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
  }) async {
    cancellation.throwIfCancelled();
    if (_disposed) throw const GenAiFailure(GenAiFailureKind.cancelled);
    final client = _createClient();
    final abort = Completer<void>();
    var closed = false;
    void Function()? removeListener;
    void close() {
      if (closed) return;
      closed = true;
      removeListener?.call();
      if (!abort.isCompleted) abort.complete();
      client.close();
      _active.remove(close);
    }

    _active.add(close);
    removeListener = cancellation.onCancel(close);
    try {
      final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )
        ..followRedirects = false
        ..headers.addAll(headers);
      if (bodyBytes != null) {
        request.bodyBytes = bodyBytes;
      } else if (body != null) {
        request.body = body;
      }
      final accept = headers['Accept'] ?? headers['accept'] ?? headers['ACCEPT'] ?? '';
      final isChat = uri.path.endsWith('/chat/start/chat');
      final timeoutDuration = !isChat
          ? headerTimeout
          : accept.contains('text/event-stream')
              ? chatHeaderTimeout
              : imageTimeout;
      final response = await cancellation.race(
        client.send(request).timeout(timeoutDuration),
      );
      cancellation.throwIfCancelled();
      return GenAiResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        bytes: _read(
          response.stream,
          cancellation,
          close,
          isChat && accept.contains('text/event-stream') ? chatIdleTimeout : idleTimeout,
        ),
        close: close,
      );
    } catch (error) {
      close();
      throw _failure(error, cancellation);
    }
  }

  Stream<List<int>> _read(
    Stream<List<int>> source,
    GenAiCancellation cancellation,
    void Function() close,
    Duration timeout,
  ) async* {
    try {
      await for (final bytes in source.timeout(timeout)) {
        cancellation.throwIfCancelled();
        yield bytes;
      }
      cancellation.throwIfCancelled();
    } catch (error) {
      throw _failure(error, cancellation);
    } finally {
      close();
    }
  }

  GenAiFailure _failure(Object error, GenAiCancellation cancellation) {
    cancellation.throwIfCancelled();
    if (error is GenAiFailure) return error;
    return GenAiFailure(
      error is TimeoutException ? GenAiFailureKind.timeout : GenAiFailureKind.transport,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final close in _active.toList()) {
      close();
    }
  }
}
