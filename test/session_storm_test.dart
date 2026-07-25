import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/session/session_tree.dart';

/// Verifies the anti-renew-storm guarantees of the SessionNode tree:
///   1. Concurrent renew() calls share ONE in-flight renew (single-flight).
///   2. renewIfNeeded(beforeEpoch) skips when a concurrent renew already
///      advanced the epoch — the caller re-reads fresh cookies instead.
///   3. withCookie retries a 401 exactly once with the fresh cookie, and two
///      concurrent withCookie callers share a single renew.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingClient client;
  late LoggingHttpClient httpClient;
  late SessionTree tree;

  /// Seed an egate account so the cpdaily node is available. The renew
  /// endpoint (/auth/renew) is mocked to rotate tgc + cookies each call.
  ThirdPartyAccount seedAccount({String tgc = 'tgc-v0'}) =>
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.egate,
        account: 'student',
        sid: '2024xxxx',
        name: 'Test',
        token: 'tok',
        raw: {
          'sessionToken': 'st-v0',
          'tgc': tgc,
          'userId': 'u1',
          'tenantId': 't1',
          'cookies': 'JSESSIONID=js-v0',
        },
        boundAt: DateTime.now(),
      );

  setUp(() {
    client = _CountingClient();
    final logger = DebugLogger();
    httpClient = LoggingHttpClient(logger, inner: client);
    tree = SessionTree(
      persist: (_) async {},
      http: httpClient,
      baseUrl: () => 'https://backend.test',
    );
    tree.egate.setAccount(seedAccount());
  });

  test('concurrent renew() calls share one in-flight POST (single-flight)',
      () async {
    // Three concurrent renews — must collapse to ONE /auth/renew call.
    final results = await Future.wait([
      tree.egate.renew(),
      tree.egate.renew(),
      tree.egate.renew(),
    ]);
    expect(results, [true, true, true]);
    expect(client.renewCalls, 1);
    // Cookie advanced to v1.
    expect(tree.egate.cookieProvider!.cookies, contains('CASTGC=tgc-v1'));
  });

  test('renewIfNeeded skips when epoch already advanced by a concurrent renew',
      () async {
    final epochBefore = tree.egate.epoch;
    // Fire a renew in the background (don't await yet).
    final pending = tree.egate.renew();
    // While it's in-flight, renewIfNeeded(epochBefore) should join the same
    // in-flight renew rather than starting a second one.
    final second = tree.egate.renewIfNeeded(epochBefore);
    await Future.wait([pending, second]);
    expect(client.renewCalls, 1);
  });

  test('renewIfNeeded does NOT skip when epoch is still current', () async {
    final epochBefore = tree.egate.epoch;
    // No concurrent renew — renewIfNeeded must actually run.
    final ok = await tree.egate.renewIfNeeded(epochBefore);
    expect(ok, true);
    expect(client.renewCalls, 1);
    expect(tree.egate.epoch, greaterThan(epochBefore));
  });

  test('withCookie retries 401 once with refreshed cookie', () async {
    // First request to /fetch returns 401; retry (after renew) returns 200.
    client.fetchStatuses = [401, 200];
    client.fetchBodies = ['{}', jsonEncode({'ok': true})];

    final resp = await tree.withCookie<http.Response>(
      tree.egate,
      (cp) async {
        final r = await httpClient.post(
          Uri.parse('https://backend.test/fetch'),
          body: jsonEncode({'cookies': cp.cookies}),
        );
        return CookieAction(r, expired: r.statusCode == 401);
      },
    );
    expect(resp, isNotNull);
    expect(resp!.statusCode, 200);
    expect(client.renewCalls, 1);
    expect(client.fetchCalls, 2);
  });

  test('two concurrent withCookie callers share ONE renew on simultaneous 401',
      () async {
    // Both callers get 401 on first attempt, 200 after renew.
    client.fetchStatuses = [401, 401, 200, 200];
    client.fetchBodies = ['{}', '{}', '{"a":1}', '{"b":2}'];


    final results = await Future.wait([
      tree.withCookie<http.Response>(
        tree.egate,
        (cp) async {
          final r = await httpClient.post(
            Uri.parse('https://backend.test/fetch'),
            body: jsonEncode({'cookies': cp.cookies}),
          );
          return CookieAction(r, expired: r.statusCode == 401);
        },
      ),
      tree.withCookie<http.Response>(
        tree.egate,
        (cp) async {
          final r = await httpClient.post(
            Uri.parse('https://backend.test/fetch'),
            body: jsonEncode({'cookies': cp.cookies}),
          );
          return CookieAction(r, expired: r.statusCode == 401);
        },
      ),
    ]);

    // Exactly one renew across both concurrent 401-retry cycles.
    expect(client.renewCalls, 1);
    expect(
      results.every((r) => r != null && r.statusCode == 200),
      true,
      reason: 'both callers should succeed after the shared renew',
    );
  });

  test('ids node cookieProvider falls back to parent cpdaily cookies', () {
    final cp = tree.ids.cookieProvider;
    expect(cp, isNotNull);
    // Falls back to parent's CASTGC-bearing cookie set.
    expect(cp!.cookies, contains('CASTGC=tgc-v0'));
  });

  test('ids renew delegates to parent cpdaily renew (single-flight at parent)',
      () async {
    final ok = await tree.ids.renew();
    expect(ok, true);
    expect(client.renewCalls, 1);
    expect(tree.egate.cookieProvider!.cookies, contains('CASTGC=tgc-v1'));
  });
}

/// Mock HTTP client that counts /auth/renew calls and serves a configurable
/// sequence of statuses/bodies for other paths. The renew response rotates
/// tgc + cookies by appending a version suffix so each renew is observable.
class _CountingClient extends http.BaseClient {
  int renewCalls = 0;
  int fetchCalls = 0;
  List<int> fetchStatuses = const [];
  List<String> fetchBodies = const [];
  int _renewVersion = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();

    if (url.endsWith('/auth/renew')) {
      renewCalls++;
      _renewVersion++;
      final resp = jsonEncode({
        'success': true,
        'sessionToken': 'st-v$_renewVersion',
        'tgc': 'tgc-v$_renewVersion',
        'userId': 'u1',
        'tenantId': 't1',
        'cookies': 'JSESSIONID=js-v$_renewVersion',
      });
      return _resp(resp, 200);
    }

    // Other paths (fetch) consume from the configured sequences.
    fetchCalls++;
    final idx = fetchCalls - 1;
    final status = idx < fetchStatuses.length ? fetchStatuses[idx] : 200;
    final respBody = idx < fetchBodies.length ? fetchBodies[idx] : '{}';
    return _resp(respBody, status);
  }

  http.StreamedResponse _resp(String body, int status) {
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(bytes),
      status,
      request: null,
      headers: {'content-type': 'application/json'},
    );
  }
}
