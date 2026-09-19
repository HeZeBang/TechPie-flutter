enum FailureKind {
  authenticationExpired,
  authenticationUnconfigured,
  network,
  timeout,
  server,
  protocol,
  invalidInput,
  unavailable,
  permissionDenied,
  credentialMissing,
  offlineAuthorizationExpired,
  offlineQuotaExhausted,
  cancelled,
  unknown,
}

final class AppFailure implements Exception {
  const AppFailure(
    this.kind,
    this.safeMessage, {
    this.code,
    this.retryable = false,
    this.requestNotSent = false,
    this.cause,
  });

  final FailureKind kind;
  final String safeMessage;
  final String? code;
  final bool retryable;

  /// Set only by the transport when no business request was dispatched.
  final bool requestNotSent;

  /// Never display or report this value without an explicit redaction pass.
  final Object? cause;

  @override
  String toString() =>
      'AppFailure(kind: $kind, code: $code, retryable: $retryable)';
}

extension AppFailureAvailability on AppFailure {
  bool get permitsCachedFallback =>
      kind == FailureKind.network ||
      kind == FailureKind.timeout ||
      (kind == FailureKind.server && retryable);
}

extension SessionRecoveryFailure on AppFailure {
  bool get isRecoverableSessionFailure => const {
    'AUTH_SESSION_SUBJECT_CHANGED', 'AUTH_PAYMENT_CONTEXT_EXPIRED',
    'AUTH_VERIFIED_SESSION_MISSING', 'AUTH_IDENTITY_MISMATCH',
    'AUTH_RESPONSE_IDENTITY_MISMATCH', 'AUTH_PINNED_IDENTITY_MISMATCH',
    'AUTH_IDENTITY_FIELDS_MISSING', 'HTTP_401',
  }.contains(code);
}
