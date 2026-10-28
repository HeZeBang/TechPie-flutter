import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'genai/genai_gateway.dart';
import 'genai/genai_login.dart';
import 'storage_service.dart';

class GenaiApiService extends ChangeNotifier {
  GenaiApiService(this.storage, {GenaiGateway? gateway, GenaiLogin? login})
      : _gateway = gateway ??
            GenaiGateway(
              onDiagnostic: (metadata) {
                // Request metadata only; never log prompts, tool results or credentials.
                stdout.writeln('genai_request ${jsonEncode(metadata)}');
              },
            ),
        _login = login ?? GenaiLogin();

  final StorageService storage;
  final GenaiGateway _gateway;
  final GenaiLogin _login;
  Future<void>? _loading;
  bool _disposed = false;
  bool busy = false;
  String? error;
  String? _genaiToken;
  String _apiToken = '';
  String _host = '127.0.0.1';
  int _port = 5000;

  bool get running => _gateway.running;
  bool get loggedIn => (_genaiToken ?? '').isNotEmpty;
  String get host => _host;
  int get port => _port;
  String get apiToken => _apiToken;
  String get endpoint => 'http://127.0.0.1:${_gateway.port ?? _port}/v1';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      _genaiToken = await storage.loadGenaiToken();
      _apiToken = await storage.loadGenaiApiToken() ?? '';
      if (_apiToken.isEmpty) {
        final random = Random.secure();
        _apiToken =
            'sk-${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
        await storage.saveGenaiApiToken(_apiToken);
      }
      _host = storage.genaiApiHost;
      _port = storage.genaiApiPort;
    } catch (_) {
      _loading = null;
      error = '读取设置失败，请重试';
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<bool> login(String account, String password) async {
    if (busy || running) return false;
    if (account.trim().isEmpty || password.isEmpty) {
      error = '请输入学号和密码';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final token = await _login.login(account, password);
      await storage.saveGenaiToken(token);
      _genaiToken = token;
      return true;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = '登录失败，请重试';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> logout() async {
    if (busy) return;
    await stop();
    await storage.clearGenaiToken();
    _genaiToken = null;
    error = null;
    _notify();
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
    if (busy || running) return running;
    busy = true;
    error = null;
    _notify();
    try {
      await load();
      if (!loggedIn) throw const FormatException('请先登录 GenAI');
      await _gateway.start(host: _host, port: _port, genaiToken: _genaiToken!, apiToken: _apiToken);
      return true;
    } on FormatException catch (e) {
      error = e.message;
      return false;
    } on SocketException catch (_) {
      error = '端口已占用，换一个试试';
      return false;
    } catch (_) {
      error = '启动失败，请重试';
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
    unawaited(_gateway.stop());
    super.dispose();
  }
}
