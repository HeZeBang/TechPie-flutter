import 'dart:async';
import 'dart:convert';

import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import 'genai_transport.dart';
import 'url_session_driver.dart';
import 'url_session_task.dart';

/// Apple networking with per-request sessions, native cancellation and live SSE.
final class UrlSessionGenAiTransport implements GenAiTransport {
  UrlSessionGenAiTransport({
    GenAiUrlSessionTaskFactory? createTask,
    this.headerTimeout = const Duration(seconds: 20),
    this.chatHeaderTimeout = const Duration(minutes: 3),
    this.idleTimeout = const Duration(seconds: 60),
    this.chatIdleTimeout = const Duration(minutes: 3),
    this.imageTimeout = const Duration(minutes: 5),
  }) : _createTask = createTask ?? createGenAiUrlSessionTask;

  final GenAiUrlSessionTaskFactory _createTask;
  final Duration headerTimeout;
  final Duration chatHeaderTimeout;
  final Duration idleTimeout;
  final Duration chatIdleTimeout;
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
    final response = Completer<GenAiResponse>();
    GenAiUrlSessionTask? task;
    Timer? headerTimer;
    Timer? idleTimer;
    void Function()? removeListener;
    var closed = false;
    var paused = false;
    late StreamController<List<int>> stream;
    late void Function() abort;

    void finish({GenAiFailure? failure, bool cancel = false}) {
      if (closed) return;
      closed = true;
      headerTimer?.cancel();
      idleTimer?.cancel();
      removeListener?.call();
      _active.remove(abort);
      if (cancel) task?.cancel();
      task?.finish();
      if (!response.isCompleted) {
        response.completeError(failure ?? const GenAiFailure(GenAiFailureKind.transport));
      } else if (failure != null) {
        stream.addError(failure);
      }
      unawaited(stream.close());
    }

    GenAiFailure cancelled() {
      try {
        cancellation.throwIfCancelled();
      } on GenAiFailure catch (failure) {
        return failure;
      }
      return const GenAiFailure(GenAiFailureKind.cancelled);
    }

    abort = () => finish(failure: cancelled(), cancel: true);
    final accept = headers.entries
        .where((entry) => entry.key.toLowerCase() == 'accept')
        .map((entry) => entry.value)
        .join(',');
    final chat = uri.path.endsWith('/chat/start/chat');
    final sse = chat && accept.contains('text/event-stream');
    final headerBudget = !chat ? headerTimeout : (sse ? chatHeaderTimeout : imageTimeout);
    final idleBudget = sse ? chatIdleTimeout : idleTimeout;
    void resetIdle() {
      idleTimer?.cancel();
      if (paused) return;
      idleTimer = Timer(
        idleBudget,
        () => finish(failure: const GenAiFailure(GenAiFailureKind.timeout), cancel: true),
      );
    }

    stream = StreamController<List<int>>(
      onPause: () {
        paused = true;
        idleTimer?.cancel();
        if (!closed) task?.suspend();
      },
      onResume: () {
        paused = false;
        if (closed) return;
        resetIdle();
        task?.resume();
      },
      onCancel: () => finish(cancel: true),
    );
    try {
      task = _createTask(
        method: method,
        uri: uri,
        headers: Map.unmodifiable(headers),
        body: bodyBytes ?? (body == null ? null : utf8.encode(body)),
        onHeaders: (status, values) {
          if (closed || response.isCompleted) return;
          headerTimer?.cancel();
          resetIdle();
          response.complete(
            GenAiResponse(
              statusCode: status,
              headers: values,
              bytes: stream.stream,
              close: () => finish(cancel: true),
            ),
          );
        },
        onData: (bytes) {
          if (closed) return;
          resetIdle();
          stream.add(bytes);
        },
        onComplete: (failure) => finish(failure: failure),
      );
      _active.add(abort);
      headerTimer = Timer(
        headerBudget,
        () => finish(failure: const GenAiFailure(GenAiFailureKind.timeout), cancel: true),
      );
      removeListener = cancellation.onCancel(abort);
      if (!closed) task.resume();
    } catch (_) {
      finish(failure: const GenAiFailure(GenAiFailureKind.transport), cancel: true);
    }
    return response.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final abort in _active.toList()) {
      abort();
    }
  }
}
