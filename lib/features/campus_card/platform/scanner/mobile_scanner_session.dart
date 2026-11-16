import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/async_mutex.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/ports/platform_ports.dart';

/// Shared scanner controller for every platform the pinned mobile_scanner fork
/// supports — Android, iOS and OHOS — through one code path.
/// Presentation uses [controller] only to attach the plugin-owned camera
/// preview; all scanning operations remain behind [ScannerPort].
final class MobileScannerSession implements ScannerPort {
  MobileScannerSession({
    MobileScannerController? controller,
    ImagePicker? imagePicker,
  })  : controller = controller ??
            MobileScannerController(
              autoStart: false,
              // Decode at most four times a second without throttling preview.
              // ScannerModal gates duplicate results before any submission.
              detectionSpeed: DetectionSpeed.normal,
              detectionTimeoutMs: 250,
              facing: CameraFacing.back,
              formats: const [BarcodeFormat.qrCode],
            ),
        _imagePicker = imagePicker ?? ImagePicker() {
    _subscription = this.controller.barcodes.listen(
          _acceptCapture,
          onError: _codes.addError,
        );
  }

  final MobileScannerController controller;
  final ImagePicker _imagePicker;
  final StreamController<ScannerReading> _codes =
      StreamController<ScannerReading>.broadcast(
    sync: true,
  );
  late final StreamSubscription<BarcodeCapture> _subscription;
  final _transitions = AsyncMutex();

  /// Whether the platform camera session exists: started and not yet stopped.
  bool _live = false;

  /// Whether the preview is frozen on its last frame with the camera paused.
  bool _frozen = false;

  /// How long a start waits for the preview's first frame before opening anyway.
  static const Duration _previewTimeout = Duration(milliseconds: 1500);
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Stream<ScannerReading> get scannedCodes => _codes.stream;

  @override
  Future<void> start() => _transitions.protect(_start);

  Future<void> _start() async {
    _ensureActive();
    if (_live && !_frozen) return;
    // Subscribed before the platform is asked to start: the native side reports
    // one frame per start, so waiting only after `start()` resolved would
    // sometimes miss it and sit out the whole timeout. An earlier session's
    // frame cannot satisfy this wait, because its report was for its own start.
    final previewStarted = controller.previewStartedStream.first;
    // Nobody may await this future when the start below fails, and a broken
    // event stream is not the scanner's problem.
    unawaited(previewStarted.then((_) {}, onError: (Object _) {}));
    try {
      // Also unfreezes a preview that was frozen on a decoded code.
      await controller.start();
      final error = controller.value.error;
      if (error != null) throw error;
      await _awaitPreviewFrame(previewStarted);
      _live = true;
      _frozen = false;
    } on MobileScannerException catch (error) {
      throw AppFailure(
        FailureKind.permissionDenied,
        '无法启动相机，请检查相机权限。',
        code: 'SCANNER_START_FAILED',
        cause: error,
      );
    }
  }

  /// Waits for the picture to actually be live.
  ///
  /// [MobileScannerController.start] reports that the platform accepted the
  /// request — for a moment afterwards the preview still shows whatever it was
  /// left with (the previous session's last frame, or a frozen code). This is
  /// the wait that makes `start()` mean "the camera is on screen", and it is
  /// bounded so a camera that never reports cannot leave the scanner behind a
  /// black cover forever.
  Future<void> _awaitPreviewFrame(Future<void> previewStarted) async {
    try {
      await previewStarted.timeout(_previewTimeout);
    } on TimeoutException {
      // Opening with a possibly-stale picture beats not opening at all.
    } on Object {
      // A stream error says nothing about the camera.
    }
  }

  /// Stops the camera while leaving its last frame on the preview, so the code
  /// that was just decoded stays visible behind its result. [start] resumes.
  @override
  Future<void> freeze() => _transitions.protect(_freeze);

  Future<void> _freeze() async {
    _ensureActive();
    if (!_live || _frozen) return;
    await controller.freezePreview();
    _frozen = true;
  }

  @override
  Future<void> stop() => _transitions.protect(_stop);

  Future<void> _stop() async {
    if (_disposed || !_live) return;
    // Forced, because a frozen session is already paused and would otherwise
    // keep the camera resources.
    await controller.stop(force: true);
    _live = false;
    _frozen = false;
  }

  @override
  Future<void> setTorch(bool enabled) async {
    _ensureActive();
    final current = controller.value.torchState;
    if (current == TorchState.unavailable) {
      throw const AppFailure(
        FailureKind.unavailable,
        '当前设备不支持手电筒。',
        code: 'SCANNER_TORCH_UNAVAILABLE',
      );
    }
    final isEnabled = current == TorchState.on;
    if (isEnabled != enabled) await controller.toggleTorch();
  }

  @override
  Future<String?> scanImage() async {
    _ensureActive();
    final path =
        (await _imagePicker.pickImage(source: ImageSource.gallery))?.path;
    if (path == null) return null;
    final capture = await controller.analyzeImage(path);
    return _firstValue(capture);
  }

  Future<void> dispose() => _disposeFuture ??= _transitions.protect(_dispose);

  Future<void> _dispose() async {
    if (_disposed) return;
    await _stop();
    _disposed = true;
    await _subscription.cancel();
    await _codes.close();
    await controller.dispose();
  }

  void _acceptCapture(BarcodeCapture capture) {
    if (_codes.isClosed) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _codes.add(
        ScannerReading(
          value,
          corners: _normalisedCorners(barcode, capture.size),
        ),
      );
      return;
    }
  }

  /// The decoded corners in 0..1 against the frame they were read from — the
  /// same space the viewfinder draws in, so the frame can land on the code.
  List<Offset>? _normalisedCorners(Barcode barcode, Size frame) {
    final corners = barcode.corners;
    if (corners.isEmpty) return null;
    if (frame.width <= 0 || frame.height <= 0) return null;
    return [
      for (final point in corners)
        Offset(point.dx / frame.width, point.dy / frame.height),
    ];
  }

  String? _firstValue(BarcodeCapture? capture) {
    if (capture == null) return null;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('MobileScannerSession is disposed');
  }
}
