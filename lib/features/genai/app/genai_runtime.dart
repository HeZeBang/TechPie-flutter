import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../models/third_party_account.dart';
import '../../../services/auth_service.dart';
import '../../../services/third_party_auth_service.dart';
import '../application/campus_genai_session_issuer.dart';
import '../application/genai_chat_service.dart';
import '../application/genai_repository.dart';
import '../application/genai_session_service.dart';
import '../application/genai_workspace_controller.dart';
import '../data/genai_api_client.dart';
import '../data/genai_request_signer.dart';
import '../data/secure_genai_session_store.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';
import '../platform/genai_transport.dart';
import '../platform/http_genai_transport.dart';

/// Construction only installs listeners. Secure storage/network access starts
/// when a feature explicitly connects or requests authenticated data.
final class GenAiRuntime {
  GenAiRuntime({
    required AuthService auth,
    required ThirdPartyAuthService thirdPartyAuth,
    GenAiTransport? transport,
    GenAiSessionStore? store,
    GenAiSessionIssuer? issuer,
    Uri? apiBase,
    this.isDemo = false,
  })  : _auth = auth,
        _thirdPartyAuth = thirdPartyAuth,
        _issuer = issuer,
        _transport = transport ?? HttpGenAiTransport() {
    if (isDemo && !kDebugMode) throw UnsupportedError('Preview is debug-only');
    final api = GenAiApiClient(
      transport: _transport,
      apiBase: apiBase,
      signer: const GenAiRequestSigner(
        String.fromEnvironment(
          'TECHPI_GENAI_SIGNING_SALT',
          defaultValue: 'dd05f1c54d63749eda95f9fa6d49v442a',
        ),
      ),
    );
    _api = api;
    sessions = GenAiSessionService(
      api: api,
      store: store ?? SecureGenAiSessionStore(),
      issuer: issuer,
    );
    repository = GenAiRepository(api: api, sessions: sessions);
    chat = GenAiChatService(repository);
    workspace = GenAiWorkspaceController(
      sessions: sessions,
      repository: repository,
      chat: chat,
    );
    _auth.addListener(_syncOwner);
    _thirdPartyAuth.addListener(_syncOwner);
    _syncOwner();
  }

  final bool isDemo;
  final AuthService _auth;
  final ThirdPartyAuthService _thirdPartyAuth;
  final GenAiTransport _transport;
  final GenAiSessionIssuer? _issuer;
  late final GenAiApiClient _api;
  String? _campusScope;
  String? _resolvedStudentId;
  bool _disposed = false;
  Future<void>? _campusConnection;
  final _identityOperations = <GenAiCancellation>{};
  late final GenAiSessionService sessions;
  late final GenAiRepository repository;
  late final GenAiChatService chat;
  late final GenAiWorkspaceController workspace;

  void _syncOwner() {
    final primary = _auth.session;
    final binding = _thirdPartyAuth.cpdailyBinding;
    final scope = _currentCampusScope();
    if (scope != _campusScope) {
      _campusScope = scope;
      _resolvedStudentId = null;
    }
    final boundStudentId = binding?.cpdailyStudentId ?? '';
    if (boundStudentId.isNotEmpty && _resolvedStudentId != boundStudentId) {
      _resolvedStudentId = null;
    }
    final studentId =
        boundStudentId.isNotEmpty ? boundStudentId : _resolvedStudentId ?? '';
    final owner = primary == null ||
            primary.userId.trim().isEmpty ||
            binding == null ||
            studentId.isEmpty
        ? null
        : GenAiOwner(
            primaryUserId: primary.userId,
            studentId: studentId,
            bindingId: binding.boundAt.toUtc().toIso8601String(),
          );
    if (owner == sessions.owner) return;
    chat.clear();
    // setOwner already exposes storage failures through sessions.lastFailure.
    // No raw platform exception or token-bearing URL is sent to DebugLogger.
    unawaited(sessions.setOwner(owner).catchError((Object _) {}));
  }

  String? _currentCampusScope() {
    final primary = _auth.session;
    final binding = _thirdPartyAuth.cpdailyBinding;
    if (primary == null || primary.userId.trim().isEmpty || binding == null) {
      return null;
    }
    return jsonEncode([
      primary.userId,
      binding.account,
      binding.boundAt.toUtc().toIso8601String(),
    ]);
  }

  /// SMS/legacy CpDaily bindings can contain only a phone and internal UUID.
  /// Resolve their school ID only through an SSO exchange tied to that binding,
  /// then use the normal GenAI session verifier. Never infer it from GeekPie or
  /// accept an arbitrary pasted token to fill a missing campus identity.
  Future<void> connectUsingCampusSession() {
    if (_disposed) {
      return Future.error(const GenAiFailure(GenAiFailureKind.cancelled));
    }
    final pending = _campusConnection;
    if (pending != null) return pending;
    late final Future<void> future;
    future = _connectUsingCampusSession().whenComplete(() {
      if (identical(_campusConnection, future)) _campusConnection = null;
    });
    _campusConnection = future;
    return future;
  }

  Future<void> _connectUsingCampusSession() async {
    if (sessions.owner != null) {
      await sessions.requireSession();
      return;
    }
    final scope = _currentCampusScope();
    final binding = _thirdPartyAuth.cpdailyBinding;
    final issuer = _issuer;
    if (scope == null ||
        binding == null ||
        issuer is! CampusGenAiSessionIssuer) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    final cancellation = GenAiCancellation();
    _identityOperations.add(cancellation);
    void guard() {
      if (_disposed || _currentCampusScope() != scope) {
        cancellation.cancel(GenAiFailureKind.accountChanged);
      }
    }

    _auth.addListener(guard);
    _thirdPartyAuth.addListener(guard);
    try {
      final credential = await issuer.issue(
        GenAiOwner(
          primaryUserId: _auth.session!.userId,
          studentId: '',
          bindingId: binding.boundAt.toUtc().toIso8601String(),
        ),
        cancellation,
      );
      final profile = await cancellation.race(
        _api.verifyToken(credential.token, cancellation),
      );
      guard();
      cancellation.throwIfCancelled();
      final studentId = ThirdPartyAccount.cpdailySchoolId(profile.username);
      if (studentId.isEmpty) {
        throw const GenAiFailure(GenAiFailureKind.identityMismatch);
      }
      final currentId = _thirdPartyAuth.cpdailyStudentId;
      if ((currentId.isNotEmpty && currentId != studentId) ||
          (_resolvedStudentId != null && _resolvedStudentId != studentId)) {
        throw const GenAiFailure(GenAiFailureKind.identityMismatch);
      }
      // Keep the resolution local to this runtime/binding, without rewriting
      // existing IDS credentials, raw data or cloud-synced account records.
      _resolvedStudentId = studentId;
      _syncOwner();
      cancellation.throwIfCancelled();
      await sessions.connect(credential);
    } finally {
      _auth.removeListener(guard);
      _thirdPartyAuth.removeListener(guard);
      _identityOperations.remove(cancellation);
      cancellation.cancel();
    }
  }

  void dispose() {
    _disposed = true;
    for (final operation in _identityOperations.toList()) {
      operation.cancel();
    }
    _auth.removeListener(_syncOwner);
    _thirdPartyAuth.removeListener(_syncOwner);
    workspace.dispose();
    chat.dispose();
    sessions.dispose();
    _transport.dispose();
  }
}
