import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAIAAABt+uBvAAAApElEQVR4nO3QMQ0AMAzAsCEpf1ADMwZ7m8NSAEQ+d0afzvpBPECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQIEDhAAECBAhQOECAAAECFA4QIECAAIUDBAgQoM0eMcZiSiv2Au4AAAAASUVORK5CYII=',
);

/// Serves a decodable 96 × 96 PNG for image preview and dimension checks.
final class TestImageHttpClient implements HttpClient {
  int requests = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return _ImageRequest(_png);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.bytes);

  final List<int> bytes;
  final _headers = _ImageHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _ImageHeaders();

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(
    bytes,
  ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
