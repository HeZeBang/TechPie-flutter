import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techpie/services/debug_preview_http_client.dart';

void main() {
  test(
      'existing TechPie IDS requests use the loopback proxy without unrelated credentials',
      () async {
    final client = DebugPreviewHttpClient(
      proxyOrigin: 'http://127.0.0.1:18768',
      inner: MockClient((request) async {
        expect(
          request.url.toString(),
          'http://127.0.0.1:18768/api/auth/third-party/egate',
        );
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(request.body, '{"account":"student","password":"input"}');
        return http.Response('{"success":true}', 200);
      }),
    );
    addTearDown(client.close);
    expect(
      (await client.post(
        Uri.parse(
          'https://techpie.geekpie.club/api/auth/third-party/egate',
        ),
        headers: {'Authorization': 'unrelated-primary-credential'},
        body: '{"account":"student","password":"input"}',
      ))
          .statusCode,
      200,
    );
  });
  test('background and foreign requests stay local', () async {
    final client = DebugPreviewHttpClient(
      proxyOrigin: 'http://127.0.0.1:18768',
      inner: MockClient((_) async => throw StateError('must remain local')),
    );
    addTearDown(client.close);
    expect(
      (await client.get(Uri.parse('https://techpie.geekpie.club/api/courses')))
          .statusCode,
      503,
    );
    expect(
      (await client.post(
        Uri.parse('https://evil.example/api/auth/third-party/egate'),
      ))
          .statusCode,
      503,
    );
  });
}
