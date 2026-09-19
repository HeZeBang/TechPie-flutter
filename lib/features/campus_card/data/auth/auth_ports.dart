import 'dart:async';

import '../../core/errors/app_failure.dart';
import '../../domain/models/auth_models.dart';
import '../../domain/ports/auth_port.dart';

typedef SignOutCleanup = Future<void> Function();

final class UnconfiguredAuthPort implements AuthPort {
  UnconfiguredAuthPort({required SignOutCleanup cleanup}) : _cleanup = cleanup;

  final SignOutCleanup _cleanup;
  final StreamController<AuthSnapshot> _changes =
      StreamController<AuthSnapshot>.broadcast(sync: true);
  static const _snapshot = AuthSnapshot(
    state: AuthState.unconfigured,
    message: '校园统一身份登录服务尚未配置。',
  );

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() async => _snapshot;

  @override
  Future<AuthSnapshot> restore() async => _snapshot;

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async {
    _changes.add(_snapshot);
    throw const AppFailure(
      FailureKind.authenticationUnconfigured,
      '校园统一身份登录服务尚未配置。',
      code: 'SSO_UNCONFIGURED',
    );
  }

  @override
  Future<void> signOut() async {
    await _cleanup();
    _changes.add(_snapshot);
  }
}

final class DemoAuthPort implements AuthPort {
  DemoAuthPort({required SignOutCleanup cleanup}) : _cleanup = cleanup;

  final SignOutCleanup _cleanup;
  final StreamController<AuthSnapshot> _changes =
      StreamController<AuthSnapshot>.broadcast(sync: true);
  AuthSnapshot _snapshot = const AuthSnapshot(state: AuthState.signedOut);

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() async => _snapshot;

  @override
  Future<AuthSnapshot> restore() async => _snapshot;

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async {
    if (credential is! DemoAuthCredential) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '演示环境仅接受演示登录。',
        code: 'DEMO_AUTH_CREDENTIAL_REQUIRED',
      );
    }
    _snapshot = const AuthSnapshot(
      state: AuthState.authenticated,
      session: AuthSession(subjectId: 'demo-student-001', orgId: '2'),
    );
    _changes.add(_snapshot);
    return _snapshot;
  }

  @override
  Future<void> signOut() async {
    await _cleanup();
    _snapshot = const AuthSnapshot(state: AuthState.signedOut, reason: AuthChangeReason.userSignedOut);
    _changes.add(_snapshot);
  }
}
