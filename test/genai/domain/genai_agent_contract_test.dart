import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

void main() {
  test('linked requests preserve failure reasons and can detach', () async {
    for (final kind in [GenAiFailureKind.timeout, GenAiFailureKind.accountChanged]) {
      final parent = GenAiCancellation();
      final child = GenAiCancellation();
      final detached = GenAiCancellation();
      parent.forwardTo(child);
      parent.forwardTo(detached)();
      parent.cancel(kind);
      expect(
        child.throwIfCancelled,
        throwsA(isA<GenAiFailure>().having((e) => e.kind, 'kind', kind)),
      );
      expect(detached.isCancelled, isFalse);
      final lateChild = GenAiCancellation();
      parent.forwardTo(lateChild);
      expect(
        lateChild.throwIfCancelled,
        throwsA(isA<GenAiFailure>().having((e) => e.kind, 'kind', kind)),
      );
    }
  });

  test('ordinary code fences stream before completion without accepting tool frames', () {
    final stream = GenAiAgentFinalStream('synthetic_nonce_0123456789', allowPlain: true);
    expect(stream.add('```py'), isEmpty);
    expect(stream.add('thon\nprint(1)'), '```python\nprint(1)');
    expect(stream.add('\n```'), '\n```');
    expect(stream.finish().text, contains('print(1)'));
  });

  test('plain finals stream unchanged while control-like output cannot execute', () {
    const nonce = 'plain_final_nonce_012345';
    const body =
        '谱定理：\\(A=Q\\Lambda Q^{T}\\)。\n'
        '```techpie-visual {"title":"谱定理"}\n<p data-latex="A=Q"></p>\n```';
    final decoder = GenAiAgentFinalStream(nonce);
    expect(body.split('').map(decoder.add).join(), body);
    expect(decoder.finish().text, body);
    expect(decodeGenAiAgentFinal(body, allowPlain: true), body);
    expect(decodeGenAiAgentFinal(body), isNull);
    for (final source in [
      '<techpie-call nonce="stale_nonce_012345">{"name":"read_data","arguments":{}}</techpie-call>',
      'I will look it up. <techpie-call>',
      '{"name":"read_data","arguments":{}}',
      '```tool_call\n{"name":"read_data"}\n```',
      '<|open|>call tool="read_data"<|close|>',
      '<techpie-final nonce="stale_nonce_012345">answer</techpie-final>',
    ]) {
      expect(
        () => parseGenAiAgentDecision(source, nonce: nonce),
        throwsA(isA<GenAiAgentToolException>()),
        reason: source,
      );
      expect(
        decodeGenAiAgentFinal(source, allowPlain: true),
        source.startsWith('<techpie-final') ? 'answer' : isNull,
      );
    }
  });

  test('only finished mutations with a successful or uncertain receipt warn of an effect', () {
    const booked = {
      'ok': true,
      'result': {'status': 'booked'},
    };
    bool hasEffect(
      String? name,
      Map<String, Object?>? result, {
      GenAiAgentEventKind kind = GenAiAgentEventKind.toolFinished,
      Map<String, Object?> arguments = const {},
    }) => genAiHasExternalEffect(
      GenAiAgentEvent(
        kind: kind,
        turn: 1,
        call: name == null
            ? null
            : GenAiAgentToolCall(id: 'call', name: name, arguments: arguments),
        result: result,
      ),
    );

    for (final kind in [
      GenAiAgentEventKind.toolProposed,
      GenAiAgentEventKind.approvalRequired,
      GenAiAgentEventKind.toolStarted,
      GenAiAgentEventKind.cancelled,
      GenAiAgentEventKind.failed,
    ]) {
      expect(hasEffect('reserve_court', booked, kind: kind), isFalse, reason: kind.name);
    }
    for (final name in ['generate_image', 'reserve_court']) {
      expect(hasEffect(name, booked), isTrue, reason: name);
    }
    for (final name in ['read_data', null]) {
      expect(hasEffect(name, booked), isFalse, reason: name);
    }
    for (final code in ['approval_denied', 'tool_failed', 'outcome_unknown']) {
      expect(
        hasEffect('reserve_court', {
          'ok': false,
          'error': {'code': code},
        }),
        code == 'outcome_unknown',
        reason: code,
      );
    }
    expect(hasEffect('generate_image', null), isFalse);
    expect(
      hasEffect('generate_image', {
        'result': {'status': 'generated'},
      }),
      isFalse,
    );
    expect(hasEffect('reserve_court', booked, arguments: {'action': 'search'}), isTrue);
  });

  test('ledger receipts require an actual booking for reserve_court', () {
    expect(genAiRecordsMutationReceipt('generate_image', const {}), isTrue);
    expect(genAiRecordsMutationReceipt('reserve_court', const {'action': 'book'}), isTrue);
    expect(genAiRecordsMutationReceipt('reserve_court', const {'action': 'search'}), isFalse);
    expect(genAiRecordsMutationReceipt('reserve_court', const {}), isFalse);
    expect(genAiRecordsMutationReceipt('get_court_slots', const {'action': 'book'}), isFalse);
  });
}
