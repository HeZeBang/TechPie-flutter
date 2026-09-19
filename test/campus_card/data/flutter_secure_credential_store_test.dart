import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const cookieKey = 'geekpay.auth.session_cookie';
  const openIdKey = 'geekpay.auth.openid';
  const journalKey = 'geekpay.secure.journal';
  late Map<String, String> values;
  Future<void> Function(String key)? beforeWrite;

  setUp(() {
    values = {};
    beforeWrite = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final key = arguments['key']! as String;
      switch (call.method) {
        case 'read':
          return values[key];
        case 'write':
          await beforeWrite?.call(key);
          values[key] = arguments['value']! as String;
          return null;
        case 'delete':
          values.remove(key);
          return null;
        default:
          throw UnimplementedError(call.method);
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a failed credential update cannot expose mixed account values',
      () async {
    values.addAll(
      {cookieKey: 'cookie-a', openIdKey: 'account-a', 'host.sso': 'keep'},
    );
    beforeWrite = (key) async {
      if (key == openIdKey) {
        throw PlatformException(code: 'synthetic-write-failure');
      }
    };
    final store = FlutterSecureCredentialStore();

    await expectLater(
      store.replaceAtomically({cookieKey: 'cookie-b', openIdKey: 'account-b'}),
      throwsA(isA<AppFailure>()),
    );

    beforeWrite = null;
    expect(await store.read(cookieKey), 'cookie-a');
    expect(await store.read(openIdKey), 'account-a');
    expect(values['host.sso'], 'keep');
    expect(values.containsKey(journalKey), isFalse);
  });

  test('credential reads wait for an in-progress account update', () async {
    values.addAll({cookieKey: 'cookie-a', openIdKey: 'account-a'});
    final paused = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    beforeWrite = (key) async {
      if (key == openIdKey) {
        paused.complete();
        await release.future;
      }
    };
    final store = FlutterSecureCredentialStore();
    final update = store
        .replaceAtomically({cookieKey: 'cookie-b', openIdKey: 'account-b'});
    await paused.future;
    var readCompleted = false;
    final read = store.read(cookieKey).then((value) {
      readCompleted = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(readCompleted, isFalse);
    release.complete();
    await update;
    expect(await read, 'cookie-b');
    expect(await store.read(openIdKey), 'account-b');
  });

  test('legacy interrupted updates discard only their affected credentials',
      () async {
    values.addAll({
      cookieKey: 'cookie-b',
      openIdKey: 'account-a',
      'host.sso': 'keep',
      journalKey: jsonEncode({
        'id': 'interrupted',
        'keys': [cookieKey, openIdKey],
      }),
    });
    final store = FlutterSecureCredentialStore();

    expect(await store.read(cookieKey), isNull);
    expect(await store.read(openIdKey), isNull);
    expect(values['host.sso'], 'keep');
  });
  test(
      'restart restores the last complete account after an interrupted refresh',
      () async {
    values.addAll({
      cookieKey: 'cookie-new',
      openIdKey: 'account-a',
      'host.sso': 'keep',
      journalKey: jsonEncode({
        'version': 1,
        'before': {
          cookieKey: 'cookie-old',
          openIdKey: 'account-a',
        },
      }),
    });
    final store = FlutterSecureCredentialStore();
    expect(await store.read(cookieKey), 'cookie-old');
    expect(await store.read(openIdKey), 'account-a');
    expect(values['host.sso'], 'keep');
    expect(values.containsKey(journalKey), isFalse);
  });

  test('an invalid journal cannot delete the host account', () async {
    values.addAll({
      'host.sso': 'keep',
      journalKey: jsonEncode({
        'keys': ['host.sso'],
      }),
    });
    await expectLater(
      FlutterSecureCredentialStore().read(cookieKey),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'SECURE_STORAGE_INVALID_JOURNAL',
        ),
      ),
    );
    expect(values['host.sso'], 'keep');
  });
}
