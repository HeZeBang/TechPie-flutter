import '../domain/genai_failure.dart';

/// The small native boundary allows transport lifecycle tests without Apple APIs.
abstract interface class GenAiUrlSessionTask {
  void resume();
  void suspend();
  void cancel();
  void finish();
}

typedef GenAiUrlSessionTaskFactory =
    GenAiUrlSessionTask Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      required List<int>? body,
      required void Function(int status, Map<String, String> headers) onHeaders,
      required void Function(List<int> bytes) onData,
      required void Function(GenAiFailure? failure) onComplete,
    });
