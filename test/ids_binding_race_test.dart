import 'dart:async';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  test('a late A registration cannot replace a completed B binding or its candidate', () async {
    final fixture = await _Fixture.create();
    final first = fixture.bind('A');
    final rejected = expectLater(first, throwsA(isA<IdsException>()));
    await fixture.client.started('A');
    await fixture.client.pending['A']!.save(FakeIdsClient.key('A'));
    final second = fixture.bind('B');
    await fixture.client.started('B');
    await fixture.client.pending['B']!.save(FakeIdsClient.key('B'));
    fixture.client.finish('B');
    await second;
    await expectLater(
      fixture.client.pending['A']!.save(FakeIdsClient.key('A')),
      throwsA(isA<IdsException>()),
    );
    fixture.client.finish('A');
    await rejected;
    expect(fixture.auth.idsBinding!.credential!.username, 'B');
    expect(
        IdsSyncBinding.fromAccount(
                await fixture.storage.loadThirdPartyAccount(ThirdPartyPlatform.ids),)!
            .credential!
            .username,
        'B',);
    expect(fixture.auth.idsAccount!.account, 'B');
    expect(await fixture.storage.loadIdsCandidate(), isNull);
  });

  for (final action in ['unbind', 'clearAll', 'sync-delete']) {
    test('$action invalidates an in-flight registration and its candidate writes', () async {
      final fixture = await _Fixture.create();
      final pending = fixture.bind('A');
      final rejected = expectLater(pending, throwsA(isA<IdsException>()));
      await fixture.client.started('A');
      if (action == 'unbind') {
        await fixture.auth.unbind(ThirdPartyPlatform.ids);
      } else if (action == 'clearAll') {
        await fixture.auth.clearAll();
      } else {
        await fixture.auth.applyIdsSyncBinding(
          IdsSyncBinding(credential: null, updatedAt: DateTime.now(), deviceId: 'other'),
        );
      }
      await expectLater(
        fixture.client.pending['A']!.save(FakeIdsClient.key('A')),
        throwsA(isA<IdsException>()),
      );
      fixture.client.finish('A');
      await rejected;
      expect(fixture.auth.idsBinding?.credential, isNull);
      expect(
          IdsSyncBinding.fromAccount(
                  await fixture.storage.loadThirdPartyAccount(ThirdPartyPlatform.ids),)
              ?.credential,
          isNull,);
      expect(fixture.auth.idsAccount, isNull);
      expect(await fixture.storage.loadIdsCandidate(), isNull);
    });
  }

  for (final replace in [false, true]) {
    test('late CAS cannot restore cookies while ${replace ? "replacing" : "unbinding"} the root',
        () async {
      final fixture = await _Fixture.create();
      await fixture.bindNow('A');
      final mint = fixture.auth.eamsNode.renew();
      await fixture.client.mintStarted.future;
      fixture.storage.pauseNextClear = true;
      final change = replace
          ? fixture.auth.applyIdsSyncBinding(IdsSyncBinding(
              credential: FakeIdsClient.key('B'),
              updatedAt: DateTime.now().add(const Duration(seconds: 1)),
              deviceId: 'other',),)
          : fixture.auth.unbind(ThirdPartyPlatform.ids);
      await fixture.storage.clearStarted.future;
      final ownerWhileClearing = fixture.auth.idsAccount?.account;
      fixture.client.minted.complete('JSESSIONID=old-A');
      await Future<void>.delayed(Duration.zero);
      fixture.storage.releaseClear.complete();
      await change;
      expect(await mint, false);
      expect(ownerWhileClearing, replace ? 'B' : null);
      expect(fixture.auth.eamsNode.cookieProvider, isNull);
      expect(await fixture.storage.loadDerivedCookie('eams'), isNull);
    });
  }

  test('an old child cookie storage write completes before the root deletion', () async {
    final fixture = await _Fixture.create();
    await fixture.bindNow('A');
    fixture.storage.pauseNextDerivedWrite = true;
    final mint = fixture.auth.eamsNode.renew();
    await fixture.client.mintStarted.future;
    fixture.client.minted.complete('JSESSIONID=old-A');
    await fixture.storage.derivedWriteStarted.future;
    final removal = fixture.auth.unbind(ThirdPartyPlatform.ids);
    fixture.storage.releaseDerivedWrite.complete();
    await removal;
    await mint;
    expect(fixture.auth.eamsNode.cookieProvider, isNull);
    expect(await fixture.storage.loadDerivedCookie('eams'), isNull);
  });

  test('a late silent probe cannot restore an unbound child session', () async {
    final probeStarted = Completer<void>();
    final response = Completer<http.Response>();
    final fixture = await _Fixture.create(
      campusHttp: MockClient((_) {
        probeStarted.complete();
        return response.future;
      }),
    );
    await fixture.bindNow('A');
    final mint = fixture.auth.eamsNode.renew();
    await fixture.client.mintStarted.future;
    fixture.client.minted.complete('JSESSIONID=old-A');
    await probeStarted.future;
    await fixture.auth.unbind(ThirdPartyPlatform.ids);
    response.complete(http.Response('姓名：</td><td>Synthetic Old User</td>', 200,
        headers: {'content-type': 'text/html; charset=utf-8'},),);
    expect(await mint, false);
    expect(fixture.auth.eamsNode.cookieProvider, isNull);
    expect(await fixture.storage.loadDerivedCookie('eams'), isNull);
  });

  test('unbind during secure-storage commit wins after the earlier commit finishes', () async {
    final fixture = await _Fixture.create(pauseCommit: true);
    final pending = fixture.bind('A');
    final rejected = expectLater(pending, throwsA(isA<IdsException>()));
    await fixture.client.started('A');
    fixture.client.finish('A');
    await fixture.storage.commitStarted.future;
    final removal = fixture.auth.unbind(ThirdPartyPlatform.ids);
    fixture.storage.releaseCommit.complete();
    await removal;
    await rejected;
    expect(
        IdsSyncBinding.fromAccount(
                await fixture.storage.loadThirdPartyAccount(ThirdPartyPlatform.ids),)
            ?.credential,
        isNull,);
    expect(await fixture.storage.loadThirdPartyAccount(ThirdPartyPlatform.ids), isNull);
    expect(fixture.auth.idsAccount, isNull);
  });
}

class _Pending {
  _Pending(this.save);
  final Future<void> Function(IdsPasskey) save;
  final result = Completer<({IdsPasskey credential, IdsSession session})>();
}

class _ControlledIds extends IdsClient {
  final mintStarted = Completer<void>();
  final minted = Completer<String>();
  @override
  Future<String> mintCookie(String id, Map<String, dynamic> root) {
    mintStarted.complete();
    return minted.future;
  }

  final pending = <String, _Pending>{};
  final _started = <String, Completer<void>>{};
  Future<void> started(String account) => (_started[account] ??= Completer<void>()).future;
  void finish(String account) => pending[account]!.result.complete(
        (
          credential: FakeIdsClient.key(account),
          session: IdsSession(account, {'tgc': 'synthetic-$account'}),
        ),
      );
  @override
  Future<({IdsPasskey credential, IdsSession session})> register(
    String username,
    String password, {
    required IdsCaptchaPrompt promptCaptcha,
    required Future<void> Function(IdsPasskey) saveCandidate,
  }) {
    final operation = pending[username] = _Pending(saveCandidate);
    (_started[username] ??= Completer<void>()).complete();
    return operation.result.future;
  }
}

class _Storage extends StorageService {
  _Storage(super.prefs, this.pauseCommit);
  final bool pauseCommit;
  bool pauseNextClear = false;
  final clearStarted = Completer<void>();
  final releaseClear = Completer<void>();
  bool pauseNextDerivedWrite = false;
  final derivedWriteStarted = Completer<void>();
  final releaseDerivedWrite = Completer<void>();
  @override
  Future<void> clearDerivedCookie(String nodeId) async {
    if (pauseNextClear && nodeId == 'eams') {
      pauseNextClear = false;
      clearStarted.complete();
      await releaseClear.future;
    }
    await super.clearDerivedCookie(nodeId);
  }

  @override
  Future<void> saveDerivedCookie(String nodeId, String cookie) async {
    if (pauseNextDerivedWrite && nodeId == 'eams') {
      pauseNextDerivedWrite = false;
      derivedWriteStarted.complete();
      await releaseDerivedWrite.future;
    }
    await super.saveDerivedCookie(nodeId, cookie);
  }

  final commitStarted = Completer<void>();
  final releaseCommit = Completer<void>();
  @override
  Future<void> saveThirdPartyAccount(ThirdPartyAccount account) async {
    if (pauseCommit &&
        account.platform == ThirdPartyPlatform.ids &&
        account.raw['authMethod'] == 'passkey' &&
        !commitStarted.isCompleted) {
      commitStarted.complete();
      await releaseCommit.future;
    }
    await super.saveThirdPartyAccount(account);
  }
}

class _Fixture {
  _Fixture(this.auth, this.storage, this.client);
  final ThirdPartyAuthService auth;
  final _Storage storage;
  final _ControlledIds client;
  Future<ThirdPartyAccount> bind(String account) => auth.bindIds(
        account: account,
        password: 'synthetic-password',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
  Future<void> bindNow(String account) async {
    final result = bind(account);
    await client.started(account);
    client.finish(account);
    await result;
  }

  static Future<_Fixture> create({bool pauseCommit = false, http.Client? campusHttp}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = _Storage(await SharedPreferences.getInstance(), pauseCommit);
    final client = _ControlledIds();
    final auth = ThirdPartyAuthService(
        storage,
        LoggingHttpClient(DebugLogger(),
            inner: campusHttp ?? MockClient((_) async => http.Response('', 404)),),
        idsClient: client,);
    await auth.initialize();
    return _Fixture(auth, storage, client);
  }
}
