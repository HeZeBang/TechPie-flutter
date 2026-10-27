/// Preparation of one model request, including optional history compaction.
enum GenAiContextStage { preparing, compacting, ready }

/// Conservative local input accounting, not tokenizer or provider usage data.
/// Text uses a conservative token estimate; messages, documents and images add the same
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

  /// Only completed accounting is portable; never restore a live progress phase.
  Map<String, Object?>? toRecord() => stage != GenAiContextStage.ready
      ? null
      : {
          'input': estimatedInputUnits,
          'limit': allowedInputUnits,
          'original': originalInputUnits,
          'compacted': compacted,
        };

  /// Optional display metadata must not make an otherwise valid chat unreadable.
  static GenAiContextUsage? fromRecord(Object? value) {
    if (value is! Map) return null;
    final input = value['input'];
    final limit = value['limit'];
    final original = value['original'];
    final compacted = value['compacted'];
    if (input is! int ||
        input < 0 ||
        limit is! int ||
        limit <= 0 ||
        original is! int ||
        original < 0 ||
        compacted is! bool) {
      return null;
    }
    return GenAiContextUsage(
      stage: GenAiContextStage.ready,
      estimatedInputUnits: input,
      allowedInputUnits: limit,
      originalInputUnits: original,
      compacted: compacted,
    );
  }

  final GenAiContextStage stage;
  final int estimatedInputUnits;
  final int allowedInputUnits;
  final int originalInputUnits;
  final int completedChunks;
  final int totalChunks;
  final bool compacted;
}
