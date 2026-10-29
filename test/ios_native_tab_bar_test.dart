import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios/ios_native_tab_bar.dart';

void main() {
  testWidgets('tab selection and reselection report once; dragging does not reselect',
      (tester) async {
    // A portrait phone: the one layout whose item frames the bar can derive.
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: IosNativeTabBar(
            selectedIndex: 99,
            items: const [
              IosNativeTabBarItem(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                sfSymbol: 'house',
                selectedSfSymbol: 'house.fill',
              ),
              IosNativeTabBarItem(
                label: 'Settings',
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                sfSymbol: 'gearshape',
                selectedSfSymbol: 'gearshape.fill',
              ),
            ],
            onSelected: selected.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final bar = tester.widget<CNTabBar>(find.byType(CNTabBar));
    expect(bar.currentIndex, 1);
    bar.onTap(-1);
    bar.onTap(2);
    expect(selected, isEmpty);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(selected, [1]);
    await tester.drag(find.text('Settings'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(selected, [1]);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(selected, [1, 0]);
  });

  testWidgets('a wide bar does not guess which item a tap was on', (tester) async {
    // Landscape and iPad centre compact items, so an equal split would put a
    // tap on another tab under the selected one and pop it by mistake.
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: IosNativeTabBar(
            selectedIndex: 1,
            items: const [
              IosNativeTabBarItem(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                sfSymbol: 'house',
                selectedSfSymbol: 'house.fill',
              ),
              IosNativeTabBarItem(
                label: 'Settings',
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                sfSymbol: 'gearshape',
                selectedSfSymbol: 'gearshape.fill',
              ),
            ],
            onSelected: selected.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final bar = tester.getRect(find.byType(CNTabBar));
    await tester.tapAt(Offset(bar.right - 40, bar.top + 20));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });
}
