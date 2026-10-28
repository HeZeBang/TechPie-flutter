import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/genai/genai_gateway.dart';
import 'package:techpie/services/genai/genai_login.dart';
import 'package:techpie/services/genai/genai_session.dart';
import 'package:techpie/services/genai_api_service.dart';
import 'package:techpie/services/storage_service.dart';

class _Login extends GenaiLogin {
  final calls = <(String, String)>[];
  Future<String> Function()? next;

  @override
  Future<String> login(String account, String password) async {
    calls.add((account, password));
    return next == null ? 'token-${calls.length}' : await next!();
  }
}

Future<StorageService> _storage({Map<String, String> secrets = const {}}) async {
  SharedPreferences.setMockInitialValues({'genai_api_port': 0});
  FlutterSecureStorage.setMockInitialValues(Map.of(secrets));
  return StorageService(await SharedPreferences.getInstance());
}

GenaiSession _session(DateTime expiresAt) => GenaiSession(
      account: 'student',
      password: 'fixture-password',
      token: 'saved-token',
      expiresAt: expiresAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final initial = DateTime.utc(2026, 10, 28, 12);

  testWidgets('login saves credentials and the two-hour expiry in secure storage', (tester) async {
    final storage = await _storage();
    final login = _Login();
    final service = GenaiApiService(storage, login: login, now: () => initial);
    expect(await service.login(' student ', 'fixture-password'), isTrue);
    final saved = (await storage.loadGenaiSession())!;
    expect(saved.account, 'student');
    expect(saved.password, 'fixture-password');
    expect(saved.token, 'token-1');
    expect(saved.expiresAt, initial.add(const Duration(hours: 2)));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'genai_api_port'});
    expect(service.apiToken, startsWith('sk-'));
    service.dispose();
  });

  testWidgets('timer refreshes without a page or running API and renews the deadline',
      (tester) async {
    var now = initial;
    final storage = await _storage();
    final login = _Login();
    final service = GenaiApiService(storage, login: login, now: () => now);
    await service.login('student', 'fixture-password');
    final apiToken = service.apiToken;
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(login.calls, [('student', 'fixture-password'), ('student', 'fixture-password')]);
    expect((await storage.loadGenaiSession())!.token, 'token-2');
    expect((await storage.loadGenaiSession())!.expiresAt, now.add(const Duration(hours: 2)));
    expect(service.apiToken, apiToken);
    expect(service.running, isFalse);
    now = now.add(const Duration(hours: 2));
    await tester.pump(const Duration(hours: 2));
    expect(login.calls, hasLength(3));
    service.dispose();
  });

  testWidgets('app initialization restores the remaining lifetime rather than extending it',
      (tester) async {
    var now = initial;
    final storage = await _storage();
    final expiry = initial.add(const Duration(hours: 1));
    await storage.saveGenaiSession(_session(expiry));
    final login = _Login();
    final service = GenaiApiService(storage, login: login, now: () => now);
    await service.initialize();
    expect(service.loggedIn, isTrue);
    expect(login.calls, isEmpty);
    now = expiry;
    await tester.pump(const Duration(hours: 1));
    expect(login.calls, hasLength(1));
    expect((await storage.loadGenaiSession())!.token, 'token-1');
    service.dispose();
  });

  testWidgets('failed automatic login retries after one minute without losing credentials',
      (tester) async {
    var now = initial;
    final storage = await _storage();
    await storage.saveGenaiSession(_session(initial));
    final login = _Login()..next = () async => throw const SocketException('offline');
    final service = GenaiApiService(storage, login: login, now: () => now);
    await service.initialize();
    await tester.pump(const Duration(milliseconds: 1));
    expect(login.calls, hasLength(1));
    expect(service.error, '自动登录失败，1 分钟后重试');
    expect((await storage.loadGenaiSession())!.token, 'saved-token');
    now = now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 59));
    expect(login.calls, hasLength(1));
    login.next = null;
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(login.calls, hasLength(2));
    expect((await storage.loadGenaiSession())!.token, 'token-2');
    expect(service.error, isNull);
    service.dispose();
  });

  testWidgets('logout during refresh clears credentials and ignores the late token',
      (tester) async {
    final storage = await _storage(secrets: {'genai_upstream_token': 'legacy-token'});
    await storage.saveGenaiSession(_session(initial));
    final pending = Completer<String>();
    final login = _Login()..next = () => pending.future;
    final service = GenaiApiService(storage, login: login, now: () => initial);
    await service.initialize();
    await tester.pump(const Duration(milliseconds: 1));
    expect(login.calls, hasLength(1));
    final logout = service.logout();
    await tester.pump(const Duration(milliseconds: 1));
    pending.complete('late-token');
    await logout;
    expect(service.loggedIn, isFalse);
    expect(await storage.loadGenaiSession(), isNull);
    final secure = const FlutterSecureStorage();
    expect(await secure.read(key: 'genai_upstream_token'), isNull);
    expect(await storage.loadGenaiApiToken(), service.apiToken);
    await tester.pump(const Duration(hours: 3));
    expect(login.calls, hasLength(1));
    service.dispose();
  });

  testWidgets('dispose ignores a pending refresh and cancels future timers', (tester) async {
    final storage = await _storage();
    await storage.saveGenaiSession(_session(initial));
    final pending = Completer<String>();
    final login = _Login()..next = () => pending.future;
    final service = GenaiApiService(storage, login: login, now: () => initial);
    await service.initialize();
    await tester.pump(const Duration(milliseconds: 1));
    service.dispose();
    pending.complete('late-token');
    await tester.pump(const Duration(milliseconds: 1));
    expect((await storage.loadGenaiSession())!.token, 'saved-token');
    await tester.pump(const Duration(hours: 3));
    expect(login.calls, hasLength(1));
  });

  testWidgets('account switch waits for the old refresh and saves only the new account',
      (tester) async {
    final storage = await _storage();
    await storage.saveGenaiSession(_session(initial));
    final pending = Completer<String>();
    final login = _Login()..next = () => pending.future;
    final service = GenaiApiService(storage, login: login, now: () => initial);
    await service.initialize();
    await tester.pump(const Duration(milliseconds: 1));
    final switchAccount = service.login('other-student', 'other-password');
    await tester.pump(const Duration(milliseconds: 1));
    login.next = null;
    pending.complete('old-account-token');
    expect(await switchAccount, isTrue);
    final saved = (await storage.loadGenaiSession())!;
    expect(saved.account, 'other-student');
    expect(saved.password, 'other-password');
    expect(saved.token, 'token-2');
    service.dispose();
  });

  testWidgets('legacy token without expiry requires a new login', (tester) async {
    final storage = await _storage(secrets: {'genai_upstream_token': 'legacy-token'});
    final login = _Login();
    final service = GenaiApiService(storage, login: login, now: () => initial);
    await service.initialize();
    expect(service.loggedIn, isFalse);
    expect(await service.start(), isFalse);
    expect(login.calls, isEmpty);
    service.dispose();
  });

  group('running HTTP gateway', () {
    late HttpServer upstream;
    late HttpClient client;
    late GenaiGateway gateway;
    late GenaiApiService service;
    late StorageService storage;
    late _Login login;
    late DateTime now;
    Completer<void>? streamEntered;
    Completer<void>? releaseStream;
    final tokens = <String?>[];

    setUp(() async {
      HttpOverrides.global = null;
      now = initial;
      tokens.clear();
      streamEntered = null;
      releaseStream = null;
      storage = await _storage();
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        tokens.add(request.headers.value('x-access-token'));
        if (request.uri.path.endsWith('/list')) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'success': true,
              'result': {
                'records': <Map<String, dynamic>>[],
              },
            }),
          );
        } else {
          await request.drain<void>();
          streamEntered?.complete();
          await releaseStream?.future;
          request.response.headers.contentType = ContentType('text', 'event-stream');
          request.response.write('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': 'still running'},
                    'finish_reason': 'stop',
                  },
                ],
              })}\n\ndata: [DONE]\n\n');
        }
        await request.response.close();
      });
      gateway = GenaiGateway(
        upstream: Uri.parse('http://127.0.0.1:${upstream.port}'),
        heartbeatInterval: const Duration(milliseconds: 30),
      );
      login = _Login();
      service = GenaiApiService(storage, gateway: gateway, login: login, now: () => now);
      await service.login('student', 'fixture-password');
      expect(await service.start(), isTrue);
      client = HttpClient();
    });

    tearDown(() async {
      service.dispose();
      client.close(force: true);
      await gateway.stop();
      await upstream.close(force: true);
    });

    Future<int> models({String? apiToken}) async {
      final request = await client.getUrl(Uri.parse('${service.endpoint}/models'));
      request.headers.set('Authorization', 'Bearer ${apiToken ?? service.apiToken}');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    test('expired concurrent requests share one login and use the new token on the same port',
        () async {
      final port = gateway.port;
      final apiToken = service.apiToken;
      expect(await models(), 200);
      now = now.add(const Duration(hours: 2));
      final pending = Completer<String>();
      final entered = Completer<void>();
      login.next = () {
        entered.complete();
        return pending.future;
      };
      final provider = gateway.tokenProvider!;
      final bothWaiting = Completer<void>();
      var waiting = 0;
      gateway.tokenProvider = () {
        if (++waiting == 2) bothWaiting.complete();
        return provider();
      };
      final first = models();
      await entered.future;
      final second = models();
      await bothWaiting.future;
      pending.complete('refreshed-token');
      expect(await Future.wait([first, second]), [200, 200]);
      expect(login.calls, hasLength(2));
      expect(tokens, ['token-1', 'refreshed-token', 'refreshed-token']);
      expect((await storage.loadGenaiSession())!.token, 'refreshed-token');
      expect(gateway.port, port);
      expect(service.running, isTrue);
      expect(service.apiToken, apiToken);
      expect(await storage.loadGenaiApiToken(), apiToken);
    });

    test('refresh keeps an existing streaming response alive', () async {
      streamEntered = Completer<void>();
      releaseStream = Completer<void>();
      final request = await client.postUrl(Uri.parse('${service.endpoint}/chat/completions'));
      request.headers.set('Authorization', 'Bearer ${service.apiToken}');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': 'test-model',
          'messages': [
            {'role': 'user', 'content': 'fixture'},
          ],
          'stream': true,
        }),
      );
      final response = await request.close();
      final body = utf8.decoder.bind(response).join();
      await streamEntered!.future;
      final port = gateway.port;
      now = now.add(const Duration(hours: 2));
      expect(await models(), 200);
      expect(tokens, ['token-1', 'token-2']);
      expect(gateway.port, port);
      releaseStream!.complete();
      expect(await body, contains('still running'));
      expect((await storage.loadGenaiSession())!.token, 'token-2');
    });

    test('failed refresh never forwards the expired token and a later request can recover',
        () async {
      now = now.add(const Duration(hours: 3));
      login.next = () async => throw const FormatException('登录失败');
      expect(await models(), isNot(200));
      expect(tokens, isEmpty);
      expect((await storage.loadGenaiSession())!.token, 'token-1');
      login.next = null;
      expect(await models(), 200);
      expect(tokens, ['token-3']);
      expect((await storage.loadGenaiSession())!.token, 'token-3');
      expect(service.error, isNull);
    });

    test('invalid local API token does not trigger upstream login', () async {
      now = now.add(const Duration(hours: 3));
      expect(await models(apiToken: 'wrong-token'), 401);
      expect(login.calls, hasLength(1));
      expect(tokens, isEmpty);
    });

    test('starting after app restart refreshes an expired saved session', () async {
      await service.stop();
      service.dispose();
      now = now.add(const Duration(hours: 3));
      service = GenaiApiService(storage, gateway: gateway, login: login, now: () => now);
      expect(await service.start(), isTrue);
      expect(login.calls, hasLength(2));
      expect(await models(), 200);
      expect(tokens, ['token-2']);
    });
  });
}
