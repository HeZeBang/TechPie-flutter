import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scanner_geometry.dart';

void main() {
  test('recognition window matches the guide on a phone', () {
    final window = scannerWindowForSize(const Size(430, 932));
    expect(window.width, 310);
    expect(window.height, 310);
    expect(window.center, const Offset(215, 932 * 0.43));
  });

  test('recognition stays inside narrow or landscape viewports', () {
    for (final size in [
      const Size(200, 600),
      const Size(932, 250),
      Size.zero,
    ]) {
      final window = scannerWindowForSize(size);
      expect(window.left, greaterThanOrEqualTo(0));
      expect(window.top, greaterThanOrEqualTo(0));
      expect(window.right, lessThanOrEqualTo(size.width));
      expect(window.bottom, lessThanOrEqualTo(size.height));
    }
  });
}
