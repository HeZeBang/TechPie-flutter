import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';

/// The campus ingress returns this exact notice in a 404 HTML document before
/// dispatching the request. Other 404s, HTML pages and transport failures do not
/// establish either a campus-network restriction or a pre-execution rejection.
Future<void> checkGenAiHttpStatus({
  required int statusCode,
  required String? contentType,
  required Stream<List<int>> bytes,
  required GenAiCancellation cancellation,
  Duration errorBodyTimeout = const Duration(seconds: 2),
  int maxErrorBodyBytes = 64 * 1024,
}) async {
  cancellation.throwIfCancelled();
  if (statusCode >= 200 && statusCode < 300) return;
  if (statusCode == 401) {
    throw GenAiFailure(GenAiFailureKind.authenticationRequired, statusCode: statusCode);
  }

  final mediaType = contentType?.split(';').first.trim().toLowerCase();
  if (statusCode == 404 && (mediaType == 'text/html' || mediaType == 'application/xhtml+xml')) {
    final prefix = <int>[];
    final iterator = StreamIterator(bytes);
    try {
      await cancellation.race(
        (() async {
          while (prefix.length < maxErrorBodyBytes && await iterator.moveNext()) {
            prefix.addAll(iterator.current.take(maxErrorBodyBytes - prefix.length));
          }
        })()
            .timeout(errorBodyTimeout),
      );
    } catch (_) {
      // Retain the known HTTP failure if its optional diagnostic body is
      // truncated, stalled or unreadable. Cancellation always takes precedence.
      cancellation.throwIfCancelled();
    } finally {
      // Do not extend the inspection deadline waiting for transport cleanup.
      // The request owner also closes its response/client in its own finally.
      unawaited(iterator.cancel().catchError((Object _) {}));
    }
    cancellation.throwIfCancelled();
    final document = html.parse(utf8.decode(prefix, allowMalformed: true));
    // A notice mentioned only in JavaScript, metadata, attributes or comments
    // is not the ingress page's displayed access-denied message.
    for (final element in document.querySelectorAll('script, style, template, head, [hidden]')) {
      element.remove();
    }
    if (document.body?.text.contains('该服务暂不开放外网访问，仅支持校内访问') ?? false) {
      throw const GenAiFailure(
        GenAiFailureKind.campusNetworkRequired,
        statusCode: 404,
        effectNotDispatched: true,
      );
    }
  }
  throw GenAiFailure(GenAiFailureKind.rejected, statusCode: statusCode);
}
