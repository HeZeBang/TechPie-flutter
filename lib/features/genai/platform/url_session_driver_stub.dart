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
}) => throw UnsupportedError('URLSession requires an Apple platform');
