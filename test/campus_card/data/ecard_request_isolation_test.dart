import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';
import 'package:techpie/features/campus_card/data/api/ecard_cipher.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_openid_auth_port.dart';
import 'package:techpie/features/campus_card/data/auth/geekpie_ecard_session_issuer.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_payment_code_repository.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_scan_payment_repository.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';

const _subjectOpenId = 'SYNTHETIC_OPENID_ACCOUNT_A';
const _quota = '/virtualcard/openQrcodeQuotaModify';
const _generate = '/offlineCode/openVirtualcard';
const _poll = '/virtualcard/queryOrderStatus';
const _scan = '/scan/scanningResult';

void main() {
  for (final operation in ['signIn', 'verify', 'restoreMissingCookie', 'restoreImported', 'recover401']) {
    test('authenticated event can immediately request the newly committed account', () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    Future<Object?>? request;
    final sub = rig.auth.changes.listen((event) {
      if (event.state == AuthState.authenticated) {
        request = rig.client.post('/myaccount/openMyAccountApp', const {});
      }
    });
    addTearDown(sub.cancel);
    await rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId));
    expect(request, isNotNull);
    await request;
    expect(rig.adapter.paths.where((path) => path == '/myaccount/openMyAccountApp'), hasLength(1));
  });

  test('session acquisition uses only the TechPie issuer: $operation', () async {
      final rig = await _Rig.create();
      addTearDown(rig.close);
      switch (operation) {
        case 'signIn': await rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId));
        case 'verify': await rig.auth.verifyOpenId(_subjectOpenId);
        case 'restoreMissingCookie':
          await rig.store.clearSessionCookie();
          await rig.auth.restore();
        case 'restoreImported':
          await rig.auth.importOpenId(_subjectOpenId);
          await rig.auth.restore();
        case 'recover401': await rig.auth.handleAuthenticationFailure(401);
      }
      expect(rig.adapter.paths, ['/api/auth/third-party/ecard', _quota]);
      expect(rig.adapter.requests.first.uri.host, 'geekpie.invalid');
      expect(rig.adapter.requests.first.method, 'POST');
      expect(rig.adapter.requests.first.data, {'method': 'wechat_openid', 'openid': _subjectOpenId});
      expect(rig.adapter.requests.first.followRedirects, isFalse);
    });
  }

  test('issuer failure cannot fall back to acquiring a campus session', () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    rig.adapter.issuerStatus = 503;
    await expectLater(rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId)), throwsA(isA<AppFailure>()));
    expect(rig.adapter.paths, ['/api/auth/third-party/ecard']);
    expect(await rig.store.readSessionCookie(), 'JSESSIONID=initial');
  });

  test('generations and polls cost only their own requests', () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    for (var generation = 0; generation < 2; generation++) {
      final frame = await rig.codes.generateOnlineCode();
      for (var poll = 0; poll < 10; poll++) {
        await rig.codes
            .pollTransaction(frame.payCode, context: frame.requestContext);
      }
    }
    // Nothing is fetched before a request any more: the identity comes from the
    // session the request was prepared with.
    expect(rig.adapter.paths.toSet(), {_generate, _poll});
    expect(rig.adapter.paths.where((path) => path == _generate), hasLength(2));
    expect(rig.adapter.paths.where((path) => path == _poll), hasLength(20));
    expect(rig.adapter.paths, hasLength(22));
  });

  test('Alipay generation uses usertype 18 and rejects the previous WeChat code', () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final previous = await rig.codes.generateOnlineCode();
    await rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId, channel: EcardOpenIdChannel.alipay));
    await expectLater(rig.codes.pollTransaction(previous.payCode, context: previous.requestContext), throwsA(isA<AppFailure>()));
    final current = await rig.codes.generateOnlineCode();
    final request = rig.adapter.requests.lastWhere((request) => request.uri.path == _generate);
    final payload = EcardCipher.decodeEnvelope((request.data as Map)['datajson'] as String) as Map;
    expect(payload['usertype'], '18');
    await rig.codes.pollTransaction(current.payCode, context: current.requestContext);
  });

  test('offline authorization cannot submit another account device code', () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    await expectLater(rig.client.post('/offlineCode/openOfflineCode', const {
      'idserial': 'STUDENT-A', 'devcode': 'SYNTHETIC_OPENID_ACCOUNT_B',
    }), throwsA(isA<AppFailure>()),);
    expect(rig.adapter.paths, isEmpty);
  });

  test('quota reads validate their own response without a duplicate request',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    await rig.client.post(_quota, const {});
    expect(rig.adapter.paths, [_quota]);
    rig.adapter.otherIdentity = true;
    await expectLater(
        rig.client.post(_quota, const {}), throwsA(isA<AppFailure>()),);
    expect(await rig.store.readSessionCookie(), isNull);
    expect(await rig.store.readVerifiedIdSerial(), 'STUDENT-A');
  });

  test('a generation for another identity is refused and never overwrites the pin',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    // The request is sent — nothing is checked before it any more — and its
    // response is what rejects it: the code it created is never handed over.
    rig.adapter.otherIdentity = true;
    await expectLater(
        rig.codes.generateOnlineCode(), throwsA(isA<AppFailure>()),);
    expect(rig.adapter.paths, [_generate, '/api/auth/third-party/ecard']);
    expect(await rig.store.readVerifiedIdSerial(), 'STUDENT-A');
    expect(await rig.store.readVerifiedCardId(), 'CARD-A');
    expect(await rig.store.readSessionCookie(), isNull);
  });

  test('repeated session restoration uses quota once and reuses the verified session',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    await rig.auth.restore();
    await rig.auth.restore();
    await rig.auth.verifyCurrentIdentity();
    expect(rig.adapter.paths, [_quota, _quota]);
  });

  test('polling requires an issued context, and older generations are retired',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final first = await rig.codes.generateOnlineCode();
    await expectLater(rig.client.post(_poll, {'paycode': first.payCode}),
        throwsA(isA<AppFailure>()),);
    final second = await rig.codes.generateOnlineCode();
    await expectLater(
        rig.codes.pollTransaction(first.payCode, context: first.requestContext),
        throwsA(isA<AppFailure>()),);
    await expectLater(
        rig.codes.pollTransaction('OTHER-CODE', context: second.requestContext),
        throwsA(isA<AppFailure>()),);
    expect(rig.adapter.paths.where((path) => path == _poll), isEmpty);
    await rig.codes
        .pollTransaction(second.payCode, context: second.requestContext);
    expect(rig.adapter.paths.where((path) => path == _poll), hasLength(1));
  });

  test('same-account sign in retires old code and password challenge contexts',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final frame = await rig.codes.generateOnlineCode();
    final challenge =
        await rig.scans.submit(qrCode: 'CLIENT', payTime: DateTime.utc(2026))
            as ScanPasswordRequired;
    await rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId));
    final before = rig.adapter.paths.length;
    await expectLater(
        rig.codes.pollTransaction(frame.payCode, context: frame.requestContext),
        throwsA(isA<AppFailure>()),);
    await expectLater(
      rig.scans.submit(
        qrCode: challenge.serverQrCode,
        password: '123456',
        context: challenge.context,
        payTime: DateTime.utc(2026),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(rig.adapter.paths.length, before);
  });

  test(
      'password retry checks quota once and cannot reuse the consumed challenge',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final challenge =
        await rig.scans.submit(qrCode: 'CLIENT', payTime: DateTime.utc(2026))
            as ScanPasswordRequired;
    final result = await rig.scans.submit(
      qrCode: challenge.serverQrCode,
      password: '123456',
      context: challenge.context,
      payTime: DateTime.utc(2026),
    );
    expect(result, isA<ScanSucceeded>());
    expect(rig.adapter.paths, [_scan, _scan]);
    await expectLater(
      rig.scans.submit(
        qrCode: challenge.serverQrCode,
        password: '123456',
        context: challenge.context,
        payTime: DateTime.utc(2026),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(rig.adapter.paths, hasLength(2));
  });

  test('a late result and a queued request cannot survive account switching',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final frame = await rig.codes.generateOnlineCode();
    final started = Completer<void>();
    final release = Completer<void>();
    rig.adapter.block = (path) async {
      if (path == _poll) {
        started.complete();
        await release.future;
      }
    };
    final pending =
        rig.codes.pollTransaction(frame.payCode, context: frame.requestContext);
    final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
    await started.future;
    final queued = rig.client.post('/myaccount/openMyAccountApp', const {});
    final queuedRejected = expectLater(queued, throwsA(isA<AppFailure>()));
    // Let the second request capture A and enter the client's queue.
    await Future<void>.delayed(Duration.zero);
    await rig.auth.signOut();
    await rig.auth.signIn(
        const OpenIdAuthCredential(openId: 'SYNTHETIC_OPENID_ACCOUNT_B'),);
    await rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId));
    release.complete();
    await Future.wait([rejected, queuedRejected]);
    expect(
        rig.adapter.paths
            .where((path) => path == '/myaccount/openMyAccountApp'),
        isEmpty,);
  });

  test('a quota read with missing identity fields fails closed', () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    rig.adapter.missingQuota = true;
    await expectLater(
        rig.client.post(_quota, const {}), throwsA(isA<AppFailure>()),);
    expect(await rig.store.readSessionCookie(), isNull);
  });

  test(
      'response provenance remains invalid after HTTP parsing and session rotation',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final response =
        await rig.client.post('/myaccount/openMyAccountApp', const {});
    await rig.auth.signIn(const OpenIdAuthCredential(openId: _subjectOpenId));
    var wrote = false;
    await expectLater(
        commitEcardResponse(response, () async {
          wrote = true;
        }),
        throwsA(isA<AppFailure>()),);
    expect(wrote, isFalse);
  });

  test(
      'session replacement cannot interleave with a cache or credential commit',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final response =
        await rig.client.post('/myaccount/openMyAccountApp', const {});
    final started = Completer<void>();
    final release = Completer<void>();
    final committing = commitEcardResponse(response, () async {
      // Context validation is reentrant while the persistence lock is held.
      await validateEcardResponse(response);
      started.complete();
      await release.future;
      expect(await rig.store.readOpenId(), _subjectOpenId);
    });
    final rejected = expectLater(committing, throwsA(isA<AppFailure>()));
    await started.future;
    final signingOut = rig.auth.signOut();
    release.complete();
    await rejected;
    await signingOut;
    expect(await rig.store.readOpenId(), isNull);
  });

  test('late authentication failures do not expire a newly selected account',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final frame = await rig.codes.generateOnlineCode();
    final started = Completer<void>();
    final release = Completer<void>();
    rig.adapter.pollStatus = 401;
    rig.adapter.block = (path) async {
      if (path == _poll) {
        started.complete();
        await release.future;
      }
    };
    final result =
        rig.codes.pollTransaction(frame.payCode, context: frame.requestContext);
    final rejected = expectLater(result, throwsA(isA<AppFailure>()));
    await started.future;
    await rig.auth.signIn(
        const OpenIdAuthCredential(openId: 'SYNTHETIC_OPENID_ACCOUNT_B'),);
    release.complete();
    await rejected;
    expect(await rig.store.readOpenId(), 'SYNTHETIC_OPENID_ACCOUNT_B');
    expect(await rig.store.readSessionCookie(), isNotNull);
  });

  test(
      'a request starting during account replacement cannot acquire the new session',
      () async {
    final rig = await _Rig.create();
    addTearDown(rig.close);
    final started = Completer<void>();
    final release = Completer<void>();
    rig.adapter.block = (path) async {
      if (path == '/api/auth/third-party/ecard') {
        started.complete();
        await release.future;
      }
    };
    final signingIn = rig.auth.signIn(
        const OpenIdAuthCredential(openId: 'SYNTHETIC_OPENID_ACCOUNT_B'),);
    await started.future;
    final request =
        rig.scans.submit(qrCode: 'CLIENT-A', payTime: DateTime.utc(2026));
    final rejected = expectLater(request, throwsA(isA<AppFailure>()));
    release.complete();
    await signingIn;
    await rejected;
    expect(rig.adapter.paths.where((path) => path == _scan), isEmpty);
  });
}

class _Rig {
  _Rig(this.store, this.adapter, this.auth, this.client);
  final SecureSessionCredentialStore store;
  final _Adapter adapter;
  final EcardOpenIdAuthPort auth;
  final EcardApiClient client;
  late final codes = EcardPaymentCodeRepository(client);
  late final scans = EcardScanPaymentRepository(client);
  static Future<_Rig> create() async {
    final store = SecureSessionCredentialStore(InMemorySecureCredentialStore());
    await store.writeSession(
      sessionCookie: 'JSESSIONID=initial',
      openId: _subjectOpenId,
      orgId: '2',
      verifiedIdSerial: 'STUDENT-A',
      verifiedCardId: 'CARD-A',
    );
    final adapter = _Adapter();
    Dio dio() => Dio(BaseOptions(baseUrl: 'https://example.invalid'))
      ..httpClientAdapter = adapter;
    final auth = EcardOpenIdAuthPort(
        dio: dio(),
        sessionIssuer: GeekPieEcardSessionIssuer(dio: dio(), endpoint: () => Uri.parse('https://geekpie.invalid/api/auth/third-party/ecard')),
        sessionStore: store,
        purgeAccountBoundCredentials: () async {},);
    final client = EcardApiClient(
      dio: dio(),
      sessionReader: auth.readSession,
      requestIdentityReader: auth.readRequestIdentity,
      accountRevisionReader: () => auth.accountRevision,
      sessionGenerationReader: () => auth.generation,
      commitInSession: auth.commitInSession,
      identityGuard: auth.verifyCurrentIdentity,
      onAuthenticationExpired: auth.handleAuthenticationFailure,
      onIdentityMismatch: auth.rejectCurrentOnlineSession,
    );
    return _Rig(store, adapter, auth, client);
  }

  Future<void> close() async {
    client.dispose();
    await auth.dispose();
  }
}

class _Adapter implements HttpClientAdapter {
  final paths = <String>[];
  final requests = <RequestOptions>[];
  bool otherIdentity = false;
  bool missingQuota = false;
  int nextCode = 0;
  int pollStatus = 200;
  int nextSession = 0;
  int issuerStatus = 200;
  Future<void> Function(String)? block;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture,) async {
    requests.add(options);
    paths.add(options.uri.path);
    await block?.call(options.uri.path);
    final identity = {
      'idserial': otherIdentity ? 'STUDENT-B' : 'STUDENT-A',
      'cardid': otherIdentity ? 'CARD-B' : 'CARD-A',
    };
    Object body;
    switch (options.uri.path) {
      case '/api/auth/third-party/ecard':
        final cookie = 'JSESSIONID=new-${nextSession++}';
        body = {'success': true, 'data': {'sid': identity['idserial'], 'token': cookie,
          'raw': {...identity, 'orgid': '2', 'cookies': cookie},},};
      case _quota:
        body = {'success': true, 'data': missingQuota ? <String, Object?>{} : identity};
      case _generate:
        body = {
          'success': true,
          'data': {
            ...identity,
            'code': '5638AABBCCDD${nextCode++}',
            'qrcode': '5638AABBCCDD',
            'allowOfflineCode': '1',
          },
        };
      case _poll:
        body = {
          'success': true,
          'data': {'status': 5},
        };
      case _scan:
        final previousScans = paths.where((path) => path == _scan).length;
        body = previousScans == 1
            ? {
                'success': true,
                'url': '/pages/common/inputPass/inputPass',
                'data': {'qrcode': 'SYNTHETIC%20CHALLENGE'},
              }
            : {'success': true, 'issuccess': '1', 'txamt': 880};
      case '/myaccount/openMyAccountApp':
        body = {'success': true};
      default:
        throw StateError('Unexpected endpoint in session isolation test');
    }
    return ResponseBody.fromString(
        jsonEncode(body), options.uri.path == _poll ? pollStatus : options.uri.path == '/api/auth/third-party/ecard' ? issuerStatus : 200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },);
  }

  @override
  void close({bool force = false}) {}
}
