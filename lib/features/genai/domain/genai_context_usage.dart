/// Preparation of one model request, including optional history compaction.
enum GenAiContextStage { preparing, compacting, ready }

/// Conservative local input accounting, not tokenizer or provider usage data.
/// Text contributes UTF-8 bytes; messages, documents and images add the same
/// policy allowances enforced by the context compactor. The allowed input
/// budget already excludes reserved output and safety headroom.
final class GenAiContextUsage {
  const GenAiContextUsage({
    required this.stage,
    required this.estimatedInputUnits,
    required this.allowedInputUnits,
    required this.originalInputUnits,
    this.completedChunks = 0,
    this.totalChunks = 0,
    this.compacted = false,
  })  : assert(estimatedInputUnits >= 0),
        assert(allowedInputUnits > 0),
        assert(originalInputUnits >= 0),
        assert(completedChunks >= 0 && completedChunks <= totalChunks);

  final GenAiContextStage stage;
  final int estimatedInputUnits;
  final int allowedInputUnits;
  final int originalInputUnits;
  final int completedChunks;
  final int totalChunks;
  final bool compacted;
}
