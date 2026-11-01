import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';

void main() {
  GenAiAgentToolCall call(String name) =>
      GenAiAgentToolCall(id: 'call-1', name: name, arguments: const {});

  GenAiAgentEvent event(
    GenAiAgentEventKind kind, {
    String? name,
    Map<String, Object?>? result,
  }) =>
      GenAiAgentEvent(
        kind: kind,
        turn: 1,
        call: name == null ? null : call(name),
        result: result,
      );

  const success = {
    'ok': true,
    'result': {'status': 'booked'},
  };
  const rejection = {
    'ok': false,
    'error': {'code': 'approval_denied', 'message': 'The user declined this action.'},
  };
  const failure = {
    'ok': false,
    'error': {'code': 'tool_failed', 'message': 'The tool could not complete this request.'},
  };
  const unknown = {
    'ok': false,
    'error': {'code': 'outcome_unknown', 'message': 'This action may have been dispatched.'},
  };

  test('a proposed call is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolProposed, name: 'reserve_court'),
      ),
      isFalse,
    );
  });

  test('a pending approval is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.approvalRequired, name: 'generate_image'),
      ),
      isFalse,
    );
  });

  test('a started call is not a completed external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolStarted, name: 'reserve_court', result: success),
      ),
      isFalse,
    );
  });

  test('a rejected approval is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'reserve_court', result: rejection),
      ),
      isFalse,
    );
  });

  test('a cancelled event is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.cancelled, name: 'generate_image', result: success),
      ),
      isFalse,
    );
  });

  test('a failed event is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.failed, name: 'generate_image', result: success),
      ),
      isFalse,
    );
  });

  test('a failed tool result is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'reserve_court', result: failure),
      ),
      isFalse,
    );
  });

  test('an unknown-outcome receipt may still be an external effect', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'reserve_court', result: unknown),
      ),
      isTrue,
    );
  });

  test('a missing result is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'reserve_court'),
      ),
      isFalse,
    );
  });

  test('a result without ok is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(
          GenAiAgentEventKind.toolFinished,
          name: 'generate_image',
          result: const {
            'result': {'status': 'generated'},
          },
        ),
      ),
      isFalse,
    );
  });

  test('a call-less event is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, result: success),
      ),
      isFalse,
    );
  });

  test('a successful booking is an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'reserve_court', result: success),
      ),
      isTrue,
    );
  });

  test('a successful image is an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'generate_image', result: success),
      ),
      isTrue,
    );
  });

  test('an unrelated successful read tool is not an external action', () {
    expect(
      genAiHasExternalEffect(
        event(GenAiAgentEventKind.toolFinished, name: 'read_data', result: success),
      ),
      isFalse,
    );
  });

  test('mutation tool names are centralized', () {
    expect(genAiMutationToolNames, {'generate_image', 'reserve_court'});
    expect(genAiIsMutationToolName('generate_image'), isTrue);
    expect(genAiIsMutationToolName('reserve_court'), isTrue);
    expect(genAiIsMutationToolName('get_court_slots'), isFalse);
    expect(genAiIsMutationToolName(null), isFalse);
  });

  test('ledger receipts require an actual booking for reserve_court', () {
    expect(genAiRecordsMutationReceipt('generate_image', const {}), isTrue);
    expect(genAiRecordsMutationReceipt('reserve_court', const {'action': 'book'}), isTrue);
    expect(genAiRecordsMutationReceipt('reserve_court', const {'action': 'search'}), isFalse);
    expect(genAiRecordsMutationReceipt('reserve_court', const {}), isFalse);
    expect(genAiRecordsMutationReceipt('get_court_slots', const {'action': 'book'}), isFalse);
  });

  test('the effect warning stays name-only for non-booking court actions', () {
    // The warning intentionally ignores arguments: a finished reserve_court
    // receipt may describe an uncertain external effect whatever its action.
    expect(
      genAiHasExternalEffect(
        GenAiAgentEvent(
          kind: GenAiAgentEventKind.toolFinished,
          turn: 1,
          call: GenAiAgentToolCall(
            id: 'call-1',
            name: 'reserve_court',
            arguments: const {'action': 'search'},
          ),
          result: success,
        ),
      ),
      isTrue,
    );
  });
}
