import 'dart:convert';

import '../../../services/session/cookie_provider.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';
import '../platform/genai_transport.dart';
import '../platform/http_genai_transport.dart';

/// Browser preview bridge: Cookie headers cannot be set from Flutter web.
/// Only a loopback proxy is accepted; no campus cookie is sent to GenAI itself.
final class LoopbackGenAiIdsExchange {
  LoopbackGenAiIdsExchange(String origin, {GenAiTransport? transport})
      : _origin = Uri.parse(origin),
        _transport = transport {
    if (_origin.scheme != 'http' ||
        !const ['127.0.0.1', 'localhost', '::1'].contains(_origin.host) ||
        _origin.userInfo.isNotEmpty ||
        (_origin.path.isNotEmpty && _origin.path != '/') ||
        _origin.hasQuery ||
        _origin.hasFragment) {
      throw ArgumentError('IDS preview exchange must use a loopback origin');
    }
  }
  final Uri _origin;
  final GenAiTransport? _transport;

  Future<GenAiCredential> exchange(
    CookieProvider provider,
    GenAiCancellation cancellation,
  ) async {
    final transport = _transport ?? HttpGenAiTransport();
    try {
      final response = await transport.send(
        method: 'POST',
        uri: _origin.resolve('/preview/ids-exchange'),
        cancellation: cancellation,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'cookies': provider.cookies}),
      );
      try {
        if (response.statusCode == 401) {
          throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
        }
        if (response.statusCode != 200) {
          throw const GenAiFailure(GenAiFailureKind.transport);
        }
        final bytes = <int>[];
        await for (final chunk in response.bytes) {
          cancellation.throwIfCancelled();
          if (bytes.length + chunk.length > 16384) {
            throw const GenAiFailure(GenAiFailureKind.protocol);
          }
          bytes.addAll(chunk);
        }
        final result =
            genAiObject(genAiEnvelope(jsonDecode(utf8.decode(bytes))));
        return GenAiCredential(token: genAiRequiredString(result, 'token'));
      } finally {
        response.close();
      }
    } on GenAiFailure {
      rethrow;
    } on FormatException {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    } catch (_) {
      throw const GenAiFailure(GenAiFailureKind.transport);
    } finally {
      if (_transport == null) transport.dispose();
    }
  }
}
