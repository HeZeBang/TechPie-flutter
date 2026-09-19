import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_openid_auth_port.dart';
import 'package:techpie/features/campus_card/data/auth/geekpie_ecard_session_issuer.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';

final _start = DateTime.utc(2026, 9, 14, 12);
const _issuerPath = '/api/auth/third-party/ecard';
const _quota = '/virtualcard/openQrcodeQuotaModify';
const _read = '/myaccount/openMyAccountApp';

void main() {
  test('after 31 idle minutes local binding survives and one TechPie recovery restores the session', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    final before = await h.auth.restoreLocal();
    h.now = _start.add(const Duration(minutes: 31));
    expect(await h.auth.readSession(), isNull);
    final local = await h.auth.restoreLocal();
    expect(local.state, AuthState.authenticated);
    expect(local.session!.subjectId, before.session!.subjectId);
    await Future.wait([h.auth.restore(), h.auth.restore()]);
    expect(h.adapter.issues, 1);
    expect((await h.auth.readSession())!.identity!.subjectId, before.session!.subjectId);
    expect(await h.store.readOpenId(), 'SYNTHETIC_OPENID_ACCOUNT_A');
    expect(h.purges, 0);
  });

  test('session replacement during a read retries with the new cookie', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    var replaced = false;
    h.adapter.beforeReply = (path) async {
      if (path == _read && !replaced) {
        replaced = true;
        await h.auth.rejectCurrentOnlineSession();
      }
    };
    await h.client.get(_read, {});
    expect(h.adapter.paths.where((path) => path == _read), hasLength(2));
    expect(h.adapter.issues, 1);
    expect(h.adapter.cookies.last, 'JSESSIONID=new-1');
  });

  test('online code generation retries an inconsistent response', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.adapter.wrongCodeOnce = true;
    await h.client.post('/offlineCode/openVirtualcard', {});
    expect(h.adapter.paths.where((path) => path == '/offlineCode/openVirtualcard'), hasLength(2));
    expect(h.adapter.issues, 1);
  });

  test('a late 401 joins recovery without invalidating its replacement', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.adapter.issuerGate = Completer<void>();
    final first = h.auth.handleAuthenticationFailure(401);
    await h.adapter.issuerStarted.future;
    final second = h.auth.handleAuthenticationFailure(401);
    h.adapter.issuerGate!.complete();
    await Future.wait([first, second]);
    expect(await h.store.readSessionCookie(), 'JSESSIONID=new-1');
    expect(h.adapter.issues, 1);
  });

  test(
      'logout during idle-session replacement prevents the old request from being sent',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.now = _start.add(const Duration(minutes: 31));
    h.adapter.issuerGate = Completer<void>();
    final pending = h.client.get(_read, {});
    final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
    await h.adapter.issuerStarted.future;
    final logout = h.auth.signOut();
    h.adapter.issuerGate!.complete();
    await rejected;
    await logout;
    expect(await h.store.readSessionCookie(), isNull);
    expect(h.adapter.paths.contains(_read), isFalse);
  });

  test(
      '401 recovery retains authenticated binding without interactive sign-in transitions',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    final events = <AuthSnapshot>[];
    final sub = h.auth.changes.listen(events.add);
    addTearDown(sub.cancel);
    await h.auth.handleAuthenticationFailure(401);
    expect(events, isNotEmpty);
    expect(events.every((event) => event.state == AuthState.authenticated),
        isTrue,);
    expect(events.every((event) => event.reason == null), isTrue);
    expect(h.purges, 0);
  });

  test(
      '30 minute inactivity clears only the cookie and renews once for queued requests',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.now = _start.add(const Duration(minutes: 29, seconds: 59));
    expect(await h.auth.readSession(), isNotNull);
    expect(await h.store.readSessionLastActivity(), _start);
    h.now = _start.add(const Duration(minutes: 30));
    expect(await h.auth.readSession(), isNull);
    expect(await h.store.readSessionCookie(), isNull);
    expect(await h.store.readOpenId(), 'SYNTHETIC_OPENID_ACCOUNT_A');
    expect(await h.store.readVerifiedIdSerial(), 'STUDENT-A');
    await Future.wait([h.client.get(_read, {}), h.client.get(_read, {})]);
    expect(h.adapter.issues, 1);
    expect(await h.store.readSessionCookie(), 'JSESSIONID=new-1');
    expect(h.purges, 0);
  });

  test('actual requests extend activity and the deadline survives a restart',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.now = _start.add(const Duration(minutes: 20));
    await h.client.get(_read, {});
    expect(await h.store.readSessionLastActivity(), h.now);
    await h.auth.dispose();
    h.auth = h.makeAuth();
    h.now = _start.add(const Duration(minutes: 49, seconds: 59));
    expect(await h.auth.readSession(), isNotNull);
    h.now = _start.add(const Duration(minutes: 50));
    expect(await h.auth.readSession(), isNull);
    expect(h.adapter.issues, 0);
  });

  test('requests inside the write interval reuse the stored activity', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.now = _start.add(const Duration(minutes: 20));
    await h.client.get(_read, {});
    expect(await h.store.readSessionLastActivity(), h.now);

    // Two more requests within the minute: the deadline still moves in memory,
    // but the keystore is not written again.
    h.now = _start.add(const Duration(minutes: 20, seconds: 30));
    await h.client.get(_read, {});
    await h.client.get(_read, {});
    expect(await h.store.readSessionLastActivity(),
        _start.add(const Duration(minutes: 20)),);

    h.now = _start.add(const Duration(minutes: 21, seconds: 1));
    await h.client.get(_read, {});
    expect(await h.store.readSessionLastActivity(), h.now);
  });

  test('a request does not go back to the session store', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    await h.client.get(_read, {});
    final afterFirst = h.secure.readsForTesting;
    await h.client.get(_read, {});
    await h.client.get(_read, {});

    // The session is held in memory: the store stays the authority for a cold
    // start and for changes, but not for every request. Before this each request
    // read it a dozen times, twice over, in front of a request that takes a
    // tenth of the time the reads did.
    expect(h.secure.readsForTesting, afterFirst);
  });

  test('legacy cookies without activity metadata are replaced before use',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    await h.secure.delete('geekpay.auth.last_activity');
    await h.client.get(_read, {});
    expect(h.adapter.issues, 1);
    expect(h.adapter.cookies.where((cookie) => cookie == 'JSESSIONID=initial'),
        isEmpty,);
  });

  test('active process timer removes the cookie at the idle deadline', () {
    fakeAsync((async) {
      late _Harness h;
      unawaited(_Harness.create().then((value) async {
        h = value;
        await h.auth.readSession();
      }),);
      async.flushMicrotasks();
      h.now = _start.add(const Duration(minutes: 30));
      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();
      String? cookie = 'not-read';
      unawaited(h.store.readSessionCookie().then((value) => cookie = value));
      async.flushMicrotasks();
      expect(cookie, isNull);
      unawaited(h.close());
      async.flushMicrotasks();
    });
  });

  test('a read the pass performs costs one request and leaves the session alone',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    final old = await h.auth.readSession();
    // Drift is not a read's business: it has no side effect to protect, and the
    // response is checked against the pinned identity either way.
    h.adapter.wrongQuotaOnce = true;
    await h.client.get(_read, {});
    expect(h.adapter.paths, [_read]);
    expect(h.adapter.issues, 0);
    expect((await h.auth.readSession())!.sameSession(old!), isTrue);
    expect(await h.store.readVerifiedIdSerial(), 'STUDENT-A');
  });

  test('inconsistent read response recovers once and retries only the read',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    h.adapter.wrongReadOnce = true;
    await h.client.get(_read, {});
    expect(h.adapter.paths.where((path) => path == _read), hasLength(2));
    expect(h.adapter.issues, 1);
  });

  test(
      'inconsistent payment response renews the session without replaying payment',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    await expectLater(
        h.client.post('/scan/scanningResult', {'qrcode': 'SYNTHETIC'}),
        throwsA(isA<AppFailure>()),);
    expect(h.adapter.paths.where((path) => path == '/scan/scanningResult'),
        hasLength(1),);
    expect(h.adapter.issues, 1);
    expect(await h.store.readSessionCookie(), 'JSESSIONID=new-1');
  });

  test('replacement identity cannot overwrite the original account pin',
      () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    // The read is sent — it no longer asks first — and its response is what
    // rejects the replacement: recovery renews, the renewal is refused for
    // carrying another account, and the pin survives.
    h.adapter.wrongReadOnce = true;
    h.adapter.wrongIssuer = true;
    await expectLater(h.client.get(_read, {}), throwsA(isA<AppFailure>()));
    expect(await h.store.readSessionCookie(), isNull);
    expect(await h.store.readVerifiedIdSerial(), 'STUDENT-A');
    expect(h.adapter.paths.contains(_read), isTrue);
  });

  test('no request asks for the identity before it is sent', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    // The identity comes from the session the request was prepared with, and a
    // response carrying another one is refused. Nothing is fetched first — on
    // any endpoint, not only the reads the pass performs.
    await h.client.post('/virtualcard/openVirtualCardSelf', const {});
    expect(h.adapter.paths, ['/virtualcard/openVirtualCardSelf']);
  });

  test('simultaneous mismatch rejection shares one recovery', () async {
    final h = await _Harness.create();
    addTearDown(h.close);
    await Future.wait([
      h.auth.rejectCurrentOnlineSession(),
      h.auth.rejectCurrentOnlineSession(),
    ]);
    expect(h.adapter.issues, 1);
    expect(h.purges, 0);
  });
}

class _Harness {
  _Harness(this.secure, this.store, this.adapter);
  final InMemorySecureCredentialStore secure;
  final SecureSessionCredentialStore store;
  final _Adapter adapter;
  DateTime now = _start;
  int purges = 0;
  late EcardOpenIdAuthPort auth;
  late EcardApiClient client;
  EcardOpenIdAuthPort makeAuth() => EcardOpenIdAuthPort(
      clock: Clock(() => now),
      sessionStore: store,
      dio: Dio(BaseOptions(baseUrl: 'https://campus.invalid'))
        ..httpClientAdapter = adapter,
      sessionIssuer: GeekPieEcardSessionIssuer(
          endpoint: () => Uri.parse('https://techpie.invalid$_issuerPath'),
          dio: Dio()..httpClientAdapter = adapter,),
      purgeAccountBoundCredentials: () async {
        purges++;
      },);
  static Future<_Harness> create() async {
    final secure = InMemorySecureCredentialStore();
    final store = SecureSessionCredentialStore(secure);
    await store.writeSession(
        sessionCookie: 'JSESSIONID=initial',
        openId: 'SYNTHETIC_OPENID_ACCOUNT_A',
        orgId: '2',
        verifiedIdSerial: 'STUDENT-A',
        verifiedCardId: 'CARD-A',
        lastActivityAt: _start,);
    final h = _Harness(secure, store, _Adapter());
    h.auth = h.makeAuth();
    h.client = EcardApiClient(
        dio: Dio(BaseOptions(baseUrl: 'https://campus.invalid'))
          ..httpClientAdapter = h.adapter,
        sessionReader: () => h.auth.readSession(),
        sessionPreparer: () => h.auth.prepareSession(),
        requestIdentityReader: () => h.auth.readRequestIdentity(),
        accountRevisionReader: () => h.auth.accountRevision,
        sessionGenerationReader: () => h.auth.generation,
        onSessionActivity: (session) => h.auth.recordSessionActivity(session),
        identityGuard: () => h.auth.verifyCurrentIdentity(),
        onIdentityMismatch: () => h.auth.rejectCurrentOnlineSession(),
        onAuthenticationExpired: (status) =>
            h.auth.handleAuthenticationFailure(status),);
    return h;
  }

  Future<void> close() async {
    client.dispose();
    await auth.dispose();
  }
}

class _Adapter implements HttpClientAdapter {
  int issues = 0;
  bool wrongCodeOnce = false;
  Future<void> Function(String)? beforeReply;
  Completer<void>? issuerGate;
  final issuerStarted = Completer<void>();
  bool wrongQuotaOnce = false;
  bool wrongReadOnce = false;
  bool wrongIssuer = false;
  final paths = <String>[];
  final cookies = <Object?>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture,) async {
    final path = options.uri.path;
    paths.add(path);
    cookies.add(options.headers['cookie']);
    final Map<String, Object?> body;
    if (path == _issuerPath) {
      if (!issuerStarted.isCompleted) issuerStarted.complete();
      await issuerGate?.future;
      final sid = wrongIssuer ? 'STUDENT-B' : 'STUDENT-A';
      final cookie = 'JSESSIONID=new-${++issues}';
      body = {
        'success': true,
        'data': {
          'sid': sid,
          'token': cookie,
          'raw': {
            'cookies': cookie,
            'orgid': '2',
            'idserial': sid,
            'cardid': 'CARD-A',
          },
        },
      };
    } else {
      final wrong = (path == _quota && wrongQuotaOnce) ||
          (path == _read && wrongReadOnce) ||
          (path == '/offlineCode/openVirtualcard' && wrongCodeOnce) ||
          path == '/scan/scanningResult';
      if (path == _quota) wrongQuotaOnce = false;
      if (path == _read) wrongReadOnce = false;
      if (path == '/offlineCode/openVirtualcard') wrongCodeOnce = false;
      body = {
        'success': true,
        'data': {
          'idserial': wrong ? 'STUDENT-B' : 'STUDENT-A',
          'cardid': 'CARD-A',
        },
      };
    }
    await beforeReply?.call(path);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    },);
  }

  @override
  void close({bool force = false}) {}
}
