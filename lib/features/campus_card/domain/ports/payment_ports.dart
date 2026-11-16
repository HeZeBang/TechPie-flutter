import '../models/payment_models.dart';
import '../models/scan_models.dart';

abstract interface class PaymentCodeRepository {
  Future<PaymentCodeFrame> generateOnlineCode();
  Future<void> activateOnlineCode();
  Future<PaymentCodePollResult> pollTransaction(String payCode,
      {PaymentRequestContext? context,});
}

abstract interface class ScanPaymentRepository {
  Future<ScanPaymentResult> submit({
    required String qrCode,
    required DateTime payTime,
    String? password,
    PaymentRequestContext? context,
  });
}
