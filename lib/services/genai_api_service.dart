import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'genai/genai_gateway.dart';
import 'genai/genai_login.dart';
import 'genai/genai_session.dart';
import 'storage_service.dart';

class GenaiApiService extends ChangeNotifier {
  GenaiApiService(
    this.storage, {
    GenaiGateway? gateway,
    GenaiLogin? login,
    DateTime Function()? now,
  })  : _gateway = gateway ??
            GenaiGateway(
              onDiagnostic: (metadata) {
                // Request metadata only; never log prompts, tool results or credentials.
                stdout.writeln('genai_request ${jsonEncode(metadata)}');
              },
            ),
        _login = login ?? GenaiLogin(),
        _now = now ?? DateTime.now {
    _gateway.tokenProvider = _ensureToken;
  }

  final StorageService storage;
  final GenaiGateway _gateway;
  static const tokenLifetime = Duration(hours: 2);
  static const _retryDelay = Duration(minutes: 1);

  final GenaiLogin _login;
  final DateTime Function() _now;
  GenaiSession? _session;
  Timer? _refreshTimer;
  Future<String>? _refreshing;
  int _generation = 0;
  Future<void>? _loading;
  bool _disposed = false;
  bool busy = false;
  String? error;
  String _apiToken = '';
  String _host = '127.0.0.1';
  int _port = 5000;

  bool get running => _gateway.running;
  bool get loggedIn => _session != null;
  String get host => _host;
  int get port => _port;
  String get apiToken => _apiToken;
  String get endpoint => 'http://127.0.0.1:${_gateway.port ?? _port}/v1';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await load();
    } catch (_) {
      // load exposes the settings error on the feature page.
    }
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final generation = _generation;
    try {
      final session = await storage.loadGenaiSession();
      _apiToken = await storage.loadGenaiApiToken() ?? '';
      if (_apiToken.isEmpty) {
        final random = Random.secure();
        _apiToken =
            'sk-${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        await storage.saveGenaiApiToken(_apiToken);
      }
      _host = storage.genaiApiHost;
      _port = storage.genaiApiPort;
      if (_disposed || generation != _generation) return;
      _session = session;
      _scheduleRefresh();
    } catch (_) {
      _loading = null;
      error = '读取设置失败，请重试';
      rethrow;
    } finally {
      _notify();
    }
  }

  void _scheduleRefresh({bool retry = false}) {
    _refreshTimer?.cancel();
    if (_disposed || _session == null) return;
    final remaining = _session!.expiresAt.difference(_now());
    final delay = retry ? _retryDelay : (remaining.isNegative ? Duration.zero : remaining);
    _refreshTimer = Timer(delay, () => unawaited(_refreshOnTimer()));
  }

  Future<void> _refreshOnTimer() async {
    try {
      await _ensureToken();
      _scheduleRefresh();
    } catch (_) {
      // _refresh records the error and schedules a retry.
    }
  }

  Future<String> _ensureToken() {
    if (_disposed || _session == null) {
      throw const FormatException('请先登录 GenAI');
    }
    if (_now().isBefore(_session!.expiresAt)) return Future.value(_session!.token);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final session = _session!;
    final generation = _generation;
    try {
      final token = await _login.login(session.account, session.password);
      final next = GenaiSession(
        account: session.account,
        password: session.password,
        token: token,
        expiresAt: _now().add(tokenLifetime),
      );
      await _acceptSession(next, generation);
      error = null;
      _notify();
      return token;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = '自动登录失败，1 分钟后重试';
        _scheduleRefresh(retry: true);
        _notify();
      }
      rethrow;
    }
  }

  Future<void> _acceptSession(GenaiSession session, int generation) async {
    if (_disposed || generation != _generation) throw StateError('Session changed');
    await storage.saveGenaiSession(session);
    if (_disposed || generation != _generation) throw StateError('Session changed');
    _session = session;
    _gateway.updateGenaiToken(session.token);
    _scheduleRefresh();
  }

  Future<void> _waitForRefresh() async {
    try {
      await _refreshing;
    } catch (_) {
      // Account changes and logout can supersede an in-flight refresh.
    }
  }

  Future<bool> login(String account, String password) async {
    if (_disposed || busy || running) return false;
    if (account.trim().isEmpty || password.isEmpty) {
      error = '请输入学号和密码';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await load();
      final generation = ++_generation;
      _refreshTimer?.cancel();
      await _waitForRefresh();
      if (_disposed) return false;
      final token = await _login.login(account.trim(), password);
      await _acceptSession(
        GenaiSession(
          account: account.trim(),
          password: password,
          token: token,
          expiresAt: _now().add(tokenLifetime),
        ),
        generation,
      );
      return true;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = '登录失败，请重试';
      return false;
    } finally {
      busy = false;
      _scheduleRefresh();
      _notify();
    }
  }

  Future<void> logout() async {
    if (_disposed || busy) return;
    busy = true;
    ++_generation;
    _refreshTimer?.cancel();
    _session = null;
    _notify();
    try {
      await stop();
      await _waitForRefresh();
      await storage.clearGenaiSession();
      error = null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> saveSettings({
    required String apiToken,
    required String port,
    required String host,
  }) async {
    if (running) return;
    final parsed = int.tryParse(port);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      throw const FormatException('端口填 1–65535');
    }
    if (apiToken.trim().isEmpty) throw const FormatException('请输入 API Token');
    final nextHost = host == '0.0.0.0' ? host : '127.0.0.1';
    await storage.saveGenaiApiToken(apiToken.trim());
    await storage.setGenaiApiPort(parsed);
    await storage.setGenaiApiHost(nextHost);
    _apiToken = apiToken.trim();
    _port = parsed;
    _host = nextHost;
    _notify();
  }

  Future<bool> start() async {
    if (_disposed || busy || running) return running;
    busy = true;
    error = null;
    _notify();
    try {
      await load();
      final token = await _ensureToken();
      if (_disposed) return false;
      try {
        await _gateway.start(host: _host, port: _port, genaiToken: token, apiToken: _apiToken);
      } on SocketException {
        throw const FormatException('端口已占用，换一个试试');
      }
      if (_disposed) {
        await _gateway.stop();
        return false;
      }
      return true;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error ??= '启动失败，请重试';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    await _gateway.stop();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _refreshTimer?.cancel();
    unawaited(_gateway.stop());
    super.dispose();
  }
}
