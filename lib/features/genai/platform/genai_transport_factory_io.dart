import 'dart:io';

import 'genai_transport.dart';
import 'http_genai_transport.dart';
import 'url_session_genai_transport.dart';

GenAiTransport createGenAiTransport() {
  if (Platform.isIOS || Platform.isMacOS) return UrlSessionGenAiTransport();
  return HttpGenAiTransport();
}
