import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('compact title stays centered beside unequal native actions', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: IosNativeNavigationBar(
            title: '已忽略的事项',
            leadingItems: const [
              IosNativeNavigationBarItem(
                id: 'back',
                title: 'Deadlines',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回 Deadlines',
                placementGroup: 'leading-main',
              ),
            ],
            trailingItems: const [
              IosNativeNavigationBarItem(
                id: 'select',
                title: '选择',
                placementGroup: 'trailing-main',
              ),
            ],
            onItemPressed: taps.add,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getCenter(find.text('已忽略的事项')).dx, closeTo(195, 0.1));
    final buttons = tester.widgetList<CNButton>(find.byType(CNButton)).toList();
    final back = buttons.first;
    expect(back.label, isNull);
    expect(back.semanticLabel, '返回 Deadlines');
    back.onPressed!();
    expect(taps, ['back']);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('header preserves subtitle, grouped menu values and disabled actions',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final selected = <String>[];
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: IosNativeNavigationBar(
            title: 'Schedule',
            subtitle: '2026 秋季',
            largeTitleMode: true,
            leadingItems: const [
              IosNativeNavigationBarItem(id: 'back', title: 'Back', enabled: false),
              IosNativeNavigationBarItem(id: 'hidden', title: 'Hidden', hidden: true),
            ],
            trailingItems: const [
              IosNativeNavigationBarItem(
                id: 'more',
                sfSymbol: 'ellipsis',
                accessibilityLabel: '更多操作',
                menuItems: [
                  IosNativeNavigationBarMenuItem(
                    value: 'saturday',
                    title: 'Saturday',
                    checked: true,
                  ),
                  IosNativeNavigationBarMenuItem(
                    value: 'section',
                    title: '',
                    displayInline: true,
                    children: [
                      IosNativeNavigationBarMenuItem(value: 'export', title: 'Export'),
                    ],
                  ),
                ],
              ),
            ],
            onItemPressed: taps.add,
            onMenuSelected: (id, value) => selected.add('$id:$value'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('2026 秋季'), findsOneWidget);
    final buttons = tester.widgetList<CNButton>(find.byType(CNButton));
    final button = buttons.singleWhere((button) => button.label == 'Back');
    expect(button.enabled, false);
    // A hidden item stays mounted, so its native view exists when it is shown,
    // but nothing can reach it while hidden.
    final hidden = find.byWidgetPredicate(
      (widget) => widget is CNButton && widget.label == 'Hidden',
    );
    expect(hidden, findsOneWidget);
    expect(hidden.hitTestable(), findsNothing);
    expect(button.onPressed, null);
    expect(taps, isEmpty);
    final menu = tester.widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton));
    expect(menu.semanticLabel, '更多操作');
    expect((menu.items.first as CNPopupMenuItem).checked, true);
    expect(menu.items[1], isA<CNPopupMenuDivider>());
    menu.onSelected(1);
    menu.onSelected(99);
    menu.onSelected(2);
    expect(selected, ['more:export']);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
