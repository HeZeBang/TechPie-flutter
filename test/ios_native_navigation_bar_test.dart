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
    expect(back.icon!.size, 20);
    expect(back.icon!.color, back.tint);
    final barRect = tester.getRect(find.byType(IosNativeNavigationBar));
    final backRect = tester.getRect(find.byWidget(back));
    expect(backRect.top - barRect.top, greaterThanOrEqualTo(8));
    expect(barRect.bottom - backRect.bottom, greaterThanOrEqualTo(8));
    expect(buttons.every((button) => button.config.glassEffectUnionId == null), isTrue);
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
    final button = tester.widget<CNButton>(find.byType(CNButton));
    expect(button.enabled, false);
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

  testWidgets('compact header fits narrow windows and follows app theme', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            appBar: IosNativeNavigationBar(
              title: 'Long account settings title',
              subtitle: 'Subtitle',
              leadingItems: [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: '返回 Settings',
                  sfSymbol: 'chevron.left',
                ),
              ],
              trailingItems: [
                IosNativeNavigationBarItem(
                  id: 'save',
                  title: 'Save',
                  role: IosNativeNavigationBarItemRole.done,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final title = tester.widget<Text>(find.text('Long account settings title'));
      expect(title.style!.color, theme.colorScheme.onSurface);
      expect(tester.takeException(), isNull);
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
