import 'package:cupertino_http/cupertino_http.dart';
import 'package:objective_c/objective_c.dart';

import '../domain/genai_failure.dart';
import 'url_session_task.dart';

GenAiUrlSessionTask createGenAiUrlSessionTask({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  required List<int>? body,
  required void Function(int status, Map<String, String> headers) onHeaders,
  required void Function(List<int> bytes) onData,
  required void Function(GenAiFailure? failure) onComplete,
}) {
  final configuration = URLSessionConfiguration.ephemeralSessionConfiguration()
    ..httpShouldSetCookies = false
    ..cache = null
    // Dart timers own the separate header and idle budgets.
    ..timeoutIntervalForRequest = const Duration(hours: 1);
  final session = URLSession.sessionWithConfiguration(
    configuration,
    // The caller validates each redirect and intercepts token callbacks.
    onRedirect: (_, __, ___, ____) => null,
    onResponse: (_, __, response) {
      if (response is! HTTPURLResponse) {
        onComplete(const GenAiFailure(GenAiFailureKind.protocol));
        return NSURLSessionResponseDisposition.NSURLSessionResponseCancel;
      }
      onHeaders(response.statusCode, response.allHeaderFields);
      return NSURLSessionResponseDisposition.NSURLSessionResponseAllow;
    },
    onData: (_, __, bytes) => onData(bytes.toList()),
    onComplete: (_, __, error) => onComplete(
      error == null
          ? null
          : GenAiFailure(
              error.code == -1001 ? GenAiFailureKind.timeout : GenAiFailureKind.transport,
            ),
    ),
  );
  try {
    final request = MutableURLRequest.fromUrl(uri)..httpMethod = method;
    headers.forEach(request.setValueForHttpHeaderField);
    if (body != null) {
      request.setValueForHttpHeaderField('Content-Length', '${body.length}');
      request.httpBody = body.toNSData();
    }
    return _Task(session, session.dataTaskWithRequest(request));
  } catch (_) {
    session.finishTasksAndInvalidate();
    rethrow;
  }
}

final class _Task implements GenAiUrlSessionTask {
  _Task(this._session, this._task);
  final URLSession _session;
  final URLSessionTask _task;
  bool _finished = false;

  @override
  void resume() => _task.resume();
  @override
  void suspend() => _task.suspend();
  @override
  void cancel() => _task.cancel();

  @override
  void finish() {
    if (_finished) return;
    _finished = true;
    // This safely waits for native task completion, including task.cancel().
    _session.finishTasksAndInvalidate();
  }
}
