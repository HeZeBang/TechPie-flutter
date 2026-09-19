import '../money_fen.dart';
import 'payment_models.dart';

enum ScanSuccessKind { payment, attendance, openDevice, bindTray, unknown }

sealed class ScanPaymentResult {
  const ScanPaymentResult();
}

final class ScanPasswordRequired extends ScanPaymentResult {
  const ScanPasswordRequired({required this.serverQrCode, this.context});
  final PaymentRequestContext? context;
  final String serverQrCode;
}

final class ScanSucceeded extends ScanPaymentResult {
  const ScanSucceeded({
    required this.kind,
    this.amount,
    this.fee,
    this.balance,
    this.message,
    this.paidAt,
    this.authorizationCode,
    this.transactionId,
    this.terminalCode,
    this.transactionCode,
  });

  final ScanSuccessKind kind;
  final MoneyFen? amount;
  final MoneyFen? fee;
  final MoneyFen? balance;
  final String? message;
  final DateTime? paidAt;
  final String? authorizationCode;
  final String? transactionId;
  final String? terminalCode;
  final String? transactionCode;
}

final class ScanFailed extends ScanPaymentResult {
  const ScanFailed({required this.message, this.code});
  final String message;
  final String? code;
}

enum ScanFlowPhase { idle, submitting, passwordRequired, succeeded, failed }

final class ScanFlowState {
  const ScanFlowState({
    required this.phase,
    this.pendingServerQrCode,
    this.pendingContext,
    this.success,
    this.message,
  });

  const ScanFlowState.idle()
      : phase = ScanFlowPhase.idle,
        pendingServerQrCode = null,
        pendingContext = null,
        success = null,
        message = null;

  final ScanFlowPhase phase;
  final String? pendingServerQrCode;
  final PaymentRequestContext? pendingContext;
  final ScanSucceeded? success;
  final String? message;
}
