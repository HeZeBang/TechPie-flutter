import 'package:flutter/foundation.dart';

import '../data/genai_api_client.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';

final class GenAiSessionService extends ChangeNotifier {
  GenAiSessionService({
    required GenAiApiClient api,
    required GenAiSessionStore store,
    GenAiSessionIssuer? issuer,
    DateTime Function()? now,
  })  : _api = api,
        _store = store,
        _issuer = issuer,
        _now = now ?? DateTime.now;

  final GenAiApiClient _api;
  final GenAiSessionStore _store;
  final GenAiSessionIssuer? _issuer;
  final DateTime Function() _now;
  GenAiOwner? _owner;
  GenAiSession? _session;
  Future<GenAiSession>? _pending;
  GenAiCancellation _scope = GenAiCancellation();
  int _revision = 0;
  bool _disposed = false;
  GenAiFailure? _lastFailure;

  GenAiOwner? get owner => _owner;
  GenAiSession? get session => _session;
  int get revision => _revision;
  GenAiFailure? get lastFailure => _lastFailure;

  /// Invalidates memory/requests synchronously, then removes the old record.
  Future<void> setOwner(GenAiOwner? owner) async {
    if (_disposed || owner == _owner) return;
    if (owner != null &&
        [owner.primaryUserId, owner.studentId, owner.bindingId]
            .any((value) => value.trim().isEmpty)) {
      throw const GenAiFailure(GenAiFailureKind.identityMismatch);
    }
    final previous = _owner;
    _owner = owner;
    _invalidate();
    if (previous != null) await _delete(previous);
  }

  void _invalidate() {
    _scope.cancel(GenAiFailureKind.accountChanged);
    _scope = GenAiCancellation();
    _revision++;
    _session = null;
    _pending = null;
    _lastFailure = null;
    if (!_disposed) notifyListeners();
  }

  bool get canIssue => _issuer != null;

  Future<GenAiSession> requireSession() {
    if (_disposed || _owner == null) {
      return Future.error(
        const GenAiFailure(GenAiFailureKind.authenticationRequired),
      );
    }
    final active = _session;
    if (active != null && !active.isExpired(_now())) {
      return Future.value(active);
    }
    _session = null;
    return _pending ?? _start(() => _restoreOrIssue(_owner!, _scope));
  }

  /// For a token returned by a future trusted browser callback/session issuer.
  /// A server profile + campus-identity match is required before persistence.
  Future<GenAiSession> connect(GenAiCredential credential) {
    final owner = _owner;
    if (_disposed || owner == null) {
      return Future.error(
        const GenAiFailure(GenAiFailureKind.authenticationRequired),
      );
    }
    _invalidate();
    final scope = _scope;
    return _start(() async {
      await _delete(owner);
      scope.throwIfCancelled();
      return _verifyAndSave(owner, credential, scope);
    });
  }

  Future<GenAiSession> _start(Future<GenAiSession> Function() operation) {
    final revision = _revision;
    late final Future<GenAiSession> future;
    future = operation().catchError((Object error) {
      final failure = error is GenAiFailure
          ? error
          : const GenAiFailure(GenAiFailureKind.transport);
      if (!_disposed && revision == _revision) {
        _lastFailure = failure;
        notifyListeners();
      }
      throw failure;
    }).whenComplete(() {
      if (identical(_pending, future)) _pending = null;
    });
    _pending = future;
    return future;
  }

  Future<GenAiSession> _restoreOrIssue(
    GenAiOwner owner,
    GenAiCancellation scope,
  ) async {
    final cached = await _store.read(owner);
    scope.throwIfCancelled();
    if (cached != null && !cached.isExpired(_now())) {
      try {
        return await _verifyAndSave(owner, cached.credential, scope);
      } on GenAiFailure catch (error) {
        if (error.kind != GenAiFailureKind.authenticationRequired &&
            error.kind != GenAiFailureKind.identityMismatch) {
          rethrow;
        }
        await _delete(owner);
      }
    } else if (cached != null) {
      await _delete(owner);
    }
    scope.throwIfCancelled();
    final issuer = _issuer;
    if (issuer == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    final credential = await scope.race(issuer.issue(owner, scope));
    scope.throwIfCancelled();
    return _verifyAndSave(owner, credential, scope);
  }

  Future<GenAiSession> _verifyAndSave(
    GenAiOwner owner,
    GenAiCredential credential,
    GenAiCancellation scope,
  ) async {
    if (credential.expiresAt != null &&
        !credential.expiresAt!.isAfter(_now())) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    final profile = await scope.race(_api.verifyToken(credential.token, scope));
    scope.throwIfCancelled();
    if (profile.username != owner.studentId) {
      throw const GenAiFailure(GenAiFailureKind.identityMismatch);
    }
    final session =
        GenAiSession(owner: owner, credential: credential, profile: profile);
    await _store.write(session);
    scope.throwIfCancelled();
    _session = session;
    _lastFailure = null;
    notifyListeners();
    return session;
  }

  /// An old failed request must not invalidate a newer successful connection.
  Future<void> reject(GenAiSession rejected) async {
    if (!identical(_session, rejected)) return;
    _invalidate();
    await _delete(rejected.owner);
  }

  Future<void> disconnect() async {
    final owner = _owner;
    _invalidate();
    if (owner != null) await _delete(owner);
  }

  Future<void> _delete(GenAiOwner owner) async {
    final revision = _revision;
    try {
      await _store.delete(owner);
    } catch (_) {
      if (!_disposed && revision == _revision) {
        _lastFailure = const GenAiFailure(GenAiFailureKind.storage);
        notifyListeners();
      }
      throw const GenAiFailure(GenAiFailureKind.storage);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scope.cancel(GenAiFailureKind.accountChanged);
    super.dispose();
  }
}
