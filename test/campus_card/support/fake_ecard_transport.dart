import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';

final class FakeEcardTransport implements EcardTransport {
  final Map<String, List<Object?>> responses = {};
  final List<FakeEcardRequest> requests = [];

  void enqueue(String method, String path, Object? response) {
    responses.putIfAbsent('$method $path', () => []).add(response);
  }

  @override
  Future<Object?> get(
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
  }) async {
    requests.add(FakeEcardRequest('GET', path, Map.unmodifiable(data)));
    return _take('GET', path);
  }

  @override
  Future<Object?> post(
    String path,
    Map<String, Object?> data, {
    bool includeOpenId = true,
  }) async {
    requests.add(FakeEcardRequest('POST', path, Map.unmodifiable(data)));
    return _take('POST', path);
  }

  Object? _take(String method, String path) {
    final queue = responses['$method $path'];
    if (queue == null || queue.isEmpty) {
      throw StateError('No fake response for $method $path');
    }
    return queue.removeAt(0);
  }
}

final class FakeEcardRequest {
  const FakeEcardRequest(this.method, this.path, this.data);
  final String method;
  final String path;
  final Map<String, Object?> data;
}
