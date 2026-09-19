import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/models/ecard_sync_binding.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_crypto.dart';
import 'package:techpie/services/sync_envelope.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  test('encrypted cloud backup restores eCard and propagates its deletion', () async {
    const openId = 'SYNTHETIC_OPENID_CLOUD_123456';
    final firstStore = _EcardStore(EcardSyncBinding(openId: openId, channel: EcardOpenIdChannel.alipay,
      updatedAt: DateTime.utc(2026), deviceId: 'first',),);
    final first = await _Fixture.withSession(ecard: firstStore);
    expect((await first.sync.setupWithMasterPassword('synthetic-password')).ok, isTrue);
    expect(first.server.properties['techpie_sync'], isNot(contains(openId)));
    final secondStore = _EcardStore(null);
    final second = await _Fixture.withSession(server: first.server, ecard: secondStore);
    expect((await second.sync.restoreWithMasterPassword('synthetic-password')).ok, isTrue);
    expect(secondStore.value!.openId, openId);
    expect(secondStore.value!.channel, EcardOpenIdChannel.alipay);
    secondStore.value = EcardSyncBinding(openId: null,
      updatedAt: DateTime.utc(2026, 1, 2), deviceId: 'second',);
    await second.sync.push();
    // An older offline device must not resurrect a remote deletion by pushing.
    await first.sync.push();
    await first.sync.pull();
    expect(firstStore.value!.openId, isNull);
  });

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
        platform: ThirdPartyPlatform.cpdaily,
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
    expect(fx2.tpAuth.account(ThirdPartyPlatform.cpdaily), isNull);
  });

  test('setup replaces an existing cloud backup only when confirmed', () async {
    // Device A set up first: its backup is the cloud's only copy.
    final fx = await _Fixture.withSession();
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'a@b.edu',
        token: 'gs-token-a',
        boundAt: DateTime.utc(2026),
      ),
    ]);
    await fx.sync.setupWithMasterPassword('pw-a');

    // Device B is not syncing: an unconfirmed setup must not touch A's backup.
    final fx2 = await _Fixture.withSession(server: fx.server);
    await fx2.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.hydro,
        account: 'user-b',
        token: 'hydro-sid=b',
        boundAt: DateTime.utc(2026, 2),
      ),
    ]);
    final refused = await fx2.sync.setupWithMasterPassword('pw-b');
    expect(refused.ok, isFalse, reason: refused.message);
    expect(refused.message, contains('已存在备份'));

    final overwritten = await fx2.sync.setupWithMasterPassword(
      'pw-b',
      overwriteRemote: true,
    );
    expect(overwritten.ok, isTrue, reason: overwritten.message);
    expect(overwritten.message, contains('覆盖'));

    // The blob now decrypts with B's password and carries B's binding, while
    // A's password no longer opens it.
    final fx3 = await _Fixture.withSession(server: fx.server);
    final restored = await fx3.sync.restoreWithMasterPassword('pw-b');
    expect(restored.ok, isTrue, reason: restored.message);
    expect(fx3.tpAuth.account(ThirdPartyPlatform.hydro)?.token, 'hydro-sid=b');

    final stale = await _Fixture.withSession(server: fx.server);
    final withOldPassword = await stale.sync.restoreWithMasterPassword('pw-a');
    expect(withOldPassword.ok, isFalse);
    expect(withOldPassword.message, contains('不正确'));
  });

  test('a legacy cloud blob is migrated and rewritten in the current schema',
      () async {
    // A device running an older build wrote the pre-tombstone (v1) envelope.
    final legacyPlain = jsonEncode({
      'v': 1,
      'accounts': [
        ThirdPartyAccount(
          platform: ThirdPartyPlatform.hydro,
          account: 'user',
          token: 'hydro-sid=legacy',
          boundAt: DateTime.utc(2026),
        ).toJson(),
      ],
    });
    final legacyBlob = await SyncCrypto.encryptWithSalt(legacyPlain, 'pw');

    final fx = await _Fixture.withSession();
    fx.server.properties['techpie_sync'] = legacyBlob;

    // Restoring reads the legacy shape — no tombstones, no updatedAt/deviceId.
    final restored = await fx.sync.restoreWithMasterPassword('pw');
    expect(restored.ok, isTrue, reason: restored.message);
    expect(
      fx.tpAuth.account(ThirdPartyPlatform.hydro)?.token,
      'hydro-sid=legacy',
    );

    // …and the cloud is rewritten in this build's schema, tombstones included,
    // so no later read has to translate it again.
    Future<Map<String, dynamic>> storedEnvelope() async {
      final plain = await SyncCrypto.decryptWithSalt(
        fx.server.properties['techpie_sync']!,
        'pw',
      );
      return jsonDecode(plain!) as Map<String, dynamic>;
    }

    final rewritten = await storedEnvelope();
    expect(rewritten['v'], SyncSchema.current);
    expect(rewritten, contains('tombstones'));

    await fx.sync.pull();
    expect((await storedEnvelope())['v'], SyncSchema.current);
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
  // -- LWW merge behavior (the bug these guard against) ----------------------

  test(
      'pull does NOT overwrite a locally-newer binding with an older cloud copy',
      () async {
    // Device A: set up sync with a gradescope binding (old updatedAt).
    final fx = await _Fixture.withSession();
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'a@b',
        token: 'cloud-old',
        boundAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await fx.sync.setupWithMasterPassword('pw');

    // Device B: restore, then locally rebind a NEWER token.
    final fx2 = await _Fixture.withSession(server: fx.server);
    await fx2.sync.restoreWithMasterPassword('pw');
    // Bump the local binding's updatedAt to "now" via the real bind path.
    await fx2.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'a@b',
        token: 'local-new',
        boundAt: DateTime.utc(2026, 1, 10),
        updatedAt: DateTime.utc(2026, 1, 10),
        deviceId: 'devB',
      ),
    ]);
    // Manually stamp deviceId on device 2 so the touch helper works. The
    // fixture loads deviceId lazily; ensureDeviceId already ran in init.

    // Pull from cloud (which still has 'cloud-old'). The merge must keep
    // 'local-new' because its updatedAt is newer.
    await fx2.sync.pull();
    expect(
      fx2.tpAuth.account(ThirdPartyPlatform.gradescope)?.token,
      'local-new',
      reason: 'a newer local binding must survive a pull of older cloud data',
    );
  });

  test(
      'a deletion (tombstone) on device A is not resurrected when device B pulls',
      () async {
    // Device A: bind gradescope, set up sync.
    final fx = await _Fixture.withSession();
    await fx.tpAuth.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'a@b',
        token: 't',
        boundAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await fx.sync.setupWithMasterPassword('pw');

    // Device A: unbind gradescope. This records a tombstone + force-pushes.
    await fx.tpAuth.unbind(ThirdPartyPlatform.gradescope);
    // The push the unbind triggers is deliberately fire-and-forget, so wait for
    // the cloud to hold what this test is about (a tombstone, no account).
    await fx.sync.push();
    // Cloud blob now carries a tombstone, no gradescope account.

    // Device B: restore (gets the post-deletion state) — should have no
    // gradescope binding.
    final fx2 = await _Fixture.withSession(server: fx.server);
    await fx2.sync.restoreWithMasterPassword('pw');
    expect(
      fx2.tpAuth.account(ThirdPartyPlatform.gradescope),
      isNull,
      reason: 'tombstone on device A must remove the binding on device B',
    );
  });
  test('a push keeps what a newer build wrote in the cloud', () async {
    final ecard = _EcardStore(null);
    final fx = await _Fixture.withSession(ecard: ecard);
    // What a newer build left behind: the eCard login parameter plus a field
    // this build has never heard of.
    const futureField = {'accountList': ['one', 'two']};
    final seeded = SyncEnvelope(
      v: 3,
      accounts: const [],
      tombstones: const [],
      ecard: EcardSyncBinding(
        openId: 'SYNTHETIC_OPENID_0001',
        updatedAt: DateTime.utc(2026),
        deviceId: 'newer-device',
      ),
      unknown: const {'futureField': futureField},
    ).encode();
    fx.server.properties['techpie_sync'] =
        await SyncCrypto.encryptWithSalt(seeded, 'pw');

    // This device restores (adopting the binding) and then pushes its own
    // state back.
    final outcome = await fx.sync.restoreWithMasterPassword('pw');
    expect(outcome.ok, isTrue);
    expect(ecard.value?.openId, 'SYNTHETIC_OPENID_0001');
    await fx.sync.push();

    final blob = fx.server.properties['techpie_sync']!;
    final plain = await SyncCrypto.decryptWithSalt(blob, 'pw');
    expect(plain, isNotNull);
    final written = jsonDecode(plain!) as Map<String, dynamic>;
    expect(
      written['futureField'],
      futureField,
      reason: 'a field this build cannot read must survive its push',
    );
    expect(written['v'], SyncSchema.current);
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

  static Future<_Fixture> withSession({_FakeCasdoor? server, EcardSyncStore? ecard}) async {
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
    final sync = SyncService(auth, tpAuth, storage, client: srv.toHttpClient(), ecard: ecard);
    // Mirror main.dart wiring so tombstones are recorded + pushes fire.
    tpAuth.onBindingsChanged = ({force = false}) {
      return force ? sync.forcePush() : sync.pushIfDue();
    };
    tpAuth.onUnbind = sync.recordTombstone;
    await auth.loadSession();
    await tpAuth.initialize();
    await sync.loadCachedKey();
    return _Fixture(storage, auth, tpAuth, sync, srv);
  }
}

class _EcardStore implements EcardSyncStore {
  _EcardStore(this.value);
  EcardSyncBinding? value;
  @override Future<EcardSyncBinding?> readSyncBinding() async => value;
  @override Future<void> applySyncBinding(EcardSyncBinding? binding) async {
    value = value?.merge(binding) ?? binding;
  }
}
