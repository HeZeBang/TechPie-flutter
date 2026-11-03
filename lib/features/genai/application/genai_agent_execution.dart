import 'dart:async';
import 'dart:convert';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_agent_protocol.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import 'genai_agent_limits.dart';
import 'genai_agent_projection.dart';

/// Per-run sequential execution policy. The shared ledger is in-memory duplicate
/// protection, not a distributed lock or a durable approval store.
final class GenAiAgentToolExecution {
  GenAiAgentToolExecution({
    required this.limits,
    required this.context,
    required this.ledger,
    required this.approvalRequests,
    required this.turnId,
    required this.approve,
    required this.confirmProposalSaved,
    required this.onReceipt,
  });
  final GenAiAgentLimits limits;
  final GenAiAgentToolContext context;
  final Map<String, Map<String, Object?>> ledger;
  final Map<String, int> approvalRequests;
  final String? turnId;
  final GenAiAgentApproval approve;
  final Future<void> Function()? confirmProposalSaved;
  final void Function(Map<String, Object?>) onReceipt;
  final _callIds = <String, String>{};
  final _callResults = <String, Map<String, Object?>>{};
  final _readCalls = <String>{};
  final _reads = <String, ({String value, int count})>{};
  bool noProgress = false;
  GenAiCancellation get cancellation => context.cancellation;

  void _observeRead(String key, Map<String, Object?> result) {
    final value = genAiCanonicalJson(result['result']);
    final previous = _reads[key];
    if (previous?.value != value) {
      // New evidence from any read is progress, even when another lookup remains
      // unchanged. Preserve signatures while resetting repetition counters.
      _reads.updateAll((_, observation) => (value: observation.value, count: 0));
    }
    final count = previous?.value == value ? previous!.count + 1 : 1;
    _reads[key] = (value: value, count: count);
    noProgress = count >= limits.maxUnchangedReads;
  }

  Future<void> _confirmProposal() async {
    context.checkActive();
    try {
      if (confirmProposalSaved != null) await cancellation.race(confirmProposalSaved!());
    } on GenAiFailure catch (error) {
      if (cancellation.isCancelled ||
          error.kind == GenAiFailureKind.accountChanged ||
          error.kind == GenAiFailureKind.cancelled) {
        rethrow;
      }
      throw const GenAiFailure(GenAiFailureKind.storage);
    } catch (_) {
      throw const GenAiFailure(GenAiFailureKind.storage);
    }
    context.checkActive();
  }

  Stream<GenAiAgentEvent> execute(
    GenAiAgentToolCall call,
    GenAiAgentToolRegistry activeTools,
    int turn,
  ) async* {
    final tool = activeTools[call.name]!;
    final fingerprint = '${call.name}:${genAiCanonicalJson(call.arguments)}';
    yield GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolProposed,
      turn: turn,
      call: call,
    );
    Map<String, Object?> result;
    if (_callIds.containsKey(call.id) && _callIds[call.id] != fingerprint) {
      result = genAiToolError(
        call,
        'reused_call_id',
        'Use a fresh call_id for different arguments.',
      );
    } else if (_callResults.containsKey(call.id)) {
      result = _reusedReceipt(call, _callResults[call.id]!);
      if (_readCalls.contains(call.id)) _observeRead(fingerprint, result);
    } else {
      _callIds[call.id] = fingerprint;
      var mutationAttempted = false;
      var effectNotDispatched = false;
      Map<String, Object?> executionFailure(String code, String message) => genAiToolError(
            call,
            mutationAttempted ? 'outcome_unknown' : code,
            mutationAttempted
                ? 'The action may have completed. Verify its status; do not retry.'
                : message,
          );
      String? effectKey;
      final toolCancellation = GenAiCancellation();
      final removeCancellation = cancellation.onCancel(() {
        // Preserve account invalidation when cancelling a child request;
        // a normal stop retains continuation, an account change must not.
        try {
          cancellation.throwIfCancelled();
        } on GenAiFailure catch (failure) {
          toolCancellation.cancel(failure.kind);
        }
      });
      final toolContext = GenAiAgentToolContext(
        cancellation: toolCancellation,
        isCurrent: () {
          context.checkActive();
          return true;
        },
      );
      Future<T> boundedTool<T>(Future<T> future, [Duration? timeout]) => toolCancellation.race(
            future.timeout(
              timeout ?? limits.toolTimeout,
              onTimeout: () {
                toolCancellation.cancel(GenAiFailureKind.timeout);
                throw TimeoutException('Agent tool timed out');
              },
            ),
          );
      try {
        context.checkActive();
        var prepared = await boundedTool(tool.prepare(call.arguments, toolContext));
        context.checkActive();
        final executionTimeout = prepared.executionTimeout ?? limits.toolTimeout;
        if (executionTimeout <= Duration.zero || executionTimeout > limits.maxToolTimeout) {
          throw const GenAiAgentToolException(
            'invalid_timeout',
            'Tool timeout is outside its allowed budget.',
          );
        }
        if (prepared.requiresApproval) {
          final scopedImage = call.name == 'generate_image' && turnId != null;
          final recoveryKey = genAiMutationReceiptKey(call, turnId: turnId);
          effectKey = scopedImage
              ? 'generate_image:turn:${jsonEncode(turnId)}:${prepared.effectKey ?? genAiCanonicalJson(call.arguments)}'
              : '${call.name}:${prepared.effectKey ?? genAiCanonicalJson(call.arguments)}';
          final recovered = ledger[recoveryKey];
          if (!ledger.containsKey(effectKey) && recovered != null) {
            ledger[effectKey] = recovered;
          }
          if (ledger.containsKey(effectKey)) {
            result = _reusedReceipt(call, ledger[effectKey]!);
            _callResults[call.id] = result;
            onReceipt(result);
            yield GenAiAgentEvent(
              kind: GenAiAgentEventKind.toolFinished,
              turn: turn,
              call: call,
              result: result,
            );
            return;
          }
          if (call.name == 'generate_image' && approvalRequests['generate_image:denied'] == 1) {
            throw const GenAiAgentToolException(
              'approval_denied',
              '用户已取消本轮图片生成，请等待新的请求。',
            );
          }
          final priorUnknown = ledger.values.any(
            (receipt) =>
                receipt['name'] == call.name &&
                receipt['error'] is Map &&
                (receipt['error']! as Map)['code'] == 'outcome_unknown',
          );
          if (priorUnknown) {
            final original = prepared;
            prepared = GenAiAgentPreparedTool(
              execute: original.execute,
              onApproved: original.onApproved,
              requiresApproval: original.requiresApproval,
              summary: original.summary,
              executionTimeout: original.executionTimeout,
              effectKey: original.effectKey,
              details: {
                'previous_outcome': '此前有操作结果未确认，可能已完成或扣费。'
                    '请先查看记录；本次确认将提交一项新操作，不会重试或清除旧记录。',
                ...original.details,
              },
            );
          }
          if (ledger.length >= limits.maxMutationRecords) {
            throw const GenAiAgentToolException(
              'mutation_limit',
              'Start a new task before making more changes.',
            );
          }
          final approvalCount = approvalRequests[tool.name] ?? 0;
          if (tool.maxApprovalsPerRun != null && approvalCount >= tool.maxApprovalsPerRun!) {
            throw const GenAiAgentToolException(
              'approval_limit',
              'This tool has reached its confirmation limit for this user message. '
                  'Do not retry, change arguments, or request bulk actions. '
                  'The user must send a new message for another action.',
            );
          }
          approvalRequests[tool.name] = approvalCount + 1;
          // This is a read-back barrier for the model proposal, not a write
          // of approval or outcome. Only a later model request saves receipts.
          await _confirmProposal();
          yield GenAiAgentEvent(
            kind: GenAiAgentEventKind.approvalRequired,
            turn: turn,
            call: call,
            prepared: prepared,
          );
          // Consuming the event may have changed the account before the
          // UI callback opens an approval or displays its private details.
          context.checkActive();
          final accepted = await cancellation.race(approve(tool, call, prepared));
          context.checkActive();
          if (!accepted) {
            if (tool.name == 'generate_image') {
              approvalRequests['generate_image:denied'] = 1;
            }
            result = genAiToolError(
              call,
              'approval_denied',
              '用户已取消，未执行。',
            );
            ledger[effectKey] = result;
            _callResults[call.id] = result;
            onReceipt(result);
            yield GenAiAgentEvent(
              kind: GenAiAgentEventKind.toolFinished,
              turn: turn,
              call: call,
              result: result,
            );
            return;
          }
          prepared.onApproved?.call();
        }
        context.checkActive();
        yield GenAiAgentEvent(
          kind: GenAiAgentEventKind.toolStarted,
          turn: turn,
          call: call,
          prepared: prepared,
        );
        // Yield is a suspension point: check again before execution.
        context.checkActive();
        if (prepared.requiresApproval) {
          // Mark dispatched immediately before invoking the external effect.
          // This receipt is local until carried by the next normal request.
          mutationAttempted = true;
          ledger[effectKey!] = genAiToolError(
            call,
            'outcome_unknown',
            'This action was dispatched. Verify its status; do not repeat it.',
          );
          onReceipt(ledger[effectKey]!);
        }
        final value = await boundedTool(prepared.execute(), executionTimeout);
        context.checkActive();
        activeTools.validateResult(call, value);
        result = genAiToolReceipt(call, value);
      } on GenAiAgentToolException catch (error) {
        effectNotDispatched = error.effectNotDispatched;
        result = genAiToolError(call, error.code, error.message);
      } on TimeoutException {
        result = executionFailure(
          'tool_timeout',
          'The service took too long. You may try another read request.',
        );
      } on GenAiFailure catch (error) {
        if (error.kind == GenAiFailureKind.cancelled ||
            error.kind == GenAiFailureKind.accountChanged ||
            error.kind == GenAiFailureKind.authenticationRequired ||
            error.kind == GenAiFailureKind.storage ||
            cancellation.isCancelled) {
          rethrow;
        }
        result = executionFailure(
          'service_unavailable',
          'The service is unavailable. Check the account connection.',
        );
      } catch (_) {
        result = executionFailure(
          'tool_failed',
          'The tool could not complete this request.',
        );
      } finally {
        removeCancellation();
        toolCancellation.cancel();
      }
      if (mutationAttempted) {
        if (effectNotDispatched) {
          ledger.remove(effectKey);
        } else {
          ledger[effectKey!] = result;
        }
        if (result['ok'] == true) _reads.clear();
      } else if (result['ok'] == true) {
        _readCalls.add(call.id);
        _observeRead(fingerprint, result);
      }
      _callResults[call.id] = result;
    }
    context.checkActive();
    onReceipt(result);
    yield GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: turn,
      call: call,
      result: result,
    );
  }

  static Map<String, Object?> _reusedReceipt(
    GenAiAgentToolCall call,
    Map<String, Object?> result,
  ) =>
      genAiAgentJsonMap({
        ...result,
        'call_id': call.id,
        'name': call.name,
        'reused': true,
      });
}
