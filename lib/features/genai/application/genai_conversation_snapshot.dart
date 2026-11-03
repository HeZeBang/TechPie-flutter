import '../domain/genai_agent_contract.dart';
import 'genai_conversation_turn.dart';

/// Reconstructed server data. The reader owns the mutable turns; this is not a store.
final class GenAiConversationSnapshot {
  GenAiConversationSnapshot({
    required this.id,
    required this.title,
    required this.updatedAt,
    DateTime? lastMessageAt,
    required List<GenAiConversationTurn> turns,
    required this.agentEnabled,
    required this.thinkingEnabled,
    required this.modelAiType,
    required this.modelRootAiType,
    required Map<String, Object?> mutations,
    Map<String, Object?> contextMemory = const {},
  })  : turns = List.unmodifiable(turns.map((turn) => turn.snapshot())),
        lastMessageAt = lastMessageAt ?? updatedAt,
        mutations = genAiAgentJsonMap(mutations),
        contextMemory = genAiAgentJsonMap(contextMemory);

  final String id;
  final String title;
  final DateTime updatedAt;
  final DateTime lastMessageAt;
  final List<GenAiConversationTurn> turns;
  final bool agentEnabled;
  final bool thinkingEnabled;
  final String? modelAiType;
  final String? modelRootAiType;
  final Map<String, Object?> mutations;
  final Map<String, Object?> contextMemory;
  bool get isEmpty => turns.isEmpty;
}
