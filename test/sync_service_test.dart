import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setup -> cloud has blob; restore on a fresh device recovers bindings',
      () async {
    final fx = await _Fixture.withSession();
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'a@b.edu',
        token: 'gs-token-123',
        boundAt: DateTime.utc(2026),
      ),
    ]);

    // Device A: set up sync with master password "pw".
    final setup = await fx.sync.setupWithMasterPassword('pw');
    expect(setup.ok, isTrue, reason: setup.message);
    expect(fx.sync.enabled, isTrue);
    expect(fx.sync.hasLocalKey, isTrue);
    // The server received a techpie_sync property — and it's ciphertext, not
    // the plaintext token.
    final written = fx.server.properties['techpie_sync'];
    expect(written, isNotNull);
    expect(written, isNot(contains('gs-token-123')));
    expect(written!.contains('.'), isTrue); // salt.inner format

    // Device B: fresh device — no cached key, same server state, empty local.
    final fx2 = await _Fixture.withSession(server: fx.server);
    expect(fx2.sync.hasLocalKey, isFalse);
    expect(await fx2.sync.cloudHasBlob(), isTrue);

    final restore = await fx2.sync.restoreWithMasterPassword('pw');
    expect(restore.ok, isTrue, reason: restore.message);
    expect(
      fx2.tpAuth.account(ThirdPartyPlatform.gradescope)?.token,
      'gs-token-123',
    );
  });

  test('wrong master password does not restore', () async {
    final fx = await _Fixture.withSession();
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.egate,
        account: '13800000000',
        sid: '20240001',
        token: 'tgc-secret',
        raw: const {'tgc': 'tgc-value'},
        boundAt: DateTime.utc(2026),
      ),
    ]);
    await fx.sync.setupWithMasterPassword('right');

    final fx2 = await _Fixture.withSession(server: fx.server);
    final outcome = await fx2.sync.restoreWithMasterPassword('wrong');
    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('不正确'));
    expect(fx2.tpAuth.account(ThirdPartyPlatform.egate), isNull);
  });

  test('push writes current bindings; disable clears the cloud blob',
      () async {
    final fx = await _Fixture.withSession();
    await fx.sync.setupWithMasterPassword('pw');
    expect(fx.server.properties['techpie_sync'], isNotNull);

    // Add a binding then push.
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.hydro,
        account: 'user',
        token: 'hydro-sid=sig',
        boundAt: DateTime.utc(2026),
      ),
    ]);
    // The onBindingsChanged hook would fire pushIfDue in prod; call directly.
    await fx.sync.push();
    expect(fx.server.properties['techpie_sync'], isNotNull);

    // Disable wipes the cloud blob and clears the local key.
    final outcome = await fx.sync.disable();
    expect(outcome.ok, isTrue);
    expect(fx.server.properties['techpie_sync'], isNull);
    expect(fx.sync.hasLocalKey, isFalse);
    expect(fx.sync.enabled, isFalse);
  });

  test('pull throws NeedMasterPassword when no cached key', () async {
    final fx = await _Fixture.withSession();
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'a@b',
        token: 't',
        boundAt: DateTime.utc(2026),
      ),
    ]);
    await fx.sync.setupWithMasterPassword('pw');

    final fx2 = await _Fixture.withSession(server: fx.server);
    await fx2.storage.setSyncEnabled(true); // enabled but no key on this device
    await fx2.sync.loadCachedKey();
    expect(fx2.sync.hasLocalKey, isFalse);
    expect(
      () => fx2.sync.pull(),
      throwsA(isA<NeedMasterPassword>()),
    );
  });
}

// ---------------------------------------------------------------------------
// Test fixture: in-memory Casdoor stand-in + real services backed by it.
// ---------------------------------------------------------------------------

/// An in-memory stand-in for Casdoor's /api/get-account + /api/update-user.
/// Holds the user's `properties` map so writes are visible to subsequent reads.
/// Models Casdoor's real quirks: HTTP 200 for ALL outcomes (incl. authz denial),
/// success body `{status:ok,data:"Affected"|"Unaffected"}`, denial body
/// `{status:error,msg:"Unauthorized operation"}`, and `?id=<owner>/<name>` +
/// `?columns=properties` query params. When [enforceAuthz] is true (default),
/// an update-user call whose `id` query param does not match the body's
/// `owner/name` is denied — mirroring Casbin's self-update matcher.
class _FakeCasdoor {
  final Map<String, String> properties = {};
  bool enforceAuthz = true;

  http.Client toHttpClient() {
    return MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/get-account') {
        final body = jsonEncode({
          'status': 'ok',
          'data': {
            'owner': 'geekpie',
            'name': 'user',
            'id': 'geekpie/user',
            'properties': Map<String, String>.from(properties),
          },
        });
        return http.Response(body, 200);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/update-user') {
        final decoded = jsonDecode(request.body) as Map<String, dynamic>;
        // Casbin self-update authz: id query must match body owner/name.
        if (enforceAuthz) {
          final idQuery = request.url.queryParameters['id'] ?? '';
          final bodyId =
              '${decoded['owner'] ?? ''}/${decoded['name'] ?? ''}';
          if (idQuery != bodyId) {
            return http.Response(
              jsonEncode({
                'status': 'error',
                'msg': 'Unauthorized operation',
              }),
              200, // Casdoor returns 200 even on denial.
            );
          }
        }
        final props =
            (decoded['properties'] as Map?)?.cast<String, String>();
        if (props != null) {
          properties
            ..clear()
            ..addAll(props);
        }
        return http.Response(
          jsonEncode({'status': 'ok', 'data': 'Affected'}),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/api/auth/geekpie') {
        return http.Response(
          jsonEncode({'success': true, 'userId': 'user', 'userName': 'User'}),
          200,
        );
      }
      return http.Response('not found', 404);
    });
  }
}

class _Fixture {
  final StorageService storage;
  final AuthService auth;
  final ThirdPartyAuthService tpAuth;
  final SyncService sync;
  final _FakeCasdoor server;

  _Fixture(this.storage, this.auth, this.tpAuth, this.sync, this.server);

  static Future<_Fixture> withSession({_FakeCasdoor? server}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    await storage.saveSession(
      UserSession(
        userId: 'user',
        userName: 'User',
        schoolName: '上海科技大学',
        createdAt: DateTime.utc(2026),
        geekpieToken: 'fake-geekpie-jwt',
      ),
    );
    final srv = server ?? _FakeCasdoor();
    final logger = DebugLogger();
    final httpClient = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, httpClient, uniAuth);
    final tpAuth = ThirdPartyAuthService(storage, httpClient);
    final sync = SyncService(auth, tpAuth, storage, client: srv.toHttpClient());
    await auth.loadSession();
    await tpAuth.initialize();
    await sync.loadCachedKey();
    return _Fixture(storage, auth, tpAuth, sync, srv);
  }
}
