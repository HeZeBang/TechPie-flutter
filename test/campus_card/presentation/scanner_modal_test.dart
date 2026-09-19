import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/scan_payment_preferences.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_scan_payment_repository.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/ports/payment_ports.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scan_result_content.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scanner_modal.dart';
import 'package:techpie/features/campus_card/presentation/scanner/six_digit_password_panel.dart';

import '../support/fake_ecard_transport.dart';
import '../support/scan_password_challenge.dart';
import '../support/scan_payment_receipt.dart';

void main() {
  testWidgets(
      'captured limit challenge opens password panel and retries server QR',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/scan/scanningResult', scanPasswordChallenge)
      ..enqueue('POST', '/scan/scanningResult', scanPaymentReceipt);
    final scanner = InMemoryScannerPort();
    final (base, runtime) = await _scannerRuntime(
      scanner,
      scanPayments: EcardScanPaymentRepository(transport),
    );
    addTearDown(base.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(home: ScannerModal(onClose: () {})),
      ),
    );
    await tester.pumpAndSettle();
    scanner.emit('SYNTHETIC-CLIENT-QR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.byType(SixDigitPasswordPanel), findsOneWidget);
    expect(scanner.running, isFalse);
    expect(transport.requests, hasLength(1));
    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      await tester.tap(
        find.descendant(
          of: find.byType(SixDigitPasswordPanel),
          matching: find.text(digit),
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(2));
    expect(transport.requests.last.data['qrcode'], 'SYNTHETIC%20SERVER-QR');
    expect(transport.requests.last.data['password'], '123456');
    expect(find.byType(SixDigitPasswordPanel), findsNothing);
    expect(find.text('¥6.17'), findsOneWidget);
    expect(find.text('授权码 A1B2'), findsOneWidget);
    expect(find.text('CORE10008'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScannerModal)),
    );
    expect(
      container.read(scanPaymentControllerProvider).phase,
      ScanFlowPhase.succeeded,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('rebuilding scanner transitions does not retain status listeners', () {
    final animation = _CountingAnimation();
    for (var i = 0; i < 20; i++) {
      gpScannerEntranceTransition(
        animation,
        const SizedBox(),
        reduceMotion: false,
      );
      gpScannerPopupTransition(
        animation,
        const SizedBox(),
        reduceMotion: false,
      );
    }
    expect(animation.statusListeners, 0);
  });

  group('ScanFailureContent', () {
    testWidgets('renders server-provided message and rescan action', (
      tester,
    ) async {
      var rescanned = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScanFailureContent(
            message: '无效的支付码',
            onRescan: () => rescanned = true,
          ),
        ),
      );

      expect(find.text('识别失败'), findsOneWidget);
      expect(find.text('无效的支付码'), findsOneWidget);

      await tester.tap(find.text('重新扫码'));
      await tester.pump();
      expect(rescanned, isTrue);
    });
  });

  group('gpScannerEntranceTransition', () {
    testWidgets('normal mode produces a slide transition', (tester) async {
      const controller = AlwaysStoppedAnimation<double>(1);
      final result = gpScannerEntranceTransition(
        controller,
        const Text('scanner'),
        reduceMotion: false,
      );
      expect(result, isA<SlideTransition>());
    });

    testWidgets('Reduce Motion produces a fade transition, never zero slide', (
      tester,
    ) async {
      const controller = AlwaysStoppedAnimation<double>(1);
      final result = gpScannerEntranceTransition(
        controller,
        const Text('scanner'),
        reduceMotion: true,
      );
      expect(result, isA<FadeTransition>());
    });
  });

  group('gpScannerPopupTransition', () {
    testWidgets('normal mode fades and moves the popup', (tester) async {
      const controller = AlwaysStoppedAnimation<double>(1);
      final result = gpScannerPopupTransition(
        controller,
        const Text('popup'),
        reduceMotion: false,
      );
      expect(result, isA<FadeTransition>());
      expect((result as FadeTransition).child, isA<SlideTransition>());
    });

    testWidgets('Reduce Motion keeps a fade-only popup', (tester) async {
      const controller = AlwaysStoppedAnimation<double>(1);
      final result = gpScannerPopupTransition(
        controller,
        const Text('popup'),
        reduceMotion: true,
      );
      expect(result, isA<FadeTransition>());
      expect((result as FadeTransition).child, isA<Text>());
    });
  });

  testWidgets('closing the scanner releases its camera after unmount',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = InMemoryScannerPort();
    final (base, runtime) = await _scannerRuntime(scanner);
    addTearDown(base.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(home: ScannerModal(onClose: () {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(scanner.running, isTrue);
    final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(ScannerModal),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    );
    expect(overlay.value.systemNavigationBarColor, Colors.black);
    expect(overlay.value.statusBarIconBrightness, Brightness.light);

    final mask = find.byKey(const Key('scanner-mask'));
    expect(mask, findsOneWidget);
    expect(
      tester.renderObject(mask),
      paints..everything((method, arguments) => method != #saveLayer),
    );
    final painter = tester.widget<CustomPaint>(mask).painter!;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(400, 800));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 800);
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int alpha(int x, int y) => pixels.getUint8((y * 400 + x) * 4 + 3);
      expect(
        alpha(200, 344),
        0,
        reason: 'The scan window remains transparent.',
      );
      expect(
        alpha(10, 10),
        closeTo(122, 1),
        reason: 'The outside dimming is unchanged.',
      );
      expect(
        alpha(70, 189),
        255,
        reason: 'The white corner marks remain visible.',
      );
      image.dispose();
      picture.dispose();
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(scanner.running, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asks for confirmation before submitting a scan by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = InMemoryScannerPort();
    final (base, runtime) = await _scannerRuntime(scanner);
    addTearDown(base.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(home: ScannerModal(onClose: () {})),
      ),
    );
    await tester.pumpAndSettle();

    scanner.emit('SYNTHETIC-SCAN-CODE');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text('是否继续扫码交易？'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('scan-confirmation-popup')),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('¥'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScannerModal)),
    );
    expect(
      container.read(scanPaymentControllerProvider).phase,
      ScanFlowPhase.idle,
    );

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(
      container.read(scanPaymentControllerProvider).phase,
      ScanFlowPhase.succeeded,
    );
  });

  testWidgets('submits immediately when scan confirmation is skipped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final scanner = InMemoryScannerPort();
    final (base, runtime) = await _scannerRuntime(scanner);
    addTearDown(base.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
        child: MaterialApp(home: ScannerModal(onClose: () {})),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ScannerModal)),
    );
    await container
        .read(skipScanConfirmationProvider.notifier)
        .setEnabled(true);

    scanner.emit('SYNTHETIC-SCAN-CODE');
    await tester.pumpAndSettle();

    expect(find.text('是否继续扫码交易？'), findsNothing);
    expect(
      container.read(scanPaymentControllerProvider).phase,
      ScanFlowPhase.succeeded,
    );
  });

  for (final skipConfirmation in [false, true]) {
    testWidgets('repeated detections submit once (skip=$skipConfirmation)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final scanner = InMemoryScannerPort();
      final repository = _CountingScanRepository();
      final (base, runtime) = await _scannerRuntime(
        scanner,
        scanPayments: repository,
      );
      addTearDown(base.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appRuntimeProvider.overrideWithValue(runtime)],
          child: MaterialApp(home: ScannerModal(onClose: () {})),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScannerModal)),
      );
      await container
          .read(skipScanConfirmationProvider.notifier)
          .setEnabled(skipConfirmation);
      for (var i = 0; i < 5; i++) {
        scanner.emit('SYNTHETIC-REPEATED-CODE');
      }
      await tester.pumpAndSettle();
      if (!skipConfirmation) {
        expect(repository.submissions, 0);
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
      }
      scanner.emit('SYNTHETIC-LATE-FRAME');
      await tester.pumpAndSettle();
      expect(repository.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

Future<(AppRuntime, AppRuntime)> _scannerRuntime(
  InMemoryScannerPort scanner, {
  ScanPaymentRepository? scanPayments,
}) async {
  final base = await buildDemoRuntime();
  final runtime = AppRuntime(
    environment: base.environment,
    capabilities: base.capabilities,
    auth: base.auth,
    cards: base.cards,
    paymentCodes: base.paymentCodes,
    scanPayments: scanPayments ?? base.scanPayments,
    transactions: base.transactions,
    securitySettings: base.securitySettings,
    offlinePayments: base.offlinePayments,
    brightness: base.brightness,
    connectivity: base.connectivity,
    lifecycle: base.lifecycle,
    feedback: base.feedback,
    scanner: scanner,
  );
  return (base, runtime);
}

class _CountingScanRepository implements ScanPaymentRepository {
  int submissions = 0;

  @override
  Future<ScanPaymentResult> submit({
    required String qrCode,
    required DateTime payTime,
    String? password,
    PaymentRequestContext? context,
  }) async {
    submissions++;
    return const ScanSucceeded(kind: ScanSuccessKind.payment);
  }
}

class _CountingAnimation extends AlwaysStoppedAnimation<double> {
  _CountingAnimation() : super(0.5);
  int statusListeners = 0;

  @override
  void addStatusListener(AnimationStatusListener listener) => statusListeners++;

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      statusListeners--;
}
