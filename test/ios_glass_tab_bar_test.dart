import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_glass_tab_bar.dart';

void main() {
  testWidgets('tab bar uses one composited Cupertino surface', (
    WidgetTester tester,
  ) async {
    int? selectedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: IosGlassTabBar(
            selectedIndex: 0,
            items: const [
              IosGlassTabBarItem(
                label: 'Home',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                sfSymbol: 'house',
                selectedSfSymbol: 'house.fill',
              ),
              IosGlassTabBarItem(
                label: 'Settings',
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                sfSymbol: 'gearshape',
                selectedSfSymbol: 'gearshape.fill',
              ),
            ],
            onSelected: (value) => selectedIndex = value,
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(CupertinoTabBar), findsOneWidget);

    await tester.tap(find.text('Settings'));
    expect(selectedIndex, 1);
  });
}
