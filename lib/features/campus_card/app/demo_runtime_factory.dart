import 'dart:math';

import 'package:clock/clock.dart';

import '../application/offline_payment_service.dart';
import '../core/config/app_environment.dart';
import '../data/auth/auth_ports.dart';
import '../data/crypto/sm2_offline_crypto.dart';
import '../data/mock/demo_repositories.dart';
import '../data/mock/demo_scenarios.dart';
import '../data/mock/in_memory_ports.dart';
import '../data/storage/secure_offline_credential_repository.dart';
import 'app_runtime.dart';

Future<AppRuntime> buildDemoRuntime() async {
  final fixedClock = Clock.fixed(DateTime.utc(2026, 8, 31, 12));
  final scenario = DemoScenarioController();
  final secureStore = InMemorySecureCredentialStore();
  final offlineCredentials = SecureOfflineCredentialRepository(secureStore);
  final connectivity = InMemoryConnectivityPort();
  final brightness = InMemoryBrightnessPort();
  final lifecycle = InMemoryLifecyclePort();
  final feedback = InMemoryFeedbackPort();
  final scanner = InMemoryScannerPort();
  Future<void> purge() => offlineCredentials.removeAll();
  final auth = DemoAuthPort(cleanup: purge);
  final offline = OfflinePaymentService(
    credentials: offlineCredentials,
    remote: DemoOfflineAuthorizationRemotePort(scenario, clock: fixedClock),
    connectivity: connectivity,
    crypto: Sm2OfflineCrypto(random: Random(0x4745454b)),
    deviceCodeReader: () async => 'DEMO-DEVICE-0001',
    clock: fixedClock,
  );
  await offline.activate(cardId: 'DEMO-CARD-0001');
  return AppRuntime(
    environment: AppEnvironment.demo,
    capabilities: AppCapabilities.forEnvironment(AppEnvironment.demo),
    auth: auth,
    cards: DemoCardRepository(scenario, onUnbind: purge),
    paymentCodes: DemoPaymentCodeRepository(scenario, clock: fixedClock),
    scanPayments: DemoScanPaymentRepository(scenario),
    transactions: DemoTransactionHistoryPort(clock: fixedClock),
    securitySettings: DemoSecuritySettingsPort(),
    offlinePayments: offline,
    brightness: brightness,
    connectivity: connectivity,
    lifecycle: lifecycle,
    feedback: feedback,
    scanner: scanner,
    disposeRuntime: scanner.stop,
  );
}
