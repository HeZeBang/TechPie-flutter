import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_glass_tab_bar.dart';

void main() {
  testWidgets('tab bar is backed by the native UIKit implementation', (
    WidgetTester tester,
  ) async {
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
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final platformView = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(platformView.viewType, 'techpie/native_glass_tab_bar');
    expect(platformView.creationParams, {
      'selectedIndex': 0,
      'items': [
        {
          'label': 'Home',
          'sfSymbol': 'house',
          'selectedSfSymbol': 'house.fill',
        },
        {
          'label': 'Settings',
          'sfSymbol': 'gearshape',
          'selectedSfSymbol': 'gearshape.fill',
        },
      ],
    });
  });
}
