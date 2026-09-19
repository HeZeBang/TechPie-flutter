import '../application/offline_payment_service.dart';
import '../application/payment_code_controller.dart';
import '../application/scan_payment_controller.dart';
import '../core/config/app_environment.dart';
import '../domain/ports/auth_port.dart';
import '../domain/ports/bill_ports.dart';
import '../domain/ports/card_ports.dart';
import '../domain/ports/payment_ports.dart';
import '../domain/ports/platform_ports.dart';
import '../domain/ports/security_ports.dart';

final class AppRuntime {
  const AppRuntime({
    required this.environment,
    required this.capabilities,
    required this.auth,
    required this.cards,
    required this.paymentCodes,
    required this.scanPayments,
    required this.transactions,
    required this.securitySettings,
    required this.offlinePayments,
    required this.brightness,
    required this.connectivity,
    required this.lifecycle,
    required this.feedback,
    this.scanner,
    this.disposeRuntime,
  });

  final AppEnvironment environment;
  final AppCapabilities capabilities;
  final AuthPort auth;
  final CardRepository cards;
  final PaymentCodeRepository paymentCodes;
  final ScanPaymentRepository scanPayments;
  final TransactionHistoryPort transactions;
  final SecuritySettingsPort securitySettings;
  final OfflinePaymentService offlinePayments;
  final BrightnessPort brightness;
  final ConnectivityPort connectivity;
  final AppLifecyclePort lifecycle;
  final FeedbackPort feedback;
  final ScannerPort? scanner;
  final Future<void> Function()? disposeRuntime;

  PaymentCodeExperienceController createPaymentCodeController() =>
      PaymentCodeExperienceController(
        payment: PaymentCodeController(repository: paymentCodes),
        brightness: brightness,
      );

  ScanPaymentController createScanPaymentController() =>
      ScanPaymentController(repository: scanPayments);

  Future<void> dispose() async => disposeRuntime?.call();
}
