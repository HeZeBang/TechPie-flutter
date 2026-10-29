enum GenAiFailureKind {
  authenticationRequired,
  identityMismatch,
  accountChanged,
  cancelled,
  timeout,
  transport,
  protocol,
  rejected,
  interrupted,
  storage,
  busy,
  historyChanged,
  messageTooLarge,
  contextTooLarge,
  attachmentContextUnknown,
}

/// Excludes upstream messages, URLs, tokens, and response bodies.
final class GenAiFailure implements Exception {
  const GenAiFailure(this.kind, {this.statusCode, this.effectNotDispatched = false});

  final GenAiFailureKind kind;
  final int? statusCode;

  /// True only for a response explicitly identifying a pre-execution rejection.
  final bool effectNotDispatched;

  @override
  String toString() => 'GenAiFailure(${kind.name}, status: $statusCode)';
}
