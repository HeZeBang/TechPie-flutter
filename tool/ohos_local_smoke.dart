// Run only on an isolated local OHOS test device. Credentials are supplied via
// --dart-define-from-file outside the repository and never included in logs.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart'
    show FeedbackEvent;
import 'package:techpie/features/campus_card/platform/scanner/mobile_scanner_session.dart';
import 'package:techpie/main.dart' as host;
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/storage_service.dart';

class LocalOnlyHttpOverrides extends HttpOverrides {
  bool rejectNetwork = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      if (rejectNetwork) throw const SocketException('Offline test: network disabled');
      if (!{'localhost', '127.0.0.1', 'ecard.shanghaitech.edu.cn'}
          .contains(uri.host)) {
        throw StateError('Non-local TechPie or unexpected API request blocked');
      }
      return 'DIRECT';
    };
    return client;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final httpOverrides = LocalOnlyHttpOverrides();
  HttpOverrides.global = httpOverrides;
  const openId = String.fromEnvironment('ECARD_TEST_OPENID');
  if (openId.isEmpty) throw StateError('ECARD_TEST_OPENID is required');
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  await storage.setUseLocalhost(true);
  final service = CampusCardService(storage: storage);
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Localhost OHOS campus card checks')),
      ),
    ),
  );
  var failures = 0;
  Future<bool> check(String name, Future<void> Function() operation) async {
    try {
      await operation().timeout(const Duration(seconds: 60));
      debugPrint('OHOS_SMOKE PASS $name');
      return true;
    } catch (error) {
      if (name == 'scanner-adapter' && error is AppFailure) {
        debugPrint('OHOS_SMOKE CAMERA_DIAGNOSTIC ${error.cause}');
      }
      if (name == 'scanner-image-decode') {
        debugPrint('OHOS_SMOKE DECODE_DIAGNOSTIC $error');
      }
      failures++;
      final reason = error is AppFailure ? error.code : error.runtimeType;
      debugPrint('OHOS_SMOKE FAIL $name $reason');
      return false;
    }
  }

  final authenticated =
      await check('openid-via-localhost', () => service.connect(openId));
  final runtime = service.runtime;
  await check('secure-storage-roundtrip', () async {
    if (await service.readOpenId() != openId) {
      throw StateError('credential mismatch');
    }
  });
  await check('connectivity', () async {
    if (!await runtime.connectivity.isOnline()) throw StateError('offline');
    if (!await runtime.connectivity.changes.first
        .timeout(const Duration(seconds: 5))) {
      throw StateError('offline event');
    }
  });
  await check('brightness-set-and-restore', () async {
    await runtime.brightness.current();
    try {
      await runtime.brightness.set(0.8);
    } finally {
      await runtime.brightness.restore();
    }
  });
  await check('selection-feedback-completes',
      () => runtime.feedback.play(FeedbackEvent.selection),);
  await check('scanner-adapter', () async {
    final scanner = runtime.scanner;
    if (scanner == null) throw StateError('scanner unavailable');
    if (const bool.fromEnvironment('ECARD_TEST_CAMERA')) {
      try {
        await scanner.start();
        await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        await scanner.stop();
      }
    }
  });
  await check('scanner-image-decode', () async {
    const fixture = 'TECHPIE_OHOS_SCANNER_TEST';
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.translate(24, 24);
    QrPainter(data: fixture, version: QrVersions.auto, gapless: true)
        .paint(canvas, const Size(256, 256));
    final image = await recorder.endRecording().toImage(304, 304);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/techpie-qr-test.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    try {
      final result = await (runtime.scanner as MobileScannerSession)
          .controller
          .analyzeImage(file.path);
      if (result == null ||
          !result.barcodes.any((code) => code.rawValue == fixture)) {
        throw StateError('decode mismatch');
      }
    } finally {
      await file.delete();
      image.dispose();
    }
  });
  if (authenticated) {
    await check('card-and-balance', () async {
      final cards = runtime.cards;
      final card = cards is CacheFirstCardRepository
          ? await cards.refreshCard()
          : await cards.currentCard();
      if (card == null || !card.detailsAvailable) {
        throw StateError('missing card');
      }
    });
    await check('profile', () async {
      await runtime.cards.profile();
    });
    await check('online-code', () async {
      final frame = await runtime.paymentCodes.generateOnlineCode();
      if (frame.qrPayload.isEmpty) throw StateError('empty QR');
      await runtime.paymentCodes
          .pollTransaction(frame.payCode, context: frame.requestContext);
    });
    await check('transaction-history-and-detail', () async {
      final now = DateTime.now();
      final page = await runtime.transactions.timeline(
        month: '${now.year}-${now.month.toString().padLeft(2, '0')}',
      );
      if (page.items.isNotEmpty) {
        await runtime.transactions.detail(page.items.first.id);
      }
    });
    await check('spending-limits-read', () async {
      await runtime.securitySettings.readLimits();
    });
    await check('password-form-initialization', () async {
      await runtime.securitySettings.initializePasswordChange();
    });
    await check('offline-authorization-status', () async {
      final card = await runtime.cards.currentCard();
      if (card == null) throw StateError('missing card');
      await runtime.offlinePayments.status(card.id);
    });
    if (const bool.fromEnvironment('ECARD_TEST_OFFLINE')) {
      await check('offline-activation-and-code', () async {
        final card = await runtime.cards.currentCard();
        if (card == null) throw StateError('missing card');
        final existing = await runtime.offlinePayments.mostRecentAuthorization();
        if (existing == null) await runtime.offlinePayments.activate(cardId: card.id);
        final code = await runtime.offlinePayments.generate(card.id);
        if (code.payload.isEmpty || code.hex.isEmpty) throw StateError('empty offline QR');
      });
    }
    if (const bool.fromEnvironment('ECARD_TEST_OFFLINE')) {
      await check('offline-code-with-network-blocked', () async {
        final card = await runtime.cards.currentCard();
        if (card == null) throw StateError('missing card');
        httpOverrides.rejectNetwork = true;
        try {
          final code = await runtime.offlinePayments.generate(card.id);
          if (code.payload.isEmpty) throw StateError('empty offline QR');
        } finally { httpOverrides.rejectNetwork = false; }
      });
    }
    await check('restored-session', () async {
      await runtime.auth.restore();
    });
  }
  debugPrint('OHOS_SMOKE COMPLETE failures=$failures');
  service.dispose();
  host.main([]);
}
