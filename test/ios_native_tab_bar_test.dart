import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios/ios_native_tab_bar.dart';

void main() {
  testWidgets('tab bar maps selection and reserves the bottom safe area', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
      child: Scaffold(
          bottomNavigationBar: IosNativeTabBar(
        selectedIndex: 99,
        items: const [
          IosNativeTabBarItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              sfSymbol: 'house',
              selectedSfSymbol: 'house.fill',),
          IosNativeTabBarItem(
              label: 'Settings',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings,
              sfSymbol: 'gearshape',
              selectedSfSymbol: 'gearshape.fill',),
        ],
        onSelected: selected.add,
      ),),
    ),),);
    await tester.pump(const Duration(milliseconds: 600));
    final bar = tester.widget<CNTabBar>(find.byType(CNTabBar));
    expect(bar.height, 83);
    expect(bar.currentIndex, 1);
    bar.onTap(-1);
    bar.onTap(2);
    expect(selected, isEmpty);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(selected, [0]);
  });
}
