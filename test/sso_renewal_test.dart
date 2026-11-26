import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

class _FailingSaveStorage extends StorageService {
  _FailingSaveStorage(super.prefs);

  @override
  Future<void> saveSession(UserSession session) {
    throw PlatformException(
      code: 'KEYCHAIN_LOCKED',
      message: 'Failed to store token ${session.geekpieRefreshToken}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A Casdoor access token response as this instance actually answers it: the
  // lifetime is `expires_in` seconds, and there is no `expires_at` field.
  final now = DateTime.utc(2026, 9, 20, 12);

  Future<({StorageService storage, LoggingHttpClient httpClient, DebugLogger logger})>
      buildHarness({
    UserSession? session,
    bool failSaveSession = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final seedStorage = StorageService(prefs);
    if (session != null) {
      await seedStorage.saveSession(session);
    }
    final storage = failSaveSession ? _FailingSaveStorage(prefs) : seedStorage;
    final logger = DebugLogger()..enabled = true;
    final httpClient = LoggingHttpClient(logger);
    return (storage: storage, httpClient: httpClient, logger: logger);
  }

  UserSession expiredSession({String? refreshToken = 'rt-secret-value-123'}) =>
      UserSession(
        userId: 'u-1',
        userName: 'Alice',
        schoolName: '上海科技大学',
        createdAt: DateTime.utc(2026, 9, 1),
        geekpieToken: 'at-old-secret-456',
        geekpieExpiresAt:
            DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
        geekpieRefreshToken: refreshToken,
      );

  group('reading the expiry out of a token response', () {
    test('expires_in becomes an absolute time', () {
      final expiry = UniAuthService.expiryFromTokenResponse(
        const {'expires_in': 604800},
        now,
      );

      expect(DateTime.parse(expiry!), now.add(const Duration(days: 7)));
    });

    test('a response without expires_in falls back to expires_at', () {
      expect(
        UniAuthService.expiryFromTokenResponse(
          const {'expires_at': '2026-10-01T00:00:00Z'},
          now,
        ),
        '2026-10-01T00:00:00Z',
      );
      expect(UniAuthService.expiryFromTokenResponse(const {}, now), isNull);
      expect(
        UniAuthService.expiryFromTokenResponse(const {'expires_in': '0'}, now),
        isNull,
      );
    });
  });

  group('when a refresh token is worth spending', () {
    test('an expiry that cannot be read renews', () {
      expect(
        AuthService.needsRenewal(null, now, AuthService.renewWindow),
        isTrue,
      );
      expect(
        AuthService.needsRenewal('not a date', now, AuthService.renewWindow),
        isTrue,
      );
    });

    test('a token expiring inside the window renews', () {
      expect(
        AuthService.needsRenewal(
          now.add(const Duration(hours: 6)).toIso8601String(),
          now,
          AuthService.renewWindow,
        ),
        isTrue,
      );
    });

    test('the seven day token this instance issues is left alone', () {
      expect(
        AuthService.needsRenewal(
          now.add(const Duration(days: 7)).toIso8601String(),
          now,
          AuthService.renewWindow,
        ),
        isFalse,
      );
    });
  });

  group('UniAuthService.parseRefreshResponse classification', () {
    test('rotates refresh token when non-empty and preserves fallback when empty', () {
      final rotated = UniAuthService.parseRefreshResponse(
        http.Response(
          jsonEncode({
            'access_token': 'new-at',
            'refresh_token': 'new-rt',
            'expires_in': 3600,
          }),
          200,
        ),
        fallbackRefreshToken: 'old-rt',
        now: now,
      );
      expect(rotated.accessToken, 'new-at');
      expect(rotated.refreshToken, 'new-rt');
      expect(DateTime.parse(rotated.expiresAt!), now.add(const Duration(hours: 1)));

      final preserved = UniAuthService.parseRefreshResponse(
        http.Response(
          jsonEncode({
            'access_token': 'new-at-2',
            'refresh_token': '',
            'expires_in': 3600,
          }),
          200,
        ),
        fallbackRefreshToken: 'old-rt',
        now: now,
      );
      expect(preserved.refreshToken, 'old-rt');
    });

    test('classifies 400/401/200 invalid_grant and invalid_token as invalidGrant', () {
      for (final (status, errorCode) in const [
        (400, 'invalid_grant'),
        (401, 'invalid_token'),
        (200, 'invalid_grant'),
      ]) {
        expect(
          () => UniAuthService.parseRefreshResponse(
            http.Response(
              jsonEncode({
                'error': errorCode,
                'error_description': 'refresh token is invalid or revoked',
              }),
              status,
            ),
            fallbackRefreshToken: 'old-rt',
            now: now,
          ),
          throwsA(
            isA<SsoRefreshException>()
                .having((e) => e.kind, 'kind', SsoRefreshErrorKind.invalidGrant)
                .having((e) => e.isInvalidGrant, 'isInvalidGrant', isTrue)
                .having((e) => e.statusCode, 'statusCode', status)
                .having((e) => e.oauthError, 'oauthError', errorCode),
          ),
        );
      }
    });

    test('classifies 5xx, 429, captive portal HTML, and temporary OAuth errors as transient', () {
      final cases = <http.Response>[
        http.Response('<html>502 Bad Gateway</html>', 502),
        http.Response(jsonEncode({'error': 'server_error'}), 500),
        // Even if a 5xx payload mentions invalid_grant, a 5xx is never a user logout.
        http.Response(jsonEncode({'error': 'invalid_grant'}), 503),
        http.Response('Too Many Requests', 429),
        http.Response('<html>Captive Portal Login</html>', 200),
        http.Response(
          jsonEncode({'error': 'temporarily_unavailable'}),
          400,
        ),
      ];

      for (final resp in cases) {
        expect(
          () => UniAuthService.parseRefreshResponse(
            resp,
            fallbackRefreshToken: 'old-rt',
            now: now,
          ),
          throwsA(
            isA<SsoRefreshException>()
                .having((e) => e.kind, 'kind', SsoRefreshErrorKind.transient)
                .having((e) => e.isInvalidGrant, 'isInvalidGrant', isFalse)
                .having((e) => e.statusCode, 'statusCode', resp.statusCode),
          ),
        );
      }
    });
  });

  group('AuthService.tryRenewSession outcomes and diagnostics', () {
    test('returns unavailable when logged out or missing refresh token', () async {
      final loggedOut = await buildHarness();
      final authOut = AuthService(
        loggedOut.storage,
        loggedOut.httpClient,
        UniAuthService(logger: loggedOut.logger),
        logger: loggedOut.logger,
      );
      await authOut.loadSession();
      final outResult = await authOut.tryRenewSession();
      expect(outResult, SessionRenewalResult.unavailable);
      expect(outResult.isExpired, isFalse);
      expect(outResult.isUsable, isFalse);

      final legacy = await buildHarness(session: expiredSession(refreshToken: null));
      final authLegacy = AuthService(
        legacy.storage,
        legacy.httpClient,
        UniAuthService(logger: legacy.logger),
        logger: legacy.logger,
      );
      await authLegacy.loadSession();
      final legacyResult = await authLegacy.tryRenewSession();
      expect(legacyResult, SessionRenewalResult.unavailable);
      expect(legacyResult.isExpired, isFalse);
    });

    test('skips renewal when access token still has plenty of lifetime', () async {
      var calls = 0;
      final freshSession = UserSession(
        userId: 'u-1',
        userName: 'Alice',
        schoolName: '上海科技大学',
        createdAt: DateTime.utc(2026, 9, 1),
        geekpieToken: 'at-fresh',
        geekpieExpiresAt:
            DateTime.now().add(const Duration(days: 5)).toUtc().toIso8601String(),
        geekpieRefreshToken: 'rt-fresh',
      );
      final h = await buildHarness(session: freshSession);
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) async {
          calls++;
          return http.Response('{}', 500);
        },
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.skipped);
      expect(result.isUsable, isTrue);
      expect(result.isExpired, isFalse);
      expect(calls, 0);
    });

    test('persists rotated tokens and returns renewed on HTTP 200', () async {
      final h = await buildHarness(session: expiredSession());
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) async => http.Response(
          jsonEncode({
            'access_token': 'at-rotated',
            'refresh_token': 'rt-rotated',
            'expires_in': 604800,
          }),
          200,
        ),
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.renewed);
      expect(result.isUsable, isTrue);
      expect(result.isExpired, isFalse);
      expect(auth.session?.geekpieToken, 'at-rotated');
      expect(auth.session?.geekpieRefreshToken, 'rt-rotated');
      final persisted = await h.storage.loadSession();
      expect(persisted?.geekpieToken, 'at-rotated');
      expect(persisted?.geekpieRefreshToken, 'rt-rotated');
    });

    test('returns expired on Casdoor 400 invalid_grant and logs outcome', () async {
      final h = await buildHarness(session: expiredSession());
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) async => http.Response(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'refresh token is invalid or revoked',
          }),
          400,
        ),
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.expired);
      expect(result.isExpired, isTrue);
      expect(result.isUsable, isFalse);

      final ssoLogs = h.logger.entries.where((e) => e.tag == 'SSO').toList();
      expect(
        ssoLogs.any((e) => (e.error ?? '').contains('outcome=expired')),
        isTrue,
      );
      expect(
        ssoLogs.any((e) => (e.error ?? '').contains('oauth=invalid_grant')),
        isTrue,
      );
    });

    test('returns transientError on SocketException, logs type, and redacts token', () async {
      const secretRt = 'rt-super-secret-token-999';
      final h = await buildHarness(session: expiredSession(refreshToken: secretRt));
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) async {
          throw const SocketException(
            'Failed host lookup: auth.geekpie.club (rt-super-secret-token-999)',
          );
        },
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.transientError);
      expect(result.isExpired, isFalse);
      expect(result.isUsable, isFalse);

      final ssoErrors = h.logger.entries
          .where((e) => e.tag == 'SSO')
          .map((e) => e.error ?? '')
          .join('\n');
      expect(ssoErrors, contains('SocketException'));
      expect(ssoErrors, contains('outcome=transientError'));
      expect(ssoErrors, isNot(contains(secretRt)));
    });

    test('returns transientError on refresh timeout and logs TimeoutException', () async {
      final h = await buildHarness(session: expiredSession());
      final never = Completer<http.Response>();
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshTimeout: const Duration(milliseconds: 20),
        refreshRequest: (_) => never.future,
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.transientError);
      expect(result.isExpired, isFalse);

      final ssoErrors = h.logger.entries
          .where((e) => e.tag == 'SSO')
          .map((e) => e.error ?? '')
          .join('\n');
      expect(ssoErrors, contains('TimeoutException'));
    });

    test('returns transientError on 502 server outage without claiming expired', () async {
      final h = await buildHarness(session: expiredSession());
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) async => http.Response('<html>502</html>', 502),
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.transientError);
      expect(result.isExpired, isFalse);
      final ssoErrors = h.logger.entries
          .where((e) => e.tag == 'SSO')
          .map((e) => e.error ?? '')
          .join('\n');
      expect(ssoErrors, contains('status=502'));
    });

    test('returns transientError and logs redacted type when saveSession throws', () async {
      const secretRt = 'rt-save-fail-secret';
      final h = await buildHarness(
        session: expiredSession(refreshToken: secretRt),
        failSaveSession: true,
      );
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) async => http.Response(
          jsonEncode({
            'access_token': 'at-new',
            'refresh_token': secretRt,
            'expires_in': 3600,
          }),
          200,
        ),
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final result = await auth.tryRenewSession();
      expect(result, SessionRenewalResult.transientError);
      expect(result.isExpired, isFalse);

      final ssoErrors = h.logger.entries
          .where((e) => e.tag == 'SSO')
          .map((e) => e.error ?? '')
          .join('\n');
      expect(ssoErrors, contains('PlatformException'));
      expect(ssoErrors, isNot(contains(secretRt)));
    });

    test('deduplicates concurrent tryRenewSession calls (single-flight)', () async {
      var calls = 0;
      final completer = Completer<http.Response>();
      final h = await buildHarness(session: expiredSession());
      final uniAuth = UniAuthService(
        logger: h.logger,
        refreshRequest: (_) {
          calls++;
          return completer.future;
        },
      );
      final auth = AuthService(h.storage, h.httpClient, uniAuth, logger: h.logger);
      await auth.loadSession();

      final f1 = auth.tryRenewSession();
      final f2 = auth.tryRenewSession();
      completer.complete(
        http.Response(
          jsonEncode({'error': 'invalid_grant', 'error_description': 'revoked'}),
          400,
        ),
      );
      final results = await Future.wait([f1, f2]);
      expect(calls, 1);
      expect(results, [SessionRenewalResult.expired, SessionRenewalResult.expired]);
    });
  });
}
