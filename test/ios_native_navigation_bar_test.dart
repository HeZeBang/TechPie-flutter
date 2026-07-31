import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_native_navigation_bar.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS navigation bar stays in the Flutter scene', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? pressedItem;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: IosNativeNavigationBar(
            title: 'Cloud sync',
            leadingItems: const [
              IosNativeNavigationBarItem(
                id: 'back',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回',
              ),
            ],
            onItemPressed: (value) => pressedItem = value,
          ),
          body: const SizedBox(),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    expect(find.text('Cloud sync'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('返回'));
    expect(pressedItem, 'back');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('overflow actions use a Cupertino action sheet', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String? selectedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: IosNativeNavigationBar(
            title: 'Deadlines',
            trailingItems: const [
              IosNativeNavigationBarItem(
                id: 'more',
                sfSymbol: 'ellipsis',
                accessibilityLabel: '更多操作',
                menuItems: [
                  IosNativeNavigationBarMenuItem(
                    value: 'hidden',
                    title: '查看已忽略',
                  ),
                ],
              ),
            ],
            onMenuSelected: (_, value) => selectedValue = value,
          ),
          body: const SizedBox(),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('更多操作'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('查看已忽略'));
    await tester.pumpAndSettle();

    expect(selectedValue, 'hidden');
    debugDefaultTargetPlatformOverride = null;
  });
}
