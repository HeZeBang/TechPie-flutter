import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';

void main() {
  test('iOS interactive controls use the Apple minimum hit target', () {
    expect(iosMinimumInteractiveDimension, 44);
  });
}
