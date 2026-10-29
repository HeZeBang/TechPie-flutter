import 'dart:convert';

import '../domain/genai_context_record.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_remote_record.dart';
import 'genai_conversation_turn.dart';
import 'genai_remote_history.dart';

/// A server-record suffix, never an individual model step within an agent turn.
/// Delete removes the selected turn and descendants; revert keeps that turn.
final class GenAiHistoryEdit {
  GenAiHistoryEdit._(this.removedIds, this.retained);

  final List<String> removedIds;
  final List<GenAiSavedTurn> retained;

  factory GenAiHistoryEdit.plan(
    String groupId,
    List<GenAiSavedTurn> rows,
    String turnId, {
    bool keepTurn = false,
  }) {
    final turns = decodeGenAiConversation(groupId, rows).archive.restoreTurns();
    final index = turns.indexWhere((turn) => turn.id == turnId);
    if (index < 0 || turns.any((turn) => turn.isHistoryGap)) {
      throw const GenAiFailure(GenAiFailureKind.historyChanged);
    }
    final keep = index + (keepTurn ? 1 : 0);
    final removed = turns.skip(keep).map((turn) => turn.id).toSet();
    if (removed.isEmpty) return GenAiHistoryEdit._(const [], rows);
    var cut = rows.length;
    for (var i = 0; i < rows.length; i++) {
      final record = decodeGenAiRemoteRecord(rows[i].prompt);
      if (record != null) {
        final source = record['turn'];
        final id = source is Map ? source['id'] : record['turn_id'];
        final rawStopped = record['interrupted'];
        final stopped = rawStopped is List ? rawStopped : const <Object?>[];
        if (removed.contains(id) ||
            stopped.any((raw) => raw is Map && removed.contains(raw['id']))) {
          cut = i;
          break;
        }
      } else if (!isGenAiContextExtraction(rows[i].prompt)) {
        // Legacy tool exchanges have no turn IDs. Use the same importer as
        // recovery instead of guessing boundaries from text or call markers.
        final prefix = decodeGenAiConversation(groupId, rows.sublist(0, i + 1));
        if (prefix.archive.restoreTurns().any((turn) => removed.contains(turn.id))) {
          cut = i;
          break;
        }
      }
    }
    // Extraction rows are caches of source history, not user messages. Remove
    // them even if stored out of order. Retained checkpoints are source-hash
    // validated by the compactor before reuse.
    String contents(Iterable<GenAiConversationTurn> values) => jsonEncode([
          for (final turn in values) turn.toArchiveJson(),
        ]);
    final expected = contents(turns.take(keep));
    List<GenAiSavedTurn> retained = const [];
    // Retry branches can precede the selected turn in the physical log. Trim
    // abandoned siblings too, or deleting a retry would revive its old answer.
    if (keep == 0) cut = 0;
    while (cut >= 0) {
      retained = rows.take(cut).where((row) => !isGenAiContextExtraction(row.prompt)).toList();
      final recovered = decodeGenAiConversation(groupId, retained).archive.restoreTurns();
      if (contents(recovered) == expected) break;
      cut--;
    }
    // Interleaved late writes must not cut a retained agent turn in half.
    if (cut < 0 ||
        rows.any((row) => row.recordId == null || row.recordId!.isEmpty) ||
        rows.map((row) => row.recordId).toSet().length != rows.length) {
      throw const GenAiFailure(GenAiFailureKind.historyChanged);
    }
    final retainedIds = retained.map((row) => row.recordId).toSet();
    final deleted = rows.where((row) => !retainedIds.contains(row.recordId));
    return GenAiHistoryEdit._(
      List.unmodifiable(deleted.map((row) => row.recordId!)),
      List.unmodifiable(retained),
    );
  }
}
