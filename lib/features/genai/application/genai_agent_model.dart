import 'dart:async';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';

typedef GenAiAgentChatStream = Stream<GenAiChatEvent> Function(
  GenAiChatRequest request,
  GenAiCancellation cancellation,
);

/// One exchange. Provider-specific persistence is confirmed by ChatFinished;
/// provisional display text never grants authority to execute a tool.
final class GenAiAgentModelExchange {
  GenAiAgentModelExchange(
    this._streamChat,
    String nonce,
    this.maxOutputCharacters,
    this.maxReasoningCharacters,
  ) : _decoder = GenAiAgentFinalStream(nonce);
  final GenAiAgentChatStream _streamChat;
  final GenAiAgentFinalStream _decoder;
  final int maxOutputCharacters;
  final int maxReasoningCharacters;
  bool _confirmed = false;
  GenAiFinishReason? _finish;
  String get source => _decoder.source.trim();

  GenAiAgentDecision decision() {
    if (_finish == GenAiFinishReason.length) {
      throw const GenAiAgentToolException('output_limit', '回复达到输出上限，请缩短后继续。');
    }
    if (!_confirmed) throw const GenAiFailure(GenAiFailureKind.interrupted);
    return _decoder.finish();
  }

  Stream<GenAiAgentEvent> stream(
    GenAiChatRequest request,
    GenAiAgentToolContext context,
    int turn,
  ) async* {
    final iterator = StreamIterator(_streamChat(request, context.cancellation));
    var length = 0;
    var reasoningLength = 0;
    try {
      while (await context.cancellation.race(iterator.moveNext())) {
        context.checkActive();
        if (_finish != null) throw const GenAiFailure(GenAiFailureKind.protocol);
        final event = iterator.current;
        if (event is GenAiTextDelta) length += event.text.length;
        if (event is GenAiReasoningDelta) reasoningLength += event.text.length;
        if (length > maxOutputCharacters || reasoningLength > maxReasoningCharacters) {
          throw const GenAiFailure(GenAiFailureKind.protocol);
        }
        switch (event) {
          case GenAiTextDelta(:final text):
            final delta = _decoder.add(text);
            if (delta.isNotEmpty) {
              yield GenAiAgentEvent(kind: GenAiAgentEventKind.answerDelta, turn: turn, text: delta);
            }
          case GenAiReasoningDelta(:final text):
            yield GenAiAgentEvent(kind: GenAiAgentEventKind.reasoningDelta, turn: turn, text: text);
          case GenAiContextUsageChanged(:final usage):
            yield GenAiAgentEvent(
              kind: GenAiAgentEventKind.contextUsage,
              turn: turn,
              contextUsage: usage,
            );
          case GenAiContextCompacted():
            yield GenAiAgentEvent(kind: GenAiAgentEventKind.contextCompacted, turn: turn);
          case GenAiChatFinished(:final reason):
            _finish = reason;
        }
      }
    } finally {
      iterator.cancel().ignore();
    }
    context.checkActive();
    if (_finish == GenAiFinishReason.length) return;
    if (_finish != GenAiFinishReason.stop && _finish != GenAiFinishReason.done) {
      throw const GenAiFailure(GenAiFailureKind.interrupted);
    }
    _confirmed = true;
  }
}
