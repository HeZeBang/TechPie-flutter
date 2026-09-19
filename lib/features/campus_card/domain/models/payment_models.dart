import '../money_fen.dart';

enum PaymentCodePhase {
  idle,
  initializing,
  activationRequired,
  displaying,
  refreshing,
  polling,
  switchingOffline,
  succeeded,
  failed,
  stopped,
}

enum PaymentConnectionState { unknown, online, apiError, disconnected }

/// Opaque local proof of the account/session that issued a code or challenge.
abstract interface class PaymentRequestContext {}

final class PaymentCodeFrame {
  const PaymentCodeFrame({
    required this.payCode,
    required this.rawQrCode,
    required this.qrPayload,
    required this.offlineAllowed,
    required this.generatedAt,
    this.requestContext,
    this.balance,
    this.balanceChanged = false,
  });

  final MoneyFen? balance;
  final bool balanceChanged;
  final PaymentRequestContext? requestContext;
  final String payCode;
  final String rawQrCode;
  final String qrPayload;
  final bool offlineAllowed;
  final DateTime generatedAt;
}

final class TransactionResult {
  const TransactionResult({
    required this.amount,
    required this.confirmedLocallyAt,
    this.merchantName,
    this.terminalNumber,
    this.tradeAt,
    this.orderId,
    this.balance,
    this.fee,
  });

  final MoneyFen amount;
  final DateTime confirmedLocallyAt;
  final String? merchantName;
  final String? terminalNumber;
  final DateTime? tradeAt;
  final String? orderId;
  final MoneyFen? balance;
  final MoneyFen? fee;
}

sealed class PaymentCodePollResult {
  const PaymentCodePollResult();
}

final class PaymentPending extends PaymentCodePollResult {
  const PaymentPending();
}

final class PaymentCodeExpired extends PaymentCodePollResult {
  const PaymentCodeExpired();
}

final class PaymentCompleted extends PaymentCodePollResult {
  const PaymentCompleted(this.result);
  final TransactionResult result;
}

/// A terminal result that does not confirm a successful payment.
final class PaymentNotCompleted extends PaymentCodePollResult {
  const PaymentNotCompleted({this.reason});
  final String? reason;
}

final class PaymentShouldUseOffline extends PaymentCodePollResult {
  const PaymentShouldUseOffline(this.reason);
  final String reason;
}

final class PaymentCodeViewState {
  const PaymentCodeViewState({
    required this.phase,
    required this.generation,
    this.frame,
    this.result,
    this.message,
    this.connectionState = PaymentConnectionState.unknown,
    this.requestLatency,
  });

  const PaymentCodeViewState.idle()
      : phase = PaymentCodePhase.idle,
        generation = 0,
        frame = null,
        result = null,
        message = null,
        connectionState = PaymentConnectionState.unknown,
        requestLatency = null;

  final PaymentCodePhase phase;
  final int generation;
  final PaymentCodeFrame? frame;
  final TransactionResult? result;
  final String? message;
  final PaymentConnectionState connectionState;
  final Duration? requestLatency;

  PaymentCodeViewState copyWith({
    PaymentCodePhase? phase,
    int? generation,
    PaymentCodeFrame? frame,
    TransactionResult? result,
    String? message,
    PaymentConnectionState? connectionState,
    Duration? requestLatency,
    bool clearMessage = false,
    bool clearLatency = false,
  }) =>
      PaymentCodeViewState(
        phase: phase ?? this.phase,
        generation: generation ?? this.generation,
        frame: frame ?? this.frame,
        result: result ?? this.result,
        message: clearMessage ? null : message ?? this.message,
        connectionState: connectionState ?? this.connectionState,
        requestLatency:
            clearLatency ? null : requestLatency ?? this.requestLatency,
      );
}
