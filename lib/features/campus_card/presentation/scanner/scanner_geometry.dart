import 'package:flutter/painting.dart';

/// Shared by the visible guide and the native recognition region.
Rect scannerWindowForSize(Size size) {
  final side = size.width.clamp(250.0, 310.0);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.43),
    width: side,
    height: side,
  ).intersect(Offset.zero & size);
}
