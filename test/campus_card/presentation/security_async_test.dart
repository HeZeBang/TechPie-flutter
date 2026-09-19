import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/domain/models/security_models.dart';
import 'package:techpie/features/campus_card/domain/ports/security_ports.dart';
import 'package:techpie/features/campus_card/presentation/screens/security_password_screen.dart';

void main() {
  testWidgets(
      'password completion after leaving does not touch disposed fields',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final base = await buildDemoRuntime();
    addTearDown(base.dispose);
    final security = _DelayedSecurity(base.securitySettings);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRuntimeProvider.overrideWithValue(_runtime(base, security)),
        ],
        child: const MaterialApp(home: SecurityPasswordScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), '123456');
    await tester.enterText(fields.at(1), '654321');
    await tester.enterText(fields.at(2), '654321');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(security.passwordCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    security.pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final qr in [false, true]) {
    test(
        'limits completion after provider replacement preserves current state (qr=$qr)',
        () async {
      final base = await buildDemoRuntime();
      addTearDown(base.dispose);
      final security = _DelayedSecurity(base.securitySettings);
      final container = ProviderContainer(overrides: [
        appRuntimeProvider.overrideWithValue(_runtime(base, security)),
      ],);
      addTearDown(container.dispose);
      final sub =
          container.listen(spendingLimitsControllerProvider, (_, __) {});
      addTearDown(sub.close);
      final limits =
          await container.read(spendingLimitsControllerProvider.future);
      final notifier =
          container.read(spendingLimitsControllerProvider.notifier);
      final pending = qr
          ? notifier.saveQrLimits(limits, transactionPassword: '123456')
          : notifier.saveCardLimits(limits);
      container.invalidate(spendingLimitsControllerProvider);
      await container.read(spendingLimitsControllerProvider.future);
      final reads = security.reads;
      security.pending.complete();
      await pending;
      expect(security.reads, reads);
      expect(container.read(spendingLimitsControllerProvider).hasValue, isTrue);
    });
  }
}

AppRuntime _runtime(AppRuntime base, SecuritySettingsPort security) =>
    AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: base.auth,
      cards: base.cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: security,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
    );

class _DelayedSecurity implements SecuritySettingsPort {
  _DelayedSecurity(this.delegate);
  final SecuritySettingsPort delegate;
  final pending = Completer<void>();
  int passwordCalls = 0;
  int reads = 0;
  @override
  Future<SpendingPasswordInitialization> initializePasswordChange() =>
      delegate.initializePasswordChange();
  @override
  Future<SpendingLimits> readLimits() {
    reads++;
    return delegate.readLimits();
  }

  @override
  Future<void> changeSpendingPassword(
      {required String accountKey,
      required String oldPassword,
      required String newPassword,}) {
    passwordCalls++;
    return pending.future;
  }

  @override
  Future<void> updateCardLimits(SpendingLimits limits) => pending.future;
  @override
  Future<void> updateQrLimits(SpendingLimits limits,
          {required String transactionPassword,}) =>
      pending.future;
}
