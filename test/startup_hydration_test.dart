import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import 'support/fake_ids_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('critical boot reads only accounts; derived cookies wait for deferred', () async {
    final storage = _FakeStorage(await SharedPreferences.getInstance());
    final tp = ThirdPartyAuthService(
      storage,
      LoggingHttpClient(DebugLogger(), inner: _NoopClient()),
      idsClient: FakeIdsClient(),
    );
    addTearDown(tp.dispose);

    tp.armDeferredHydration();
    await tp.initializeCritical();
    expect(storage.thirdPartyReads, 3);
    expect(storage.derivedReads, isEmpty);
    expect(tp.initialized, isFalse);

    storage.cookies.addAll(const {
      'eams': 'eams-cookie',
      'elearning': 'elearning-cookie',
      'egateApp': 'egate-cookie',
      'oa': 'oa-cookie',
    });
    await tp.hydrateDeferred();

    expect(storage.derivedReads, ['eams', 'elearning', 'egateApp', 'oa']);
    expect(tp.initialized, isTrue);
    expect(tp.eamsNode.cookieProvider?.cookies, 'eams-cookie');
    expect(tp.elearningNode.cookieProvider?.cookies, 'elearning-cookie');
  });

  test('one failing derived key does not discard the others', () async {
    final storage = _FakeStorage(await SharedPreferences.getInstance());
    storage.cookies.addAll(const {
      'eams': 'eams-cookie',
      'elearning': 'elearning-cookie',
      'egateApp': 'egate-cookie',
      'oa': 'oa-cookie',
    });
    storage.failNode = 'elearning';
    final tp = ThirdPartyAuthService(
      storage,
      LoggingHttpClient(DebugLogger(), inner: _NoopClient()),
      idsClient: FakeIdsClient(),
      derivedCookieTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(tp.dispose);

    await tp.initialize();

    expect(tp.eamsNode.cookieProvider?.cookies, 'eams-cookie');
    expect(tp.elearningNode.cookieProvider, isNull);
    expect(tp.egateAppNode.cookieProvider?.cookies, 'egate-cookie');
    expect(tp.initialized, isTrue);
  });

  test('a hanging secure read releases the gate and never applies late', () async {
    final storage = _FakeStorage(await SharedPreferences.getInstance());
    storage.cookies['eams'] = 'late-cookie';
    final hang = Completer<void>();
    storage.hangNode = 'eams';
    storage.hang = hang;
    final tp = ThirdPartyAuthService(
      storage,
      LoggingHttpClient(DebugLogger(), inner: _NoopClient()),
      idsClient: FakeIdsClient(),
      derivedCookieTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(tp.dispose);

    final watch = Stopwatch()..start();
    await tp.initialize();
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(tp.initialized, isTrue);

    hang.complete();
    await Future<void>.delayed(Duration.zero);
    expect(tp.eamsNode.cookieProvider, isNull);
  });

  test('a clear during hydration prevents the stale batch from applying', () async {
    final storage = _FakeStorage(await SharedPreferences.getInstance());
    storage.cookies.addAll(const {
      'eams': 'eams-cookie',
      'elearning': 'elearning-cookie',
      'egateApp': 'egate-cookie',
      'oa': 'oa-cookie',
    });
    final hang = Completer<void>();
    storage.hangNode = 'eams';
    storage.hang = hang;
    final tp = ThirdPartyAuthService(
      storage,
      LoggingHttpClient(DebugLogger(), inner: _NoopClient()),
      idsClient: FakeIdsClient(),
      derivedCookieTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(tp.dispose);

    tp.armDeferredHydration();
    await tp.initializeCritical();
    final hydration = tp.hydrateDeferred();
    await Future<void>.delayed(Duration.zero);

    final clear = tp.replaceAll(const []);
    hang.complete();
    await Future.wait([hydration, clear]);

    expect(tp.eamsNode.cookieProvider, isNull);
    expect(tp.elearningNode.cookieProvider, isNull);
  });
}

class _FakeStorage extends StorageService {
  _FakeStorage(super.prefs);

  final List<String> derivedReads = [];
  final Map<String, String> cookies = {};
  int thirdPartyReads = 0;
  int allAccountsCalls = 0;
  String? failNode;
  String? hangNode;
  Completer<void>? hang;

  @override
  Future<ThirdPartyAccount?> loadThirdPartyAccount(ThirdPartyPlatform platform) async {
    thirdPartyReads++;
    if (platform == ThirdPartyPlatform.ids) {
      return FakeIdsClient.account('20240001');
    }
    return ThirdPartyAccount(
      platform: platform,
      account: platform.name,
      token: 'synthetic-token',
      raw: const {'authMethod': 'password'},
      boundAt: DateTime.utc(2026),
    );
  }

  @override
  Future<List<ThirdPartyAccount>> loadAllThirdPartyAccounts() async {
    allAccountsCalls++;
    return [
      for (final platform in ThirdPartyPlatform.values)
        if (await loadThirdPartyAccount(platform) case final account?) account,
    ];
  }

  @override
  Future<String?> loadDerivedCookie(String nodeId) async {
    derivedReads.add(nodeId);
    if (failNode == nodeId) throw StateError('synthetic secure read failure');
    if (hangNode == nodeId) {
      await hang!.future;
    }
    return cookies[nodeId];
  }
}

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw UnsupportedError('synthetic test client');
  }
}
