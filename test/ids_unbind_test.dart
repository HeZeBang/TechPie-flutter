import 'dart:async';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/ids/ids_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import 'support/fake_ids_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fail in [false, true]) {
    test('local deletion is complete before school unbind ${fail ? "fails" : "succeeds"}',
        () async {
      final fixture = await _Fixture.create();
      final result = fixture.auth
          .unbindIdsWithRemote(promptVerification: (_, __, {required refresh}) async => null);
      await fixture.client.started.future;
      expect(fixture.auth.idsBinding!.credential, isNull);
      expect(fixture.auth.idsAccount, isNull);
      expect(
          IdsSyncBinding.fromAccount(
                  await fixture.storage.loadThirdPartyAccount(ThirdPartyPlatform.ids),)
              ?.credential,
          isNull,);
      expect(fixture.client.key!.credentialId, 'synthetic-A');
      if (fail) {
        fixture.client.done.completeError(const IdsException('synthetic failure'));
      } else {
        fixture.client.done.complete();
      }
      expect(await result, !fail);
      expect(fixture.auth.idsBinding!.credential, isNull);
    });
  }

  test('finishing an old school unbind does not remove a newer local Passkey', () async {
    final fixture = await _Fixture.create();
    final result = fixture.auth
        .unbindIdsWithRemote(promptVerification: (_, __, {required refresh}) async => null);
    await fixture.client.started.future;
    await fixture.auth.bindIds(
        account: 'B',
        password: 'synthetic-password',
        promptCaptcha: (_, __, {required refresh}) async => null,);
    fixture.client.done.complete();
    expect(await result, true);
    expect(fixture.client.key!.username, 'A');
    expect(fixture.auth.idsBinding!.credential!.username, 'B');
    final stored = (await fixture.storage.loadThirdPartyAccount(ThirdPartyPlatform.ids))!;
    expect(IdsSyncBinding.fromAccount(stored)!.credential!.username, 'B');
    expect(stored.password, isNull);
    expect(stored.toJson().containsKey('password'), false);
  });
}

class _RemoteIds extends FakeIdsClient {
  final started = Completer<void>();
  final done = Completer<void>();
  IdsPasskey? key;
  @override
  Future<void> revoke(IdsPasskey key, {required IdsVerificationPrompt promptVerification}) {
    this.key = key;
    started.complete();
    return done.future;
  }
}

class _Fixture {
  _Fixture(this.auth, this.storage, this.client);
  final ThirdPartyAuthService auth;
  final StorageService storage;
  final _RemoteIds client;
  static Future<_Fixture> create() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final client = _RemoteIds();
    final auth = ThirdPartyAuthService(storage, http, idsClient: client);
    await auth.initialize();
    await auth.applyIdsSyncBinding(
      IdsSyncBinding(
        credential: FakeIdsClient.key('A'),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        deviceId: 'fixture',
      ),
    );
    return _Fixture(auth, storage, client);
  }
}
