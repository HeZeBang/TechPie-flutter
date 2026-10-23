import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/genai/app/genai_runtime.dart';
import 'package:techpie/features/genai/application/campus_genai_session_issuer.dart';
import 'package:techpie/features/genai/application/genai_conversation_store.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import '../support/fakes.dart';

const _studentId = '20249999';
const _phone = '13800138000';
const _internalId = '00000000-0000-0000-0000-000000000001';

ThirdPartyAccount _binding({DateTime? boundAt}) => ThirdPartyAccount(
      platform: ThirdPartyPlatform.cpdaily,
      account: _phone,
      sid: _internalId,
      token: 'cpdaily-token-not-genai',
      boundAt: boundAt ?? DateTime(2026),
      raw: const {'tgc': 'existing-ids-tgc'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<
      ({
        GenAiRuntime runtime,
        ThirdPartyAuthService bindings,
        AuthService auth,
        ScriptedTransport transport,
        MemorySessionStore store,
      })> fixture({
    String username = _studentId,
    GenAiCampusExchange? exchange,
    http.Client? renewalClient,
    bool trustedIssuer = true,
  }) async {
    final storage = StorageService(await SharedPreferences.getInstance());
    final logging = LoggingHttpClient(
      DebugLogger(),
      inner: renewalClient ?? MockClient((_) async => http.Response('', 500)),
    );
    final auth = AuthService(storage, logging, UniAuthService());
    await storage.saveSession(
      UserSession(
        userId: 'geekpie-user',
        userName: 'Fixture',
        schoolName: 'Fixture',
        studentId: '20240001',
        createdAt: DateTime(2026),
      ),
    );
    await auth.loadSession();
    final bindings = ThirdPartyAuthService(storage, logging);
    await bindings.replaceAll([_binding()]);
    final transport = ScriptedTransport((request) async {
      if (request.uri.path.endsWith('/ai/aiModel/list')) {
        return response(
          json: {
            'success': true,
            'code': 200,
            'result': {'records': <Object>[]},
          },
        );
      }
      return profileResponse(username);
    });
    final store = MemorySessionStore();
    final runtime = GenAiRuntime(
      auth: auth,
      thirdPartyAuth: bindings,
      transport: transport,
      store: store,
      conversationStore: MemoryGenAiConversationStore(),
      issuer: trustedIssuer
          ? CampusGenAiSessionIssuer(
              thirdPartyAuth: bindings,
              exchange: exchange ??
                  (provider, _) async {
                    expect(provider.studentId, isEmpty);
                    expect(provider.cookies, contains('CASTGC='));
                    return const GenAiCredential(token: 'genai-token');
                  },
            )
          : CallbackIssuer(
              (_, __) async => const GenAiCredential(token: 'untrusted-token'),
            ),
    );
    addTearDown(() {
      runtime.dispose();
      bindings.dispose();
      auth.dispose();
      logging.close();
    });
    return (
      runtime: runtime,
      bindings: bindings,
      auth: auth,
      transport: transport,
      store: store,
    );
  }

  test('SMS binding resolves school identity through its IDS session',
      () async {
    final f = await fixture();
    expect(f.runtime.sessions.owner, isNull);
    expect(f.transport.requests, isEmpty);
    await f.runtime.workspace.connectUsing(f.runtime.connectUsingCampusSession);
    expect(f.runtime.workspace.loginFailure, isNull);
    expect(f.runtime.workspace.connected, isTrue);
    expect(f.runtime.sessions.owner?.studentId, _studentId);
    expect(f.runtime.sessions.session?.profile.username, _studentId);
    expect(f.store.writes, 1);
    expect(f.bindings.cpdailyBinding?.account, _phone);
    expect(f.bindings.cpdailyBinding?.sid, _internalId);
    expect(f.bindings.cpdailyBinding?.raw, {'tgc': 'existing-ids-tgc'});
    expect(f.auth.session?.studentId, '20240001');
    expect(
      f.transport.requests
          .every((r) => r.headers['X-Access-Token'] == 'genai-token'),
      isTrue,
    );
  });

  for (final discoveredId in [_studentId, '20241111']) {
    test(
        'SMS renewal identity $discoveredId must match the verified GenAI profile',
        () async {
      var exchanges = 0;
      var renewals = 0;
      final f = await fixture(
        renewalClient: MockClient((request) async {
          expect(request.url.path, '/api/auth/renew');
          renewals++;
          return http.Response(
            jsonEncode({
              'success': true,
              'tgc': 'renewed-ids-tgc',
              'sid': discoveredId,
            }),
            200,
          );
        }),
        exchange: (provider, _) async {
          if (++exchanges == 1) {
            expect(provider.studentId, isEmpty);
            throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
          }
          expect(provider.studentId, discoveredId);
          expect(provider.cookies, contains('CASTGC=renewed-ids-tgc'));
          return const GenAiCredential(token: 'genai-token');
        },
      );
      await f.runtime.workspace
          .connectUsing(f.runtime.connectUsingCampusSession);
      if (discoveredId == _studentId) {
        expect(f.runtime.workspace.loginFailure, isNull);
        expect(f.runtime.sessions.session?.profile.username, _studentId);
        expect(f.store.writes, 1);
      } else {
        expect(
          f.runtime.workspace.loginFailure,
          failure(GenAiFailureKind.identityMismatch),
        );
        expect(f.runtime.sessions.session, isNull);
        expect(f.store.writes, 0);
      }
      expect(f.runtime.sessions.owner?.studentId, discoveredId);
      expect(renewals, 1);
      expect(exchanges, 2);
    });
  }

  test('resolved identity survives IDS renewal and allows GenAI reconnect',
      () async {
    final f = await fixture();
    await f.runtime.connectUsingCampusSession();
    final owner = f.runtime.sessions.owner;
    await f.bindings.updateRaw(
      ThirdPartyPlatform.cpdaily,
      {'tgc': 'renewed-ids-tgc'},
    );
    expect(f.runtime.sessions.owner, owner);
    await f.runtime.sessions.disconnect();
    await f.runtime.connectUsingCampusSession();
    expect(f.runtime.sessions.session?.profile.username, _studentId);
    expect(f.store.writes, 2);
  });

  test('rebinding clears the resolved owner and old GenAI credential',
      () async {
    final f = await fixture();
    await f.runtime.connectUsingCampusSession();
    await f.bindings.replaceAll([_binding(boundAt: DateTime(2026, 2))]);
    expect(f.runtime.sessions.owner, isNull);
    expect(f.runtime.sessions.session, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(f.store.records, isEmpty);
    await expectLater(
      f.runtime.sessions.connect(const GenAiCredential(token: 'manual-token')),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
  });

  test('unbinding cancels identity resolution and rejects a late credential',
      () async {
    final result = Completer<GenAiCredential>();
    final started = Completer<void>();
    late GenAiCancellation cancellation;
    final f = await fixture(
      exchange: (_, operation) {
        cancellation = operation;
        started.complete();
        return result.future;
      },
    );
    final connection = f.runtime.connectUsingCampusSession();
    final assertion = expectLater(
      connection,
      throwsA(failure(GenAiFailureKind.accountChanged)),
    );
    await started.future;
    await f.bindings.unbind(ThirdPartyPlatform.cpdaily);
    await assertion;
    result.complete(const GenAiCredential(token: 'late-token'));
    await Future<void>.delayed(Duration.zero);
    expect(cancellation.isCancelled, isTrue);
    expect(f.runtime.sessions.owner, isNull);
    expect(f.transport.requests, isEmpty);
    expect(f.store.writes, 0);
  });

  for (final username in [_phone, _internalId, 'student@example.com']) {
    test('profile with non-school identity $username is rejected', () async {
      final f = await fixture(username: username);
      await f.runtime.workspace
          .connectUsing(f.runtime.connectUsingCampusSession);
      expect(
        f.runtime.workspace.loginFailure,
        failure(GenAiFailureKind.identityMismatch),
      );
      expect(f.runtime.sessions.owner, isNull);
      expect(f.store.writes, 0);
    });
  }

  test('unexpected IDS exchange failures become a redacted login error',
      () async {
    var attempts = 0;
    final f = await fixture(
      exchange: (_, __) async {
        if (++attempts == 1) {
          throw const FormatException('private IDS cookie value');
        }
        return const GenAiCredential(token: 'genai-token');
      },
    );
    await f.runtime.workspace.connectUsing(f.runtime.connectUsingCampusSession);
    expect(
      f.runtime.workspace.loginFailure,
      failure(GenAiFailureKind.transport),
    );
    expect(
      f.runtime.workspace.loginFailure.toString(),
      isNot(contains('private IDS cookie value')),
    );
    expect(f.runtime.sessions.owner, isNull);
    expect(f.runtime.sessions.session, isNull);
    expect(f.transport.requests, isEmpty);
    expect(f.store.writes, 0);
    expect(f.runtime.workspace.connecting, isFalse);
    await f.runtime.workspace.connectUsing(f.runtime.connectUsingCampusSession);
    expect(f.runtime.workspace.loginFailure, isNull);
    expect(f.runtime.sessions.session?.profile.username, _studentId);
    expect(attempts, 2);
    expect(f.store.writes, 1);
  });

  test('unknown campus identity cannot be bootstrapped by a generic issuer',
      () async {
    final f = await fixture(trustedIssuer: false);
    await expectLater(
      f.runtime.connectUsingCampusSession(),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(f.transport.requests, isEmpty);
    expect(f.store.writes, 0);
  });
}
