import 'package:flutter/foundation.dart';

import '../domain/genai_cancellation.dart';
import '../domain/genai_context_usage.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import 'genai_conversation_turn.dart';
import 'genai_repository.dart';

export 'genai_conversation_turn.dart' show GenAiChatPhase;

/// UI-independent single-turn controller. It keeps partial output on a failed
/// connection and never silently retries a generation or edits server history.
final class GenAiChatService extends ChangeNotifier {
  GenAiChatService(
    this._repository, {
    this.maxOutputCharacters = 2 * 1024 * 1024,
  });

  final GenAiRepository _repository;
  final int maxOutputCharacters;
  GenAiCancellation? _operation;
  int _turn = 0;
  bool _disposed = false;
  GenAiConversationTurn _state = GenAiConversationTurn('')..phase = GenAiChatPhase.idle;

  String get answer => _state.answer;
  String get reasoning => _state.reasoning;
  GenAiChatPhase get phase => _state.phase;
  GenAiFailure? get failure => _state.failure;
  GenAiFinishReason? get finishReason => _state.finishReason;
  bool get contextCompacted => _state.contextCompacted;
  GenAiContextUsage? get contextUsage => _state.contextUsage;

  Future<void> send(GenAiChatRequest request, {GenAiConversationTurn? target}) async {
    if (_disposed) throw const GenAiFailure(GenAiFailureKind.cancelled);
    if (_operation != null) throw const GenAiFailure(GenAiFailureKind.busy);
    final turn = ++_turn;
    final operation = GenAiCancellation();
    _operation = operation;
    final state = _state = target ?? GenAiConversationTurn(request.prompt);
    final answer = StringBuffer();
    final reasoning = StringBuffer();
    state.phase = GenAiChatPhase.preparing;
    notifyListeners();
    try {
      await for (final event in _repository.streamChat(request, operation)) {
        if (_disposed || turn != _turn) return;
        switch (event) {
          case GenAiContextUsageChanged(:final usage):
            state.contextUsage = usage;
          case GenAiContextCompacted():
            state.contextCompacted = true;
          case GenAiTextDelta(:final text):
            answer.write(text);
            state.answer = answer.toString();
            state.phase = GenAiChatPhase.streaming;
          case GenAiReasoningDelta(:final text):
            reasoning.write(text);
            state.reasoning = reasoning.toString();
            state.phase = GenAiChatPhase.streaming;
          case GenAiChatFinished(:final reason):
            state.finishReason = reason;
            state.phase = GenAiChatPhase.completed;
        }
        if (answer.length + reasoning.length > maxOutputCharacters) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        notifyListeners();
      }
    } catch (error) {
      if (_disposed || turn != _turn) return;
      state.contextUsage = null;
      state.failure =
          error is GenAiFailure ? error : const GenAiFailure(GenAiFailureKind.transport);
      state.phase = switch (state.failure!.kind) {
        GenAiFailureKind.authenticationRequired => GenAiChatPhase.needsLogin,
        GenAiFailureKind.interrupted ||
        GenAiFailureKind.transport ||
        GenAiFailureKind.timeout =>
          GenAiChatPhase.interrupted,
        GenAiFailureKind.cancelled => GenAiChatPhase.cancelled,
        _ => GenAiChatPhase.failed,
      };
      if (state.failure!.kind == GenAiFailureKind.accountChanged) {
        state.answer = '';
        state.reasoning = '';
      }
      notifyListeners();
    } finally {
      operation.cancel();
      if (identical(_operation, operation)) _operation = null;
    }
  }

  void stop() {
    if (_operation == null) return;
    _state.contextUsage = null;
    _operation!.cancel();
    _operation = null;
    _turn++;
    _state.phase = GenAiChatPhase.cancelled;
    notifyListeners();
  }

  void clear() {
    _operation?.cancel(GenAiFailureKind.accountChanged);
    _operation = null;
    _turn++;
    _state = GenAiConversationTurn('')..phase = GenAiChatPhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation?.cancel();
    super.dispose();
  }
}
