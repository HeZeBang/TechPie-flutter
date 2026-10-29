import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/app/real_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/app_environment.dart';

void main() {
  // buildRealRuntime() constructs adapters that read WidgetsBinding.instance.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production enables the supported security screens', () {
    final capabilities = AppCapabilities.forEnvironment(
      AppEnvironment.production,
    );
    expect(capabilities.spendingLimits, isTrue);
    expect(capabilities.spendingLimitsRead, isTrue);
    expect(capabilities.changeSpendingPassword, isTrue);
  });

  test('the real composition root composes adapters the demo one does not',
      () async {
    final real = buildRealRuntime(AppEnvironment.staging);
    addTearDown(real.dispose);
    final demo = await buildDemoRuntime();
    addTearDown(demo.dispose);

    // Comparing the composed types says what the old source scan said — the real
    // root never wires a demo adapter — without reading our own source text.
    for (final (name, pair) in [
      ('auth', (real.auth, demo.auth)),
      ('cards', (real.cards, demo.cards)),
      ('paymentCodes', (real.paymentCodes, demo.paymentCodes)),
      ('scanPayments', (real.scanPayments, demo.scanPayments)),
      ('transactions', (real.transactions, demo.transactions)),
      ('securitySettings', (real.securitySettings, demo.securitySettings)),
    ]) {
      expect(
        pair.$1.runtimeType,
        isNot(pair.$2.runtimeType),
        reason: '$name must differ between the real and demo runtimes',
      );
    }

    // The offline payment service is the one adapter the two runtimes share: it is
    // a domain service over ports, and the demo/real difference lives in those
    // ports (covered by test/campus_card/application/offline_payment_service_test).
    expect(real.offlinePayments.runtimeType, demo.offlinePayments.runtimeType);
  });

  test('nothing in the feature logs outside the request trace', () {
    // The trace's own gate (debug mode and explicit opt-in) is behavioural-tested
    // in test/campus_card_http_trace_test.dart; what stays here is the rename-proof
    // half: no stray print/debugPrint anywhere in the feature.
    final loggingCall = RegExp(
      r'(^|[^A-Za-z0-9_])(print|debugPrint|debugPrintSynchronously)\s*\(',
      multiLine: true,
    );
    for (final file in Directory('lib/features/campus_card')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        // The trace is the one place allowed to log; its own gate is covered by
        // test/campus_card_http_trace_test.dart.
        .where(
          (file) => !file.path.endsWith('data/api/decrypted_http_trace.dart'),
        )) {
      expect(
        file.readAsStringSync(),
        isNot(matches(loggingCall)),
        reason: file.path,
      );
    }
  });
}
