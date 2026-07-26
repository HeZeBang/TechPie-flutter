import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/session/session_tree.dart';

/// Verifies the anti-renew-storm guarantees of the unified SessionNode tree:
///   1. Concurrent renew() calls share ONE in-flight renew (single-flight).
///   2. renewIfNeeded(beforeEpoch) skips when a concurrent renew already
///      advanced the epoch — the caller re-reads fresh cookies instead.
///   3. withCookie retries a 401 exactly once with the fresh cookie, and two
///      concurrent withCookie callers share a single renew.
///   4. Child nodes (eams/elearning) mint downstream cookies from the parent
///      cpdaily tgc; parent renew cascades to clear child derived cookies.
///   5. Two-level retry: a child 401 caused by a stale parent tgc triggers
///      parent renew → child re-mint → retry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingClient client;
  late LoggingHttpClient httpClient;
  late SessionTree tree;

  /// Seed a cpdaily account so the cpdaily node is available. The renew
  /// endpoint (/auth/renew) is mocked to rotate tgc + cookies each call.
  ThirdPartyAccount seedAccount({String tgc = 'tgc-v0'}) =>
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
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
      persist: (_, {force = false}) async {},
      http: httpClient,
      baseUrl: () => 'https://backend.test',
    );
    tree.cpdaily.setAccount(seedAccount());
  });

  test('concurrent renew() calls share one in-flight POST (single-flight)',
      () async {
    final results = await Future.wait([
      tree.cpdaily.renew(),
      tree.cpdaily.renew(),
      tree.cpdaily.renew(),
    ]);
    expect(results, [true, true, true]);
    expect(client.renewCalls, 1);
    // Cookie advanced to v1.
    expect(
      tree.cpdaily.cookieProvider!.cookies,
      contains('CASTGC=tgc-v1'),
    );
  });

  test('renewIfNeeded skips when epoch already advanced by a concurrent renew',
      () async {
    final epochBefore = tree.cpdaily.epoch;
    // Fire a renew in the background (don't await yet).
    final pending = tree.cpdaily.renew();
    // While it's in-flight, renewIfNeeded(epochBefore) should join the same
    // in-flight renew rather than starting a second one.
    final second = tree.cpdaily.renewIfNeeded(epochBefore);
    await Future.wait([pending, second]);
    expect(client.renewCalls, 1);
  });

  test('renewIfNeeded does NOT skip when epoch is still current', () async {
    final epochBefore = tree.cpdaily.epoch;
    // No concurrent renew — renewIfNeeded must actually run.
    final ok = await tree.cpdaily.renewIfNeeded(epochBefore);
    expect(ok, true);
    expect(client.renewCalls, 1);
    expect(tree.cpdaily.epoch, greaterThan(epochBefore));
  });

  test('withCookie retries 401 once with refreshed cookie', () async {
    // First request to /fetch returns 401; retry (after renew) returns 200.
    client.fetchStatuses = [401, 200];
    client.fetchBodies = ['{}', jsonEncode({'ok': true})];

    final resp = await tree.withCookie<http.Response>(
      tree.cpdaily,
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
        tree.cpdaily,
        (cp) async {
          final r = await httpClient.post(
            Uri.parse('https://backend.test/fetch'),
            body: jsonEncode({'cookies': cp.cookies}),
          );
          return CookieAction(r, expired: r.statusCode == 401);
        },
      ),
      tree.withCookie<http.Response>(
        tree.cpdaily,
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

  // -- Child node (eams/elearning) downstream renew tests --

  test('eams doRenew mints downstream cookie from parent tgc', () async {
    // Downstream renew returns a token (cookie string).
    final ok = await tree.eams.renew();
    expect(ok, true);
    expect(client.eamsCalls, 1);
    expect(tree.eams.cookieProvider, isNotNull);
    expect(tree.eams.cookieProvider!.cookies, 'JSESSIONID=eams-v1');
    // The renew POST body used the parent's current tgc.
    expect(client.lastEamsBody?['tgc'], 'tgc-v0');
  });

  test('eams isAvailable is false until doRenew succeeds', () {
    expect(tree.eams.isAvailable, false);
  });

  test('eams cookieProvider is null until doRenew succeeds', () {
    expect(tree.eams.cookieProvider, isNull);
  });

  test('parent cpdaily renew clears eams derived cookie (cascade)', () async {
    // First mint the eams cookie.
    await tree.eams.renew();
    expect(tree.eams.isAvailable, true);
    // Now renew the parent — the child's derived cookie must be cleared.
    final ok = await tree.cpdaily.renew();
    expect(ok, true);
    expect(tree.eams.isAvailable, false);
    expect(tree.eams.cookieProvider, isNull);
  });

  test('child 401 retry: eams renew succeeds (single-level, fresh parent)',
      () async {
    // Mint the eams cookie first.
    await tree.eams.renew();
    expect(client.eamsCalls, 1);

    // Fetch returns 401 (eams cookie stale), then 200 after re-mint.
    client.fetchStatuses = [401, 200];
    client.fetchBodies = ['{}', jsonEncode({'ok': true})];

    final resp = await tree.withCookie<http.Response>(
      tree.eams,
      (cp) async {
        final r = await httpClient.post(
          Uri.parse('https://backend.test/fetch'),
          body: jsonEncode({'cookies': cp.cookies}),
        );
        return CookieAction(r, expired: r.statusCode == 401);
      },
    );

    // Single-level retry: eams renew (2nd eams call) succeeds because the
    // parent tgc is still fresh. No parent renew needed.
    expect(resp, isNotNull);
    expect(resp!.statusCode, 200);
    expect(client.renewCalls, 0);
    expect(client.eamsCalls, 2);
  });

  test(
      'two-level retry: eams renew 401 (stale parent tgc) triggers parent renew',
      () async {
    // Reset parent to a stale tgc that the eams endpoint rejects.
    tree.cpdaily.setAccount(seedAccount(tgc: 'tgc-stale'));
    // Configure eams renew to fail on the stale tgc, then succeed after the
    // parent renews (rotating tgc to v1).
    client.eamsStatuses = [401, 200];
    client.eamsTokens = [null, 'JSESSIONID=eams-fresh'];

    // Configure the fetch path to return 200 (the fetch itself is fine once
    // the eams cookie is minted).
    client.fetchStatuses = [200];
    client.fetchBodies = [jsonEncode({'ok': true})];

    final resp = await tree.withCookie<http.Response>(
      tree.eams,
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
    // Parent was renewed (tgc rotated to v1).
    expect(client.renewCalls, 1);
    // Eams was minted twice: first (failed 401), then after parent renew.
    expect(client.eamsCalls, 2);
    expect(
      tree.eams.cookieProvider!.cookies,
      'JSESSIONID=eams-fresh',
    );
  });

  test('server error (500) does NOT trigger parent renew escalation', () async {
    // Eams renew returns 500 (backend error). The two-level fallback must
    // NOT escalate to parent renew — a server error isn't a credential
    // issue, and re-minting the parent tgc won't fix it.
    client.eamsStatuses = [500];

    final resp = await tree.withCookie<http.Response>(
      tree.eams,
      (cp) async {
        final r = await httpClient.post(
          Uri.parse('https://backend.test/fetch'),
          body: jsonEncode({'cookies': cp.cookies}),
        );
        return CookieAction(r, expired: r.statusCode == 401);
      },
    );

    expect(resp, isNull);
    // Parent renew was NOT called (no escalation on 500).
    expect(client.renewCalls, 0);
    // Eams renew was attempted once (first-level minting).
    expect(client.eamsCalls, 1);
  });
}

/// Mock HTTP client that counts /auth/renew and /auth/third-party/eams calls
/// and serves a configurable sequence of statuses/bodies for other paths.
/// The renew response rotates tgc + cookies by appending a version suffix so
/// each renew is observable.
class _CountingClient extends http.BaseClient {
  int renewCalls = 0;
  int eamsCalls = 0;
  int fetchCalls = 0;
  List<int> fetchStatuses = const [];
  List<String> fetchBodies = const [];
  List<int> eamsStatuses = const [];
  List<String?> eamsTokens = const [];
  Map<String, dynamic>? lastEamsBody;
  int _renewVersion = 0;
  int _eamsVersion = 0;

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

    if (url.endsWith('/auth/third-party/eams')) {
      eamsCalls++;
      final body = request is http.Request
          ? jsonDecode(request.body) as Map<String, dynamic>
          : <String, dynamic>{};
      lastEamsBody = body;
      _eamsVersion++;
      final idx = eamsCalls - 1;
      final status = idx < eamsStatuses.length ? eamsStatuses[idx] : 200;
      final token = idx < eamsTokens.length
          ? eamsTokens[idx]
          : 'JSESSIONID=eams-v$_eamsVersion';
      final resp = jsonEncode({
        'success': true,
        'data': {'token': token},
      });
      return _resp(resp, status);
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
