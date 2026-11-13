import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/genai/application/campus_genai_session_issuer.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<ThirdPartyAuthService> bindings({
    String tgc = 'existing-tgc',
    http.Client? client,
  }) async {
    final service = ThirdPartyAuthService(
      StorageService(await SharedPreferences.getInstance()),
      LoggingHttpClient(
        DebugLogger(),
        inner: client ?? MockClient((_) async => http.Response('', 500)),
      ),
    );
    await service.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: ownerA.studentId,
        token: 'cpdaily-token-not-genai',
        boundAt: DateTime(2026),
        raw: {
          'tgc': tgc,
          'cookies': 'ids-session=existing',
          'sessionToken': 'session',
        },
      ),
    ]);
    addTearDown(service.dispose);
    return service;
  }

  test(
      'uses the current IDS cookie provider without asking for another identity',
      () async {
    final service = await bindings();
    final issuer = CampusGenAiSessionIssuer(
      thirdPartyAuth: service,
      exchange: (provider, _) async {
        expect(provider.cookies, contains('CASTGC=existing-tgc'));
        expect(provider.domain, 'ids.shanghaitech.edu.cn');
        expect(provider.studentId, ownerA.studentId);
        return const GenAiCredential(token: 'separate-genai-token');
      },
    );
    expect(
      (await issuer.issue(ownerA, GenAiCancellation())).token,
      'separate-genai-token',
    );
  });

  test('an IDS rejection reuses the session tree one-renew retry budget',
      () async {
    var renews = 0;
    final service = await bindings(
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/renew');
        renews++;
        return http.Response(
          jsonEncode({'success': true, 'tgc': 'renewed-tgc'}),
          200,
        );
      }),
    );
    var exchanges = 0;
    final issuer = CampusGenAiSessionIssuer(
      thirdPartyAuth: service,
      exchange: (provider, _) async {
        exchanges++;
        if (exchanges == 1) {
          throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
        }
        expect(provider.cookies, contains('CASTGC=renewed-tgc'));
        return const GenAiCredential(token: 'genai-token');
      },
    );
    await issuer.issue(ownerA, GenAiCancellation());
    expect(renews, 1);
    expect(exchanges, 2);
  });

  test(
      'missing CASTGC requires the existing IDS binding instead of inventing a login',
      () async {
    final service = await bindings(tgc: '');
    final issuer = CampusGenAiSessionIssuer(
      thirdPartyAuth: service,
      exchange: (_, __) async => throw StateError('exchange must not run'),
    );
    await expectLater(
      issuer.issue(ownerA, GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
  });

  test('a different campus identity cannot be exchanged', () async {
    final service = await bindings();
    final issuer = CampusGenAiSessionIssuer(
      thirdPartyAuth: service,
      exchange: (_, __) async => throw StateError('exchange must not run'),
    );
    await expectLater(
      issuer.issue(ownerB, GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.identityMismatch)),
    );
  });

  test('network failures do not spend an IDS renewal', () async {
    final service = await bindings(
      client: MockClient((_) async => throw StateError('must not renew')),
    );
    final issuer = CampusGenAiSessionIssuer(
      thirdPartyAuth: service,
      exchange: (_, __) async =>
          throw const GenAiFailure(GenAiFailureKind.transport),
    );
    await expectLater(
      issuer.issue(ownerA, GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.transport)),
    );
  });

  test('cancelling an in-flight exchange rejects the late credential',
      () async {
    final service = await bindings();
    final result = Completer<GenAiCredential>();
    final scope = GenAiCancellation();
    final issuer = CampusGenAiSessionIssuer(
      thirdPartyAuth: service,
      exchange: (_, __) => result.future,
    );
    final future = issuer.issue(ownerA, scope);
    await Future<void>.delayed(Duration.zero);
    scope.cancel();
    await expectLater(future, throwsA(failure(GenAiFailureKind.cancelled)));
    result.complete(const GenAiCredential(token: 'late-token'));
  });
}
