import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/campus_user_agent.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/ids/ids_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import 'support/fake_ids_client.dart';

const _legacyUserId = '11111111-2222-3333-4444-555555555555';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UA combines the actual app build, iPhone OS and screen scale', () {
    expect(
      CampusUserAgent.format(
        version: '1.0.1',
        build: '42',
        device: 'iPhone',
        system: 'iOS',
        systemVersion: '27.0.1',
        scale: 3,
      ),
      'TechPie/1.0.1.42 (iPhone; iOS 27.0.1; Scale/3.00) techpie/1.0.1',
    );
  });

  test('old campus records are upgrade-only and cannot expose or renew sessions', () async {
    final fixture = await _Fixture.create(legacy: true);
    expect(fixture.auth.needsIdsRebind, true);
    expect(fixture.auth.hasIdsBinding, false);
    expect(fixture.auth.idsAccount!.password, 'saved-password');
    for (final node in [
      fixture.auth.idsNode,
      fixture.auth.eamsNode,
      fixture.auth.elearningNode,
      fixture.auth.egateAppNode,
      fixture.auth.oaNode,
    ]) {
      expect(node.cookieProvider, isNull);
      expect(node.canRenew, false);
      expect(await fixture.auth.refreshNode(node), false);
    }
    expect(fixture.requests, isEmpty);
    expect(fixture.ids.logins, 0);
  });

  test('root and child identities stay fixed across repeated large and small refreshes', () async {
    final fixture = await _Fixture.create();
    await fixture.auth.applyIdsSyncBinding(
      IdsSyncBinding(
        credential: FakeIdsClient.key('20240001'),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        deviceId: 'test',
      ),
    );
    expect(await fixture.auth.refreshNode(fixture.auth.idsNode), true);
    Map<String, String> identities() => {
          'ids': fixture.auth.idsNode.displayName,
          'bb': fixture.auth.elearningNode.displayName,
          'eams': fixture.auth.eamsNode.displayName,
          'egate': fixture.auth.egateAppNode.displayName,
        };
    const expected = {
      'ids': 'Profile User',
      'bb': 'Profile User',
      'eams': '20240001',
      'egate': '20240001',
    };
    final frames = <Map<String, String>>[];
    fixture.auth.addListener(() => frames.add(identities()));
    for (var i = 0; i < 5; i++) {
      expect(await fixture.auth.refreshNode(fixture.auth.idsNode), true);
      final results = await Future.wait([
        fixture.auth.refreshNode(fixture.auth.elearningNode),
        fixture.auth.refreshNode(fixture.auth.eamsNode),
        fixture.auth.refreshNode(fixture.auth.egateAppNode),
      ]);
      expect(results, everyElement(true));
      expect(identities(), expected);
      expect(fixture.auth.idsAccount!.name, 'Profile User');
      expect(fixture.auth.idsAccount!.sid, '20240001');
    }
    expect(frames, isNotEmpty);
    expect(frames, everyElement(expected));
    // A graduate account's 403 on the EAMS feature probe must not hide its ID
    // or cause another IDS login: the CAS session itself remains valid.
    expect(fixture.ids.logins, 6);
  });
}

class _Ids extends IdsClient {
  int logins = 0;
  @override
  Future<IdsSession> login(IdsPasskey key, {bool backedUp = false}) async => IdsSession(
        key.username,
        {'tgc': 'new-${++logins}'},
        name: logins == 1 ? 'Profile User' : null,
      );
  @override
  Future<String> mintCookie(String id, Map<String, dynamic> root) async => switch (id) {
        'eams' => 'JSESSIONID=eams',
        'elearning' => 'session_id=bb',
        'egateApp' => 'MOD_AUTH_CAS=egate',
        _ => 'shkjdx_session=oa',
      };
}

class _Fixture {
  _Fixture(this.auth, this.ids, this.requests);
  final ThirdPartyAuthService auth;
  final _Ids ids;
  final List<http.Request> requests;
  static Future<_Fixture> create({bool legacy = false}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    if (legacy) {
      await storage.saveThirdPartyAccount(
        ThirdPartyAccount(
          platform: ThirdPartyPlatform.ids,
          account: '20240001',
          sid: _legacyUserId,
          name: 'Legacy User',
          password: 'saved-password',
          autoRenew: true,
          token: 'token',
          raw: const {
            'tgc': 'old',
            'sessionToken': 'st',
            'tenantId': 'tenant',
          },
          boundAt: DateTime.now(),
          expire: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
        ),
      );
    }
    if (legacy) {
      for (final node in ['eams', 'elearning', 'egateApp', 'oa']) {
        await storage.saveDerivedCookie(node, 'cached-old-cookie=must-not-be-used');
      }
    }
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      http.Response json(Map<String, dynamic> value) => http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
      final path = request.url.path;
      if (path.endsWith('/stdDetail.action')) return http.Response('forbidden', 403);
      if (request.url.host == 'elearning.shanghaitech.edu.cn') {
        return http.Response(
          '欢迎，Different Name &ndash;',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      if (path.contains('getAppConfig')) return json({'code': '0'});
      if (path.endsWith('hqdlxsjpcxx.do')) {
        return json({
          'code': '0',
          'datas': {
            'hqdlxsjpcxx': {
              'rows': [
                {'XSBH': '999999'},
              ],
            },
          },
        });
      }
      return http.Response('', 404);
    });
    final logging = LoggingHttpClient(DebugLogger(), inner: client);
    final ids = _Ids();
    final auth = ThirdPartyAuthService(storage, logging, idsClient: ids);
    await auth.initialize();
    return _Fixture(auth, ids, requests);
  }
}
