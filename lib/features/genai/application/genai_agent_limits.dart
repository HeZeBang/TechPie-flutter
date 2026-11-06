final class GenAiAgentLimits {
  const GenAiAgentLimits({
    this.maxTurns = 12,
    this.maxProtocolErrors = 2,
    this.maxTotalProtocolErrors = 4,
    this.maxUnchangedReads = 3,
    this.maxOutputCharacters = 128 * 1024,
    this.maxToolResultCharacters = 6000,
    this.maxMutationRecords = 64,
    this.runTimeout = const Duration(minutes: 10),
    this.toolTimeout = const Duration(seconds: 60),
    this.maxToolTimeout = const Duration(minutes: 6),
  });

  final int maxTurns;
  final int maxProtocolErrors;
  final int maxTotalProtocolErrors;
  final int maxUnchangedReads;
  final int maxOutputCharacters;
  static const maxReasoningCharacters = 128 * 1024;
  final int maxToolResultCharacters;
  final int maxMutationRecords;
  final Duration runTimeout;
  final Duration toolTimeout;
  final Duration maxToolTimeout;
}
