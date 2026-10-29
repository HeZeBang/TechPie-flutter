import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/app_shell/app_shell_metrics.dart';
import 'package:techpie/widgets/desktop_popup.dart';

/// A menu with a known height, shaped like the theme picker from #139:
/// header (30) + four rows (4 × 48) inside the surface's 8px padding → 238.
Widget _themeLikeMenu() {
  return DesktopPopoverSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 30),
        for (var i = 0; i < 4; i++)
          SizedBox(height: 48, child: Center(child: Text('Row $i'))),
      ],
    ),
  );
}

void main() {
  late BuildContext anchorContext;

  /// A landscape tablet window (logical 800×450) with MobileShell's floating
  /// nav bar occupying the bottom 72px. Places a 260×48 anchor row at x=100,
  /// [anchorTop] from the top edge.
  Future<void> pumpTablet(WidgetTester tester, double anchorTop) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShellMetrics(
          bottomObstruction: 72,
          child: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: anchorTop,
                  width: 260,
                  height: 48,
                  child: Builder(
                    builder: (context) {
                      anchorContext = context;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void openMenu() {
    showDesktopPopover(
      anchorContext: anchorContext,
      width: 260,
      placement: DesktopPopoverPlacement.belowEnd,
      offset: const Offset(0, 8),
      scrollable: true,
      builder: (context, close) => _themeLikeMenu(),
    );
  }

  testWidgets('flips above the anchor when it does not fit below (#139)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 640);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Anchor bottom at y=298: below it there is only the nav bar (72px) and a
    // margin, far less than the menu's 238px. The constrained menu remains
    // scrollable so every option is still available in this short landscape
    // window.
    await pumpTablet(tester, 250);
    openMenu();
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(SingleChildScrollView).last);
    // The scroll viewport is on screen and above the nav bar.
    expect(viewport.top, greaterThanOrEqualTo(16));
    expect(viewport.bottom, lessThanOrEqualTo(320 - 72));
    // It opened above the anchor instead of below it.
    expect(viewport.bottom, lessThan(250));
    // Every row remains available — before the fix the last rows ran off screen.
    expect(viewport.height, lessThanOrEqualTo(320 - 72 - 32));
    expect(find.text('Row 3'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -100),
    );
    await tester.pump();
    final lastRow = tester.getRect(find.text('Row 3'));
    expect(lastRow.bottom, lessThanOrEqualTo(viewport.bottom));
  });

}
