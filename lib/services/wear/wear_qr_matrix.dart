import 'dart:convert';
import 'dart:typed_data';

import 'package:qr_flutter/qr_flutter.dart';

import 'wear_protocol.dart';

/// Row-major, MSB-first QR modules. The original binary payload is never
/// converted to a String; the watch adds a four-module quiet zone when drawing.
Map<String, dynamic> wearQrMatrix(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 1024) {
    throw const WearFailure('PAYLOAD_TOO_LARGE');
  }
  final image = QrImage(
    QrCode.fromUint8List(
      data: bytes,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ),
  );
  final size = image.moduleCount;
  // 264 logical pixels with >= 2 pixels/module, including the quiet zone.
  if (size > 121) throw const WearFailure('PAYLOAD_TOO_LARGE');
  final packed = Uint8List((size * size + 7) ~/ 8);
  for (var row = 0; row < size; row++) {
    for (var col = 0; col < size; col++) {
      final bit = row * size + col;
      if (image.isDark(row, col)) packed[bit ~/ 8] |= 1 << (7 - bit % 8);
    }
  }
  return {
    'matrixSize': size,
    'matrixEncoding': 'base64-msb',
    'matrix': base64Encode(packed),
  };
}
