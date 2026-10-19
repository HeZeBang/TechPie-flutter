import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'wear_protocol.dart';
import 'wear_qr_matrix.dart';

/// Android product services. The transport never decides whether data was applied.
class WearEngineService extends ChangeNotifier {
  WearEngineService({
    required this.transport,
    required this.source,
    required this.metadata,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 30),
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5)],
  }) : now = now ?? DateTime.now {
    final raw = metadata.read();
    if (raw != null) {
      try {
        final stored = jsonDecode(raw) as Map<String, dynamic>;
        _binding = stored['binding'] as String?;
        _scopeHash = stored['scopeHash'] as String?;
        _pendingClear = stored['pendingClear'] as String?;
        for (final resource in ['account', 'ddl']) {
          _revisions[resource] =
              (stored['revisions'] as Map?)?[resource] as int? ?? 0;
        }
      } catch (_) {
        _binding = null;
        _scopeHash = null;
        _pendingClear = 'userRevoked';
      }
    }
    _subscriptions.add(
      transport.frames.listen((frame) {
        try {
          final message = _codec.accept(frame, this.now());
          if (message != null) unawaited(_receive(message));
        } on WearFailure catch (error) {
          _error(error);
        }
      }),
    );
    _subscriptions.add(
      transport.states.listen((state) {
        _native.addAll(state);
        if (state['service'] == 'unavailable' ||
            state['device'] == 'disconnected') {
          _invalidate('DEVICE_DISCONNECTED');
        }
        _changed();
      }),
    );
  }

  final WearTransport transport;
  final WearDataSource source;
  final WearMetadata metadata;
  final DateTime Function() now;
  final Duration timeout;
  final List<Duration> retryDelays;
  final _codec = WearFrames();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, _Pending> _pending = {};
  final Map<String, _Reply> _replies = {};
  final Map<String, _Incoming> _inbound = {};
  final Map<String, int> _revisions = {'account': 0, 'ddl': 0};
  final Map<String, dynamic> _sync = {};
  final Map<String, dynamic> _native = {
    'service': 'unavailable',
    'device': 'none',
    'permission': {'p2p': false, 'notify': false},
  };
  Future<void> _tx = Future.value();
  Future<void> _refreshTail = Future.value();
  String? _binding, _scopeHash, _session, _device, _pendingClear;
  int _epoch = 0;
  int _leaseUntil = 0;
  int _maxCodeBytes = 512;
  bool _ready = false, _opening = false, _disposed = false, _codeBusy = false;
  DateTime? _lastCodeRequest;
  Set<String> _capabilities = {};
  Map<String, dynamic>? _lastError;
  Timer? _leaseTimer;
  Timer? _heartbeatTimer;
  bool _heartbeatBusy = false;
  Map<String, String>? _displayAccount;
  bool _remindersEnabled = false;
  bool get remindersEnabled => ready && _remindersEnabled;
  bool supports(String capability) =>
      ready && _capabilities.contains(capability);
  Map<String, String>? get displayAccount => ready && _displayAccount != null
      ? Map<String, String>.unmodifiable(_displayAccount!)
      : null;
  bool get ready => _ready && now().millisecondsSinceEpoch < _leaseUntil;

  String _id() {
    final random = Random.secure();
    return List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _error(WearFailure failure) {
    _lastError = {'code': failure.code, 'retryable': failure.retryable};
    if (failure.nativeCode != null) {
      _lastError!['nativeCode'] = failure.nativeCode;
    }
    _changed();
  }

  void _invalidate(String reason) {
    _epoch++;
    _ready = false;
    _session = null;
    _leaseTimer?.cancel();
    _heartbeatTimer?.cancel();
    _displayAccount = null;
    _codec.clear();
    _replies.clear();
    for (final pending in _pending.values) {
      if (!pending.done.isCompleted) {
        pending.done.completeError(WearFailure(reason, retryable: true));
      }
    }
    _pending.clear();
  }

  Future<void> _persist() => metadata.write(
        jsonEncode({
          'binding': _binding,
          'scopeHash': _scopeHash,
          'pendingClear': _pendingClear,
          'revisions': _revisions,
        }),
      );
  Map<String, dynamic> getStatus() => {
        ..._native,
        'peer': ready ? 'ready' : 'waiting',
        'capabilities': _capabilities.toList(),
        'sync': Map<String, dynamic>.from(_sync),
        'pendingClear': _pendingClear != null,
        'lastError': _lastError,
      };
  Future<Map<String, dynamic>> refreshStatus() async {
    try {
      _native.addAll(await transport.status().timeout(timeout));
      if (_native['device'] == 'disconnected') {
        _invalidate('DEVICE_DISCONNECTED');
      }
    } on WearFailure catch (error) {
      _error(error);
    } on TimeoutException {
      _error(const WearFailure('SERVICE_UNAVAILABLE', retryable: true));
    }
    _changed();
    return getStatus();
  }

  Future<List<Map<String, dynamic>>> devices() =>
      transport.devices().timeout(timeout);

  /// Called by the device picker before querying devices; never called at boot.
  Future<Map<String, dynamic>> requestPermissions({bool notify = false}) async {
    final permissions =
        await transport.authorize(notify: notify).timeout(timeout);
    _native['permission'] = permissions;
    _changed();
    return permissions;
  }

  Future<void> open(
    String deviceId, {
    required String watchFingerprint,
    bool notify = false,
  }) async {
    if (_opening) throw const WearFailure('RATE_LIMITED');
    if (watchFingerprint.isEmpty ||
        watchFingerprint.length > 512 ||
        RegExp(r'\s').hasMatch(watchFingerprint)) {
      throw const WearFailure('INVALID_PAYLOAD');
    }
    _opening = true;
    try {
      await close();
      var epoch = _epoch;
      await requestPermissions(notify: notify);
      _remindersEnabled =
          notify && (_native['permission'] as Map)['notify'] == true;
      if ((_native['permission'] as Map)['p2p'] != true) {
        throw const WearFailure('PERMISSION_DENIED');
      }
      await transport.open(deviceId, watchFingerprint).timeout(timeout);
      _checkEpoch(epoch);
      _device = deviceId;
      _native.addAll({'service': 'ready', 'device': 'connected'});
      // Drain a durable revocation before binding the newly logged-in account.
      if (_pendingClear != null && _binding != null) {
        await _handshake(epoch);
        await _clearConnected(_pendingClear!);
        _invalidate('SESSION_MISMATCH');
        epoch = _epoch;
      }
      final account = await source.account();
      account.toJson();
      _checkEpoch(epoch);
      final scopeHash = sha256.convert(utf8.encode(account.scope)).toString();
      if (_scopeHash != scopeHash || _binding == null) {
        await transport.cancelReminders();
        _checkEpoch(epoch);
        _scopeHash = scopeHash;
        _binding = _id();
        _revisions.updateAll((_, __) => 0);
        _sync.clear();
      }
      _pendingClear =
          null; // Explicit open authorizes a new binding after revocation.
      await _persist();
      _checkEpoch(epoch);
      await _handshake(epoch);
      // A business refresh failure must not tear down a working transport.
      try {
        await refresh(
          resources: [
            if (_capabilities.contains('account.display')) 'account',
            if (_capabilities.contains('ddl.display')) 'ddl',
          ],
        );
      } on WearFailure catch (error) {
        _error(error);
      }
    } catch (error) {
      _invalidate('SESSION_MISMATCH');
      await transport.close();
      final failure = error is WearFailure
          ? error
          : const WearFailure('SERVICE_UNAVAILABLE', retryable: true);
      _error(failure);
      throw failure;
    } finally {
      _opening = false;
      _changed();
    }
  }

  Future<void> _handshake(int epoch) async {
    final nonce = _id();
    final welcome = await _request(
      'session.hello',
      {
        'nonce': nonce,
        'versions': [1],
        'capabilities': [
          'account.display',
          'ddl.display',
          'campusCode.qrBytes',
          'campusCode.qrMatrix',
          'connection.heartbeat',
        ],
      },
      expected: 'session.welcome',
      handshake: true,
    );
    _checkEpoch(epoch);
    final body = Map<String, dynamic>.from(welcome['body'] as Map);
    if (body['nonce'] != nonce ||
        body['version'] != 1 ||
        body['watchInstanceId'] is! String ||
        body['capabilities'] is! List) {
      throw const WearFailure('UNSUPPORTED_VERSION');
    }
    _capabilities = (body['capabilities'] as List)
        .whereType<String>()
        .toSet()
        .intersection({
      'account.display',
      'ddl.display',
      'campusCode.qrBytes',
      'campusCode.qrMatrix',
      'connection.heartbeat',
    });
    if (_remindersEnabled && (_native['permission'] as Map)['notify'] == true) {
      _capabilities.add('reminder.phoneNotify');
    }
    final max = body['maxQrPayloadBytes'];
    _maxCodeBytes = max is int && max > 0 ? max.clamp(1, 1024) : 512;
    final session = _id();
    _leaseUntil = now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    await _request(
      'session.open',
      {
        'nonce': nonce,
        'sessionId': session,
        'bindingId': _binding,
        'phoneTimeMs': now().millisecondsSinceEpoch,
        'leaseUntilMs': _leaseUntil,
      },
      expected: 'session.opened',
      handshake: true,
    );
    _checkEpoch(epoch);
    _session = session;
    _ready = true;
    _lastError = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_capabilities.contains('connection.heartbeat')) {
        unawaited(_heartbeat());
      }
    });
    _leaseTimer?.cancel();
    _leaseTimer = Timer(const Duration(hours: 24), () {
      _invalidate('SESSION_MISMATCH');
      unawaited(transport.cancelReminders());
      _changed();
    });
    _changed();
  }

  void _checkEpoch(int epoch) {
    if (_disposed || epoch != _epoch) {
      throw const WearFailure('SESSION_MISMATCH');
    }
  }

  Future<void> _heartbeat() async {
    if (_heartbeatBusy || !ready) return;
    _heartbeatBusy = true;
    final epoch = _epoch;
    try {
      await _request(
        'session.ping',
        {},
        retry: false,
        responseTimeout: const Duration(seconds: 8),
      );
    } catch (_) {
      if (epoch == _epoch) {
        _invalidate('DEVICE_DISCONNECTED');
        await transport.close();
        _native['device'] = 'disconnected';
        _changed();
      }
    } finally {
      _heartbeatBusy = false;
    }
  }

  void _requireReady() {
    if (!ready || _pendingClear != null) {
      throw const WearFailure('PEER_NOT_READY', retryable: true);
    }
  }

  Future<void> _checkAccount(int epoch) async {
    final account = await source.account();
    _checkEpoch(epoch);
    if (sha256.convert(utf8.encode(account.scope)).toString() != _scopeHash) {
      throw const WearFailure('ACCOUNT_NOT_READY');
    }
  }

  Future<void> _write(Map<String, dynamic> message) {
    final epoch = _epoch;
    final frames = WearFrames.encode(message);
    final operation = _tx.catchError((Object _) {}).then((_) async {
      for (final frame in frames) {
        _checkEpoch(epoch);
        await transport.send(frame).timeout(timeout);
      }
    });
    _tx = operation.catchError((Object _) {});
    return operation;
  }

  Map<String, dynamic> _message(
    String type,
    Map<String, dynamic> body, {
    String? replyTo,
    bool handshake = false,
  }) =>
      {
        'v': 1,
        'id': _id(),
        'replyTo': replyTo,
        'sessionId': handshake ? null : _session,
        'bindingId': handshake ? null : _binding,
        'type': type,
        'sentAtMs': now().millisecondsSinceEpoch,
        'body': body,
      };
  Future<Map<String, dynamic>> _request(
    String type,
    Map<String, dynamic> body, {
    String expected = 'result',
    bool handshake = false,
    bool retry = true,
    Duration? responseTimeout,
    String? replyTo,
  }) async {
    final message =
        _message(type, body, handshake: handshake, replyTo: replyTo);
    final pending = _Pending(expected);
    final id = message['id'] as String;
    _pending[id] = pending;
    // Attach an error handler immediately: invalidate can finish before send returns.
    final answer = pending.done.future;
    unawaited(answer.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      for (var attempt = 0;; attempt++) {
        await _write(message);
        try {
          return await answer.timeout(responseTimeout ?? timeout);
        } on TimeoutException {
          if (!retry ||
              attempt >= retryDelays.length ||
              (!handshake && !ready)) {
            throw const WearFailure('SYNC_TIMEOUT', retryable: true);
          }
          await Future<void>.delayed(retryDelays[attempt]);
        }
      }
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> _receive(Map<String, dynamic> message) async {
    try {
      final type = message['type'] as String;
      final pending = _pending[message['replyTo']];
      final handshake = type == 'session.welcome' ||
          type == 'session.opened' ||
          (type == 'result' && pending != null && pending.expected != 'result');
      if (handshake) {
        if (!_opening ||
            message['sessionId'] != null ||
            message['bindingId'] != null) {
          return;
        }
      } else if (!ready ||
          message['sessionId'] != _session ||
          message['bindingId'] != _binding) {
        return; // Old session/account must never cause side effects or finish a request.
      }
      if (pending != null && (type == pending.expected || type == 'result')) {
        final body = message['body'] as Map;
        if (!pending.done.isCompleted) {
          if (type == 'result' && body['status'] == 'error') {
            pending.done.completeError(
              WearFailure(
                body['code'] as String? ?? 'INVALID_PAYLOAD',
                retryable: body['retryable'] == true,
              ),
            );
          } else if (type == pending.expected &&
              (type != 'result' || body['status'] == 'ok')) {
            pending.done.complete(message);
          }
        }
        return;
      }
      if (type == 'result' || handshake || _pendingClear != null) return;
      final id = message['id'] as String;
      final content = jsonEncode(message);
      final cached = _replies[id];
      if (cached != null) {
        if (cached.content != content) {
          throw const WearFailure('INVALID_PAYLOAD');
        }
        await _write(cached.message);
        return;
      }
      final running = _inbound[id];
      if (running != null) {
        if (running.content != content) {
          throw const WearFailure('INVALID_PAYLOAD');
        }
        await running.done;
        return;
      }
      final work = _handleRequest(message, content);
      _inbound[id] = _Incoming(content, work);
      try {
        await work;
      } finally {
        _inbound.remove(id);
      }
    } on WearFailure catch (error) {
      _error(error);
    } catch (_) {
      _error(const WearFailure('INVALID_PAYLOAD'));
    }
  }

  Future<void> _reply(
    Map<String, dynamic> request,
    String content,
    Map<String, dynamic> body,
  ) async {
    final reply = _message('result', body, replyTo: request['id'] as String);
    if (_replies.length >= 64) _replies.remove(_replies.keys.first);
    _replies[request['id'] as String] = _Reply(content, reply);
    await _write(reply);
  }

  Future<void> _handleRequest(
    Map<String, dynamic> message,
    String content,
  ) async {
    final epoch = _epoch;
    try {
      await _checkAccount(epoch);
      final body = Map<String, dynamic>.from(message['body'] as Map);
      switch (message['type']) {
        case 'sync.request':
          final resources =
              (body['resources'] as List?)?.whereType<String>().toList();
          if (resources == null ||
              resources.isEmpty ||
              resources.any((r) => !['account', 'ddl'].contains(r))) {
            throw const WearFailure('INVALID_PAYLOAD');
          }
          await _reply(message, content, {'status': 'ok', 'code': 'OK'});
          await refresh(resources: resources);
        case 'campusCode.request':
          if (body['format'] != 'qrBytes' || body['purpose'] is! String) {
            throw const WearFailure('UNSUPPORTED_FORMAT');
          }
          await _sendCode(
            body['purpose'] as String,
            replyTo: message['id'] as String,
          );
          await _reply(message, content, {'status': 'ok', 'code': 'OK'});
        default:
          throw const WearFailure('UNSUPPORTED_OPERATION');
      }
    } catch (error) {
      if (epoch != _epoch || !ready) return;
      final failure =
          error is WearFailure ? error : const WearFailure('INVALID_PAYLOAD');
      await _reply(message, content, {
        'status': 'error',
        'code': failure.code,
        'retryable': failure.retryable,
      });
    }
  }

  Future<void> refresh({List<String> resources = const ['account', 'ddl']}) {
    final operation =
        _refreshTail.catchError((Object _) {}).then((_) => _refresh(resources));
    _refreshTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _refresh(List<String> resources) async {
    _requireReady();
    if (resources.isEmpty ||
        resources.any((r) => !['account', 'ddl'].contains(r))) {
      throw const WearFailure('INVALID_PAYLOAD');
    }
    final epoch = _epoch;
    await _checkAccount(epoch);
    WearFailure? firstError;
    for (final resource in resources.toSet()) {
      try {
        if (!_capabilities.contains('$resource.display')) {
          throw const WearFailure('UNSUPPORTED_OPERATION');
        }
        Map<String, dynamic> body;
        if (resource == 'account') {
          body = {'data': (await source.account()).toJson()};
        } else {
          final items = await source.deadlines();
          body = _ddlSnapshot(items);
          await _checkAccount(epoch);
          await _schedule(items);
        }
        await _checkAccount(epoch);
        final revision = _revisions[resource]! + 1;
        _revisions[resource] = revision;
        await _persist(); // Increment before transmission; never reuse a revision after restart.
        _checkEpoch(epoch);
        body.addAll({
          'revision': revision,
          'generatedAtMs': now().millisecondsSinceEpoch,
          'validUntilMs': _leaseUntil,
        });
        _sync[resource] = {'state': 'pending', 'revision': revision};
        _changed();
        final answer = await _request('$resource.snapshot', body);
        _checkEpoch(epoch);
        final result = answer['body'] as Map;
        if (result['resource'] != resource || result['revision'] != revision) {
          throw const WearFailure('INVALID_PAYLOAD');
        }
        _sync[resource] = {
          'state': 'applied',
          'revision': revision,
          'atMs': now().millisecondsSinceEpoch,
        };
        if (resource == 'account') {
          _displayAccount = Map<String, String>.from(body['data'] as Map);
        }
      } catch (error) {
        final failure = error is WearFailure
            ? error
            : const WearFailure('SERVICE_UNAVAILABLE', retryable: true);
        _sync[resource] = {'state': 'failed', 'code': failure.code};
        firstError ??= failure;
        _error(failure);
      }
      if (epoch != _epoch) break;
    }
    _changed();
    if (firstError != null) throw firstError;
  }

  Map<String, dynamic> _ddlSnapshot(List<WearDdl> items) {
    final from = now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final to = now().add(const Duration(days: 30)).millisecondsSinceEpoch;
    final selected = items
        .where(
          (item) =>
              item.dueAt.millisecondsSinceEpoch >= from &&
              item.dueAt.millisecondsSinceEpoch < to,
        )
        .toList()
      ..sort((a, b) {
        final order = a.dueAt.compareTo(b.dueAt);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    final result = <Map<String, dynamic>>[];
    var truncated = selected.length > 50;
    for (final item in selected.take(50)) {
      result.add(item.toJson());
      // Reserve room for the envelope and metadata, truncate whole items only.
      if (utf8.encode(jsonEncode(result)).length > WearFrames.maxBytes - 1024) {
        result.removeLast();
        truncated = true;
        break;
      }
    }
    return {
      'timeZone': 'Asia/Shanghai',
      'window': {'fromMs': from, 'toMs': to},
      'truncated': truncated,
      'items': result,
    };
  }

  Future<void> _schedule(List<WearDdl> deadlines) async {
    _requireReady();
    if (!_capabilities.contains('reminder.phoneNotify')) {
      await transport.cancelReminders();
      return;
    }
    final reminders = <Map<String, dynamic>>[];
    for (final item in deadlines.where((item) => !item.completed)) {
      for (final at in item.remindAt.take(3)) {
        if (now().isAfter(at.add(const Duration(minutes: 10))) ||
            at.millisecondsSinceEpoch >= _leaseUntil) {
          continue;
        }
        reminders.add({
          'reminderId': sha256
              .convert(
                utf8.encode(
                  '$_binding:${item.id}:${at.millisecondsSinceEpoch}',
                ),
              )
              .toString(),
          'ddlId': item.id,
          'title': item.title,
          'dueAtMs': item.dueAt.millisecondsSinceEpoch,
          'scheduledAtMs': at.millisecondsSinceEpoch,
          'expiresAtMs':
              at.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
          'ddlRevision': _revisions['ddl']! + 1,
        });
      }
    }
    if (reminders.length > 500) throw const WearFailure('PAYLOAD_TOO_LARGE');
    await transport.scheduleReminders({
      'deviceId': _device,
      'bindingId': _binding,
      'leaseUntilMs': _leaseUntil,
      'items': reminders,
    });
  }

  Future<String> sendReminder(String reminderId) =>
      transport.sendReminder(reminderId);

  Future<void> setRemindersEnabled(bool enabled) async {
    _requireReady();
    final epoch = _epoch;
    if (enabled) {
      if (_remindersEnabled) return;
      final permissions = await requestPermissions(notify: true);
      _checkEpoch(epoch);
      if (permissions['notify'] != true) {
        throw const WearFailure('PERMISSION_DENIED');
      }
      _capabilities.add('reminder.phoneNotify');
      try {
        await refresh(resources: ['ddl']);
        _checkEpoch(epoch);
      } catch (_) {
        if (epoch == _epoch) {
          _capabilities.remove('reminder.phoneNotify');
          _remindersEnabled = false;
          try {
            await transport.cancelReminders();
          } catch (_) {
            // Keep the original scheduling failure available to the caller.
          }
          _changed();
        }
        rethrow;
      }
    } else {
      await transport.cancelReminders();
      _checkEpoch(epoch);
      _capabilities.remove('reminder.phoneNotify');
    }
    _remindersEnabled = enabled;
    _changed();
  }

  Future<void> _sendCode(String purpose, {required String replyTo}) async {
    _requireReady();
    if (!_capabilities.contains('campusCode.qrBytes') &&
        !_capabilities.contains('campusCode.qrMatrix')) {
      throw const WearFailure('UNSUPPORTED_FORMAT');
    }
    if (_codeBusy ||
        (_lastCodeRequest != null &&
            now().difference(_lastCodeRequest!) < const Duration(seconds: 5))) {
      throw const WearFailure('RATE_LIMITED', retryable: true);
    }
    _codeBusy = true;
    _lastCodeRequest = now();
    final epoch = _epoch;
    final elapsed = Stopwatch()..start();
    try {
      final code = await source.campusCode(purpose).timeout(timeout);
      await _checkAccount(epoch);
      if (code.bytes.isEmpty || code.bytes.length > _maxCodeBytes) {
        throw const WearFailure('PAYLOAD_TOO_LARGE');
      }
      final expiry = [
        code.validUntil.millisecondsSinceEpoch,
        code.issuedAt.add(const Duration(seconds: 120)).millisecondsSinceEpoch,
        _leaseUntil,
      ].reduce(min);
      if (expiry <=
          now().add(const Duration(seconds: 5)).millisecondsSinceEpoch) {
        throw const WearFailure('CODE_EXPIRED');
      }
      final remaining = const Duration(seconds: 30) - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw const WearFailure('SYNC_TIMEOUT', retryable: true);
      }
      await _request(
        'campusCode.snapshot',
        {
          'codeId': _id(),
          'purpose': purpose,
          'format': 'qrBytes',
          'issuedAtMs': code.issuedAt.millisecondsSinceEpoch,
          'validFromMs': code.issuedAt.millisecondsSinceEpoch,
          'validUntilMs': expiry,
          'payloadEncoding': 'base64',
          'payload': base64Encode(code.bytes),
          if (_capabilities.contains('campusCode.qrMatrix'))
            ...wearQrMatrix(code.bytes),
        },
        replyTo: replyTo,
        retry: false,
        responseTimeout: remaining < timeout ? remaining : timeout,
      );
    } finally {
      _codeBusy = false;
    }
  }

  /// Call immediately on logout/account mutation. Persist first, then drain on reconnect.
  Future<void> clear({String reason = 'userRevoked'}) async {
    if (!['logout', 'accountChanged', 'userRevoked'].contains(reason)) {
      throw const WearFailure('INVALID_PAYLOAD');
    }
    _pendingClear = reason;
    // Stop existing sends/requests synchronously before issuing the clear command.
    final oldSession = _session;
    _invalidate('SESSION_MISMATCH');
    await transport.cancelReminders();
    await _persist();
    _session = oldSession;
    _ready = oldSession != null;
    try {
      if (ready) await _clearConnected(reason);
    } finally {
      await close();
    }
  }

  Future<void> reconcileAccount() async {
    if (_binding == null || _pendingClear != null || _disposed) return;
    final epoch = _epoch;
    try {
      final current = await source.account();
      _checkEpoch(epoch);
      if (sha256.convert(utf8.encode(current.scope)).toString() != _scopeHash) {
        await clear(reason: 'accountChanged');
      }
    } on WearFailure catch (error) {
      if (epoch == _epoch && error.code == 'ACCOUNT_NOT_READY') {
        await clear(reason: 'logout');
      }
    }
  }

  Future<void> _clearConnected(String reason) async {
    await _request('session.clear', {'reason': reason});
    _pendingClear = null;
    _binding = null;
    _scopeHash = null;
    _revisions.updateAll((_, __) => 0);
    _sync.clear();
    await _persist();
  }

  Future<void> close() async {
    if (ready && _capabilities.contains('connection.heartbeat')) {
      try {
        await _request(
          'session.close',
          {},
          retry: false,
          responseTimeout: const Duration(seconds: 2),
        );
      } catch (_) {
        // A disconnected peer is released even when the final acknowledgement is lost.
      }
    }
    _invalidate('PEER_NOT_READY');
    _remindersEnabled = false;
    await transport.cancelReminders();
    await transport.close();
    _native['device'] = 'disconnected';
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate('PEER_NOT_READY');
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    transport.dispose();
    super.dispose();
  }
}

class _Pending {
  _Pending(this.expected);
  final String expected;
  final done = Completer<Map<String, dynamic>>();
}

class _Incoming {
  _Incoming(this.content, this.done);
  final String content;
  final Future<void> done;
}

class _Reply {
  _Reply(this.content, this.message);
  final String content;
  final Map<String, dynamic> message;
}
