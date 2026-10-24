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
  messageTooLarge,
  contextTooLarge,
  attachmentContextUnknown,
}

/// Excludes upstream messages, URLs, tokens, and response bodies.
final class GenAiFailure implements Exception {
  const GenAiFailure(this.kind, {this.statusCode});

  final GenAiFailureKind kind;
  final int? statusCode;

  @override
  String toString() => 'GenAiFailure(${kind.name}, status: $statusCode)';
}
