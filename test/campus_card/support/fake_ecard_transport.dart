import 'dart:typed_data';

import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';

final class FakeEcardTransport implements EcardTransport {
  final Map<String, List<Object?>> responses = {};
  final List<FakeEcardRequest> requests = [];
  final Map<String, List<int>> downloads = {};

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

  @override
  Future<List<int>> download(String path) async {
    requests.add(FakeEcardRequest('DOWNLOAD', path, const {}));
    final value = downloads[path];
    if (value == null) throw StateError('No fake download for $path');
    return Uint8List.fromList(value);
  }

  @override
  Future<Object?> getPlain(
    String path,
    Map<String, Object?> query, {
    bool includeOpenId = false,
  }) async {
    requests.add(FakeEcardRequest('GET_PLAIN', path, Map.unmodifiable(query)));
    return _take('GET_PLAIN', path);
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
