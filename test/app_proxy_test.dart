import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/http_proxy_io.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  late HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.global;
    configureAppProxy('');
  });

  tearDown(() {
    configureAppProxy('');
    HttpOverrides.global = previousOverrides;
  });

  group('app proxy validation and normalization', () {
    test('normalizes valid host:port and http:// URLs', () {
      expect(normalizeAppProxy('  127.0.0.1:7890  '), '127.0.0.1:7890');
      expect(normalizeAppProxy('HTTP://127.0.0.1:7890/'), '127.0.0.1:7890');
      expect(normalizeAppProxy('[::1]:7890'), '[::1]:7890');

      expect(isValidAppProxy('127.0.0.1:7890'), isTrue);
      expect(isValidAppProxy('http://proxy.local:8080/'), isTrue);
      expect(isValidAppProxy('[::1]:65535'), isTrue);
      expect(isValidAppProxy('localhost:1'), isTrue);
    });

    test('rejects invalid ports, schemes, and PAC injection attempts', () {
      expect(isValidAppProxy(''), isFalse);
      expect(isValidAppProxy('127.0.0.1:0'), isFalse);
      expect(isValidAppProxy('127.0.0.1:65536'), isFalse);
      expect(isValidAppProxy('127.0.0.1:99999'), isFalse);
      expect(isValidAppProxy('127.0.0.1'), isFalse);
      expect(isValidAppProxy(':7890'), isFalse);
      expect(isValidAppProxy('socks5://127.0.0.1:1080'), isFalse);
      expect(isValidAppProxy('https://127.0.0.1:7890'), isFalse);
      expect(isValidAppProxy('127.0.0.1:7890; DIRECT'), isFalse);
      expect(isValidAppProxy('127.0.0.1:7890/path'), isFalse);
      expect(isValidAppProxy('user:pass@127.0.0.1:7890'), isFalse);
    });
  });

  group('configureAppProxy and resolveAppProxy', () {
    final target = Uri.parse('https://auth.geekpie.club/login');

    test('falls back to environment proxy when disabled', () {
      configureAppProxy('');
      expect(resolveAppProxy(target, environment: const {}), 'DIRECT');
      expect(
        resolveAppProxy(
          target,
          environment: const {'https_proxy': 'http://10.0.0.2:8080'},
        ),
        'PROXY 10.0.0.2:8080',
      );
      expect(
        resolveAppProxy(
          target,
          environment: const {
            'https_proxy': 'http://10.0.0.2:8080',
            'no_proxy': 'auth.geekpie.club',
          },
        ),
        'DIRECT',
      );
    });

    test('overrides environment proxy when enabled and resets on disable', () {
      configureAppProxy('http://127.0.0.1:7890/');
      expect(
        resolveAppProxy(
          target,
          environment: const {'https_proxy': 'http://10.0.0.2:8080'},
        ),
        'PROXY 127.0.0.1:7890',
      );

      configureAppProxy('');
      expect(
        resolveAppProxy(
          target,
          environment: const {'https_proxy': 'http://10.0.0.2:8080'},
        ),
        'PROXY 10.0.0.2:8080',
      );
    });

    test('ignores invalid proxy strings and does not stack overrides', () {
      configureAppProxy('127.0.0.1:99999');
      expect(resolveAppProxy(target, environment: const {}), 'DIRECT');

      final installed = HttpOverrides.global;
      expect(installed, isA<TechPieHttpOverrides>());
      configureAppProxy('127.0.0.1:7890');
      expect(identical(HttpOverrides.global, installed), isTrue);
    });
  });

  test('UniAuthService normalizes and sanitizes proxy URLs', () {
    final service = UniAuthService(proxyUrl: 'http://127.0.0.1:7890/');
    addTearDown(service.dispose);
    expect(service.proxyUrl, '127.0.0.1:7890');

    service.setProxyUrl('127.0.0.1:99999');
    expect(service.proxyUrl, '');

    service.setProxyUrl('127.0.0.1:8080');
    expect(service.proxyUrl, '127.0.0.1:8080');
  });
}
