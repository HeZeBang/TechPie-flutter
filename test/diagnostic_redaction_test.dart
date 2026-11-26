import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  late DebugLogger logger;
  late List<String> console;
  setUp(() {
    console = [];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => console.add(message ?? '');
    addTearDown(() => debugPrint = original);
    logger = DebugLogger()..enabled = true;
  });

  String diagnostics() => [
        ...console,
        for (final e in logger.entries)
          [e.method, e.url, e.statusCode, e.requestBody, e.responseBody, e.error, e.tag].join(' '),
      ].join('\n');

  test('GET, POST and HEAD retain origin and status without request or response content', () async {
    final uri = Uri.parse(
      'https://userinfo:secret@example.test:8443/users/2026123456?ticket=secret-ticket#secret-fragment',
    );
    const body = '{"studentId":"2026123456","nested":{"unknown":"secret-password"}}';
    const reply = '<html>secret-name@example.test; CASTGC=secret-cookie</html>';
    var calls = 0;
    final client = LoggingHttpClient(
      logger,
      inner: MockClient((r) async {
        calls++;
        expect(r.url, uri);
        expect(r.headers['Cookie'], 'CASTGC=secret-cookie');
        if (r.method == 'POST') expect(r.body, body);
        return http.Response(reply, 403);
      }),
    );
    addTearDown(client.close);
    const headers = {'Cookie': 'CASTGC=secret-cookie', 'Authorization': 'Bearer secret-bearer'};
    expect((await client.get(uri, headers: headers)).body, reply);
    await client.post(uri, headers: headers, body: body);
    await client.head(uri, headers: headers);
    expect(calls, 3);
    expect(logger.entries.map((e) => e.url).toSet(), {'https://example.test:8443'});
    expect(logger.entries.last.statusCode, 403);
    expect(jsonDecode(logger.entries[1].responseBody!), {'bytes': utf8.encode(reply).length});
    for (final personal in ['secret', '2026123456', 'userinfo', 'CASTGC', '/users/']) {
      expect(diagnostics(), isNot(contains(personal)));
    }
  });

  test('the transport throws the original error but diagnostics record its type', () async {
    final error = http.ClientException('failed for private-student; session=private-cookie');
    final client = LoggingHttpClient(logger, inner: MockClient((r) => throw error));
    addTearDown(client.close);
    final uri = Uri.https('example.test');
    for (final request in [() => client.get(uri), () => client.post(uri), () => client.head(uri)]) {
      await expectLater(request(), throwsA(same(error)));
      expect(logger.entries.last.error, 'ClientException');
    }
    expect(diagnostics(), isNot(contains('private-')));
  });

  test('OAuth error descriptions and server-supplied field names stay out of both sinks', () async {
    final auth = UniAuthService(
      logger: logger,
      refreshRequest: (_) async => http.Response(
        jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'private-student private-refresh',
          'private-account-name': 'private-value',
        }),
        400,
      ),
    );
    await expectLater(auth.refresh('private-refresh'), throwsA(isA<SsoRefreshException>()));
    expect(logger.entries.last.statusCode, 400);
    expect(diagnostics(), isNot(contains('private-')));
  });
}
