import 'dart:ui' show Offset;

/// One decode: the text and where it was in the frame it was read from, in
/// normalised 0..1 coordinates so a viewfinder can land on it whatever size the
/// preview is drawn at.
final class ScannerReading {
  const ScannerReading(this.value, {this.corners});

  final String value;
  final List<Offset>? corners;
}

abstract interface class ScannerPort {
  Stream<ScannerReading> get scannedCodes;
  Future<void> start();

  /// Stops the camera while leaving its last frame on the preview — the frame a
  /// decoded code was read from stays on screen behind the result. The camera
  /// session is kept, so [start] resumes without reopening anything and [stop]
  /// is what releases it.
  Future<void> freeze();

  Future<void> stop();
  Future<void> setTorch(bool enabled);
  Future<String?> scanImage();
}
