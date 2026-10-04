import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/platform/scanner/mobile_scanner_session.dart';

void main() {
  test('startup errors stored by the controller are surfaced and remain retryable', () async {
    final controller = _FailedScannerController();
    final session = MobileScannerSession(controller: controller);
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(session.start(), throwsA(isA<AppFailure>().having(
        (error) => error.code, 'code', 'SCANNER_START_FAILED',
      ),),);
    }
    expect(controller.attempts, 2);
    await session.dispose();
  });

  test('permission transitions serialize camera start, stop and restart',
      () async {
    final controller = _DelayedScannerController();
    final session = MobileScannerSession(controller: controller);
    final start = session.start();
    await Future<void>.delayed(Duration.zero);
    final stop = session.stop();
    final restart = session.start();
    expect(controller.events, ['start']);
    controller.permission.complete();
    await Future.wait([start, stop, restart]);
    expect(controller.events, ['start', 'stop', 'start']);
    await session.dispose();
    expect(controller.events, ['start', 'stop', 'start', 'stop', 'dispose']);
  });

  test('a freeze pauses the camera without releasing its session', () async {
    final controller = _DelayedScannerController();
    final session = MobileScannerSession(controller: controller);
    final start = session.start();
    controller.permission.complete();
    await start;

    await session.freeze();
    // Releasing here would take the frozen last frame with it, and the code the
    // result is being read against would disappear behind it.
    expect(controller.events, ['start', 'freeze']);

    await session.start();
    expect(controller.events, ['start', 'freeze', 'start']);

    await session.dispose();
    expect(controller.events, ['start', 'freeze', 'start', 'stop', 'dispose']);
  });

  test('a start resolves only once the preview reports its first frame',
      () async {
    final controller = _DelayedScannerController()..holdPreview = true;
    final session = MobileScannerSession(controller: controller);
    final start = session.start();
    controller.permission.complete();
    await Future<void>.delayed(Duration.zero);

    // The platform accepted the request, but no picture is on screen yet: what
    // un-covers the preview is still waiting, which is the whole point — the
    // frame before it is the previous session's.
    var live = false;
    unawaited(start.then((_) => live = true));
    await Future<void>.delayed(Duration.zero);
    expect(controller.events, ['start']);
    expect(live, isFalse);

    controller.previewFrames.add(null);
    await start;
    expect(live, isTrue);

    await session.dispose();
  });

  test('duplicate starts share a running camera and disposal waits for startup',
      () async {
    final controller = _DelayedScannerController();
    final session = MobileScannerSession(controller: controller);
    final first = session.start();
    final second = session.start();
    final dispose = session.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(controller.events, ['start']);
    controller.permission.complete();
    await Future.wait([first, second, dispose, session.dispose()]);
    expect(controller.events, ['start', 'stop', 'dispose']);
    await expectLater(session.start(), throwsStateError);
  });

  test('a gallery picture is analyzed with the camera running again',
      () async {
    // The picker covered the page and the camera session went with it: a
    // decode handed in during that window reads the picture against a
    // camera that is only just coming back, and the picture is never read.
    final controller = _GalleryScannerController();
    final session = MobileScannerSession(
      controller: controller,
      imagePicker: _GalleryImagePicker(),
    );
    await session.start();
    await session.stop();
    final code = await session.scanImage();
    expect(code, 'TECHPIE_GALLERY_CODE');
    expect(controller.events, ['start', 'stop', 'start', 'analyze']);
    await session.dispose();
  });
}

class _DelayedScannerController extends MobileScannerController {
  _DelayedScannerController() : super(autoStart: false);

  final events = <String>[];
  final permission = Completer<void>();

  /// When true, the preview only reports its first frame when the test asks for
  /// one, so a test can observe who is still waiting for the picture.
  bool holdPreview = false;
  final previewFrames = StreamController<void>.broadcast();

  @override
  Stream<void> get previewStartedStream =>
      holdPreview ? previewFrames.stream : Stream<void>.value(null);

  @override
  Future<void> start({CameraFacing? cameraDirection}) async {
    events.add('start');
    await permission.future;
  }

  @override
  Future<void> stop({bool force = false}) async => events.add('stop');

  @override
  Future<void> freezePreview() async => events.add('freeze');

  @override
  // This fake never acquires the native resources released by the superclass.
  // ignore: must_call_super
  Future<void> dispose() async => events.add('dispose');
}

class _FailedScannerController extends MobileScannerController {
  _FailedScannerController() : super(autoStart: false);
  int attempts = 0;

  @override
  Stream<void> get previewStartedStream => Stream<void>.value(null);

  @override
  Future<void> start({CameraFacing? cameraDirection}) async {
    attempts++;
    value = value.copyWith(
      isInitialized: true,
      isRunning: false,
      error: const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied),
    );
  }
  @override
  // No native resources are acquired by this fake.
  // ignore: must_call_super
  Future<void> dispose() async {}
}

/// The picker handed a picture back after the camera session went away.
class _GalleryImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      XFile('/tmp/techpie-gallery-picture');
}

/// A camera whose decode only answers while its session is running: the
/// platform reads a picture against the camera, and one that is still coming
/// back answers with nothing.
class _GalleryScannerController extends MobileScannerController {
  _GalleryScannerController() : super(autoStart: false);

  final events = <String>[];
  bool running = false;

  @override
  Stream<void> get previewStartedStream => Stream<void>.value(null);

  @override
  Future<void> start({CameraFacing? cameraDirection}) async {
    events.add('start');
    running = true;
    value = value.copyWith(isInitialized: true, isRunning: true);
  }

  @override
  Future<void> stop({bool force = false}) async {
    events.add('stop');
    running = false;
  }

  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const <BarcodeFormat>[],
  }) async {
    events.add('analyze');
    if (!running) return null;
    return const BarcodeCapture(
      barcodes: [Barcode(rawValue: 'TECHPIE_GALLERY_CODE')],
    );
  }

  @override
  // No native resources are acquired by this fake.
  // ignore: must_call_super
  Future<void> dispose() async {}
}
