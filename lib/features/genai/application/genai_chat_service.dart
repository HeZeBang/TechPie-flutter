import 'package:flutter/foundation.dart';

import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import 'genai_repository.dart';

enum GenAiChatPhase {
  idle,
  preparing,
  streaming,
  completed,
  interrupted,
  cancelled,
  failed,
  needsLogin
}

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
  StringBuffer _answer = StringBuffer();
  StringBuffer _reasoning = StringBuffer();
  GenAiChatPhase _phase = GenAiChatPhase.idle;
  GenAiFailure? _failure;
  GenAiFinishReason? _finishReason;

  String get answer => _answer.toString();
  String get reasoning => _reasoning.toString();
  GenAiChatPhase get phase => _phase;
  GenAiFailure? get failure => _failure;
  GenAiFinishReason? get finishReason => _finishReason;

  Future<void> send(GenAiChatRequest request) async {
    if (_disposed) throw const GenAiFailure(GenAiFailureKind.cancelled);
    if (_operation != null) throw const GenAiFailure(GenAiFailureKind.busy);
    final turn = ++_turn;
    final operation = GenAiCancellation();
    _operation = operation;
    _answer = StringBuffer();
    _reasoning = StringBuffer();
    _failure = null;
    _finishReason = null;
    _phase = GenAiChatPhase.preparing;
    notifyListeners();
    try {
      await for (final event in _repository.streamChat(request, operation)) {
        if (_disposed || turn != _turn) return;
        switch (event) {
          case GenAiTextDelta(:final text):
            _answer.write(text);
            _phase = GenAiChatPhase.streaming;
          case GenAiReasoningDelta(:final text):
            _reasoning.write(text);
            _phase = GenAiChatPhase.streaming;
          case GenAiChatFinished(:final reason):
            _finishReason = reason;
            _phase = GenAiChatPhase.completed;
        }
        if (_answer.length + _reasoning.length > maxOutputCharacters) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        notifyListeners();
      }
    } catch (error) {
      if (_disposed || turn != _turn) return;
      _failure = error is GenAiFailure
          ? error
          : const GenAiFailure(GenAiFailureKind.transport);
      _phase = switch (_failure!.kind) {
        GenAiFailureKind.authenticationRequired => GenAiChatPhase.needsLogin,
        GenAiFailureKind.interrupted ||
        GenAiFailureKind.transport ||
        GenAiFailureKind.timeout =>
          GenAiChatPhase.interrupted,
        GenAiFailureKind.cancelled => GenAiChatPhase.cancelled,
        _ => GenAiChatPhase.failed,
      };
      if (_failure!.kind == GenAiFailureKind.accountChanged) {
        _answer = StringBuffer();
        _reasoning = StringBuffer();
      }
      notifyListeners();
    } finally {
      operation.cancel();
      if (identical(_operation, operation)) _operation = null;
    }
  }

  void stop() {
    if (_operation == null) return;
    _operation!.cancel();
    _operation = null;
    _turn++;
    _phase = GenAiChatPhase.cancelled;
    notifyListeners();
  }

  void clear() {
    _operation?.cancel(GenAiFailureKind.accountChanged);
    _operation = null;
    _turn++;
    _answer = StringBuffer();
    _reasoning = StringBuffer();
    _phase = GenAiChatPhase.idle;
    _failure = null;
    _finishReason = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation?.cancel();
    super.dispose();
  }
}
