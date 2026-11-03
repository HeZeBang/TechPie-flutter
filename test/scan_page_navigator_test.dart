import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/widgets/scanner/scan_page.dart';

void main() {
  testWidgets('the shared scanner covers the shell from inside a tab', (
    tester,
  ) async {
    // A tab's own Navigator, as the iOS shell gives each tab: the scanner must
    // still open on the root one, above the tab bar, like the campus card's.
    final tabNavigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          key: tabNavigator,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const SizedBox.expand(),
          ),
        ),
      ),
    );

    final scanned = showTechPieScanner(
      tabNavigator.currentContext!,
      scanner: InMemoryScannerPort(),
    );
    await tester.pumpAndSettle();

    final page = tester.element(find.byType(ScannerPage));
    expect(Navigator.of(page), same(Navigator.of(page, rootNavigator: true)));
    expect(tabNavigator.currentState!.canPop(), isFalse);

    tester.widget<ScannerPage>(find.byType(ScannerPage)).onClose!();
    await tester.pumpAndSettle();
    expect(await scanned, isNull);
  });
}
