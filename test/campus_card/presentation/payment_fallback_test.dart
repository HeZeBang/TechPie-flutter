import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';
import 'package:techpie/features/campus_card/presentation/screens/payment_code_page.dart';

void main() {
  for (final delayedCard in [false, true]) {
    testWidgets(
        'missing offline grant does not loop and online retry survives delayed card=$delayedCard',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final base = await buildDemoRuntime();
      addTearDown(base.dispose);
      await base.auth.signIn(const DemoAuthCredential());
      await base.offlinePayments.removeAllFromThisDevice();
      final pending = Completer<CampusCard?>();
      final payment = _OfflinePayment();
      final observer = _OfflineObserver();
      final runtime = AppRuntime(
          environment: base.environment,
          capabilities: base.capabilities,
          auth: base.auth,
          cards: delayedCard ? _DelayedCard(pending.future) : base.cards,
          paymentCodes: payment,
          scanPayments: base.scanPayments,
          transactions: base.transactions,
          securitySettings: base.securitySettings,
          offlinePayments: base.offlinePayments,
          brightness: base.brightness,
          connectivity: base.connectivity,
          lifecycle: base.lifecycle,
          feedback: base.feedback,);
      await tester.pumpWidget(ProviderScope(
          observers: [observer],
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: const MaterialApp(home: PaymentCodePage()),),);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(payment.calls, 1);
      if (delayedCard) pending.complete(await base.cards.currentCard());
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      final updates = observer.updates;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(observer.updates, updates,
          reason: 'missing authorization must not be invalidated every frame',);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(payment.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

class _OfflineObserver extends ProviderObserver {
  int updates = 0;
  @override
  void didUpdateProvider(ProviderBase<Object?> provider, Object? previousValue,
      Object? newValue, ProviderContainer container,) {
    if (provider == offlineAuthorizationProvider('DEMO-CARD-0001')) updates++;
  }
}

class _OfflinePayment implements PaymentCodeRepository {
  int calls = 0;
  @override
  Future<PaymentCodeFrame> generateOnlineCode() async {
    calls++;
    throw const AppFailure(FailureKind.network, 'test offline',
        code: 'TEST_OFFLINE',);
  }

  @override
  Future<void> activateOnlineCode() async {}
  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode,
          {PaymentRequestContext? context,}) async =>
      const PaymentPending();
}

class _DelayedCard implements CardRepository {
  _DelayedCard(this.pending);
  final Future<CampusCard?> pending;
  @override
  Future<CampusCard?> currentCard() => pending;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
