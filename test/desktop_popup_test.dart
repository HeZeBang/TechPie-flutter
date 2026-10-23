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
      builder: (context, close) => _themeLikeMenu(),
    );
  }

  testWidgets('flips above the anchor when it does not fit below (#139)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Anchor bottom at y=428: below it there is only the nav bar (72px) and a
    // margin, far less than the menu's 238px.
    await pumpTablet(tester, 380);
    openMenu();
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(DesktopPopoverSurface));
    // The whole menu is on screen and above the nav bar (top edge at y=378).
    expect(rect.top, greaterThanOrEqualTo(16));
    expect(rect.bottom, lessThanOrEqualTo(450 - 72));
    // It opened above the anchor instead of below it.
    expect(rect.bottom, lessThan(380));
    // Every row is visible — before the fix the last rows ran off screen.
    final lastRow = tester.getRect(find.text('Row 3'));
    expect(lastRow.bottom, lessThanOrEqualTo(450 - 72));
  });

  testWidgets('opens below the anchor when there is room', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTablet(tester, 40);
    openMenu();
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(DesktopPopoverSurface));
    expect(rect.left, closeTo(100, 0.5));
    // Anchor bottom (88) + the 8px offset.
    expect(rect.top, closeTo(96, 0.5));
    expect(rect.size, const Size(260, 238));
  });

  testWidgets('tapping outside closes the popover', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTablet(tester, 40);
    openMenu();
    await tester.pumpAndSettle();
    expect(find.byType(DesktopPopoverSurface), findsOneWidget);

    // A point on the scrim, well away from the popover (x 100–360).
    await tester.tapAt(const Offset(750, 20));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopPopoverSurface), findsNothing);
  });
}
