import 'package:flutter/foundation.dart';

import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../platform/genai_transport.dart';
import '../platform/http_genai_transport.dart';
import 'demo_genai_backend.dart';

/// Debug fixture only. Synthetic credentials never leave the process. Real
/// credentials use the production transport, optionally through a local proxy.
final class DebugGenAiTransport implements GenAiTransport {
  DebugGenAiTransport({GenAiTransport? live, String? proxyOrigin})
      : _live = live ?? HttpGenAiTransport() {
    if (!kDebugMode) throw UnsupportedError('Preview is debug-only');
    final raw = proxyOrigin ??
        const String.fromEnvironment('TECHPI_GENAI_PROXY_ORIGIN');
    if (raw.isEmpty) return;
    final uri = Uri.parse(raw);
    if (uri.scheme != 'http' ||
        !const ['127.0.0.1', 'localhost', '::1'].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Preview proxy must be a loopback HTTP origin');
    }
    _proxy = uri;
  }

  final _demo = DemoGenAiBackend();
  final GenAiTransport _live;
  Uri? _proxy;

  @override
  Future<GenAiResponse> send({
    required String method,
    required Uri uri,
    required GenAiCancellation cancellation,
    Map<String, String> headers = const {},
    String? body,
    List<int>? bodyBytes,
  }) {
    final synthetic = headers['X-Access-Token'] == DemoGenAiBackend.token ||
        headers['x-access-token'] == DemoGenAiBackend.token;
    final proxy = _proxy;
    if (!synthetic &&
        (uri.scheme != 'https' ||
            (uri.host != 'genai.shanghaitech.edu.cn' &&
                uri.host != 'genaipic.shanghaitech.edu.cn') ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty)) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    return (synthetic ? _demo : _live).send(
      method: method,
      uri: synthetic || proxy == null
          ? uri
          : uri.replace(
              scheme: proxy.scheme,
              host: proxy.host,
              port: proxy.port,
            ),
      cancellation: cancellation,
      headers: headers,
      body: body,
      bodyBytes: bodyBytes,
    );
  }

  @override
  void dispose() {
    _demo.dispose();
    _live.dispose();
  }
}
