import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/app_shell/app_destination.dart';
import 'package:techpie/widgets/app_shell/app_shell_tab_bar.dart';
import 'package:techpie/widgets/app_shell/mobile_shell.dart';
import 'package:techpie/widgets/app_shell/tg_bottom_nav_bar.dart';

/// A page that is selecting stands in for the tab bar, as Photos and Files do:
/// the bar collapses (without being removed, so it does not flash back), and
/// stops counting toward the safe area so the page's toolbar sits where it was.
void main() {
  const destinations = [
    AppDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      sfSymbol: 'house',
      selectedSfSymbol: 'house.fill',
      page: SizedBox(),
    ),
    AppDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      sfSymbol: 'gearshape',
      selectedSfSymbol: 'gearshape.fill',
      page: SizedBox(),
    ),
  ];

  late BuildContext pageContext;

  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: MobileShell(
            destinations: destinations,
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            child: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

  double barHeight(WidgetTester tester) =>
      tester.getSize(find.byType(TgBottomNavBar)).height;

  testWidgets('a hold collapses the bar and takes it out of the safe area', (
    tester,
  ) async {
    await pumpShell(tester);
    final shown = MediaQuery.paddingOf(pageContext).bottom;
    expect(shown, greaterThan(0));
    expect(find.byType(TgBottomNavBar).hitTestable(), findsOneWidget);

    final hold = AppShellTabBar.maybeOf(pageContext)!.hide();
    await tester.pump();
    // Still mounted, so it comes back without being rebuilt from scratch.
    expect(find.byType(TgBottomNavBar), findsOneWidget);
    expect(find.byType(TgBottomNavBar).hitTestable(), findsNothing);
    expect(MediaQuery.paddingOf(pageContext).bottom, 0);

    hold.release();
    hold.release(); // a second release is harmless
    await tester.pump();
    expect(find.byType(TgBottomNavBar).hitTestable(), findsOneWidget);
    expect(MediaQuery.paddingOf(pageContext).bottom, shown);
    expect(barHeight(tester), greaterThan(0));
  });

  testWidgets('the bar stays hidden until every hold is released', (
    tester,
  ) async {
    await pumpShell(tester);
    final controller = AppShellTabBar.maybeOf(pageContext)!;
    final first = controller.hide();
    final second = controller.hide();
    first.release();
    await tester.pump();
    expect(controller.hidden, isTrue);
    second.release();
    await tester.pump();
    expect(controller.hidden, isFalse);
  });

  testWidgets('a hold released while the tree is building lands next frame', (
    tester,
  ) async {
    await pumpShell(tester);
    final controller = AppShellTabBar.maybeOf(pageContext)!;
    final hold = controller.hide();
    await tester.pump();

    // What a page does from dispose when it is popped mid-selection.
    await tester.pumpWidget(
      MaterialApp(
        home: MobileShell(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          child: _ReleaseOnDispose(hold: hold),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MobileShell(
          destinations: destinations,
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          child: const SizedBox(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(controller.hidden, isFalse);
  });

  test('outside the shell there is no bar to hide', () {
    expect(AppShellTabBarController().hidden, isFalse);
  });
}

class _ReleaseOnDispose extends StatefulWidget {
  const _ReleaseOnDispose({required this.hold});

  final AppShellTabBarHold hold;

  @override
  State<_ReleaseOnDispose> createState() => _ReleaseOnDisposeState();
}

class _ReleaseOnDisposeState extends State<_ReleaseOnDispose> {
  @override
  void dispose() {
    widget.hold.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
