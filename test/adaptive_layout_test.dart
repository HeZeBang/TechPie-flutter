import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/adaptive_layout.dart';

void main() {
  test('window size classes use stable navigation breakpoints', () {
    expect(appWindowSizeClassFor(599), AppWindowSizeClass.compact);
    expect(appWindowSizeClassFor(600), AppWindowSizeClass.medium);
    expect(appWindowSizeClassFor(959), AppWindowSizeClass.medium);
    expect(appWindowSizeClassFor(960), AppWindowSizeClass.expanded);
  });
}
