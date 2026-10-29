import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';
import 'package:techpie/widgets/ios/ios_native_tab_bar.dart';
import 'package:techpie/widgets/schedule_picker_sheet.dart';

/// Before iOS 26 the chrome is drawn by Flutter. cupertino_native_better's
/// fallback would still draw SF Symbols as native views, which take the tap, so
/// an icon button or tab only responded outside its icon. None may appear here,
/// and a tap on the icon itself must land.
void main() {
  setUp(() => debugUsesIosLiquidGlass = false);
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('a tap on a tab icon selects the tab', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: IosNativeTabBar(
            selectedIndex: 0,
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
    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    expect(selected, [1]);
  },
    variant: ios,
  );

  testWidgets('a tap on a bar button icon reaches the bar', (tester) async {
    final taps = <String>[];
    final menu = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: IosNativeNavigationBar(
            title: 'Linked Accounts',
            leadingItems: const [
              IosNativeNavigationBarItem(
                id: 'back',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回',
              ),
            ],
            trailingItems: const [
              IosNativeNavigationBarItem(
                id: 'more',
                sfSymbol: 'ellipsis',
                menuItems: [
                  IosNativeNavigationBarMenuItem(value: 'export', title: 'Export'),
                ],
              ),
            ],
            onItemPressed: taps.add,
            onMenuSelected: (id, value) => menu.add('$id:$value'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(UiKitView), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.back));
    expect(taps, ['back']);

    // A menu opens as an action sheet with a 取消 button.
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(menu, ['more:export']);
  },
    variant: ios,
  );

  testWidgets('a sheet toolbar uses text buttons', (tester) async {
    var cancelled = 0;
    var confirmed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IosSheetHeader(
            title: '选择学期',
            onCancel: () => cancelled++,
            onConfirm: () => confirmed++,
          ),
        ),
      ),
    );
    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.tap(find.text('完成'));
    expect((cancelled, confirmed), (1, 1));
  },
    variant: ios,
  );
}
