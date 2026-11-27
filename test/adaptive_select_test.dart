import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/adaptive_select.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('an iOS display field only shows the value', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSelect(
            value: 'dark',
            useIosNativeMenu: false,
            options: const [
              AdaptiveSelectOption(value: 'system', label: 'System'),
              AdaptiveSelectOption(value: 'dark', label: 'Dark'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Dark'), findsOneWidget);
    // The caller owns the tap; the field itself presents nothing.
    expect(find.byType(CNPopupMenuButton), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native menu maps checked values and rejects invalid indices', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    String value = 'system';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: AdaptiveSelect(
              useIosNativeMenu: true,
              accessibilityLabel: 'Theme',
              value: value,
              options: const [
                AdaptiveSelectOption(value: 'system', label: 'System'),
                AdaptiveSelectOption(value: 'dark', label: 'Dark'),
              ],
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    var menu = tester.widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton));
    expect(menu.semanticLabel, 'Theme');
    // The list reads top to bottom wherever the menu opens.
    expect(menu.preserveTopToBottomOrder, isTrue);
    expect((menu.items.first as CNPopupMenuItem).checked, true);
    menu.onSelected(-1);
    menu.onSelected(99);
    expect(value, 'system');
    menu.onSelected(1);
    await tester.pumpAndSettle();
    menu = tester.widget<CNPopupMenuButton>(find.byType(CNPopupMenuButton));
    expect(value, 'dark');
    expect(menu.buttonLabel, 'Dark');
    expect((menu.items.last as CNPopupMenuItem).checked, true);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native menu opt-in preserves Android dropdown behavior', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSelect(
            useIosNativeMenu: true,
            value: 'system',
            options: const [
              AdaptiveSelectOption(value: 'system', label: 'System'),
              AdaptiveSelectOption(value: 'dark', label: 'Dark'),
            ],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    expect(find.byType(UiKitView), findsNothing);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(selected, 'dark');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'iOS inline selectors update existing native views',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      debugUsesIosLiquidGlass = true;
      addTearDown(() => debugUsesIosLiquidGlass = false);

      final messenger = tester.binding.defaultBinaryMessenger;
      final callsById = <int, List<MethodCall>>{};
      final disposed = <int>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
          final calls = callsById[id] = [];
          messenger.setMockMethodCallHandler(
            MethodChannel('CupertinoNativePopupMenuButton_$id'),
            (call) async {
              calls.add(call);
              if (call.method == 'getIntrinsicSize') return {'width': 100};
              return null;
            },
          );
        } else if (call.method == 'dispose') {
          disposed.add(call.arguments as int);
        }
        return null;
      });

      Widget settings({required String scheme, required Color tint}) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  AdaptiveSelect(
                    value: 'system',
                    accessibilityLabel: '主题模式',
                    iosButtonStyle: CNButtonStyle.plain,
                    iosTint: tint,
                    shrinkWrap: true,
                    options: const [
                      AdaptiveSelectOption(value: 'system', label: '跟随系统'),
                    ],
                    onChanged: (_) {},
                  ),
                  AdaptiveSelect(
                    value: scheme,
                    accessibilityLabel: '主题色',
                    iosButtonStyle: CNButtonStyle.plain,
                    iosTint: tint,
                    shrinkWrap: true,
                    options: const [
                      AdaptiveSelectOption(value: 'red', label: '科技红 · TechRed'),
                      AdaptiveSelectOption(value: 'blue', label: '系统蓝'),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(settings(scheme: 'red', tint: Colors.red));
      await tester.pumpAndSettle();
      expect(callsById, hasLength(2));
      final [modeCalls, colorCalls] = callsById.values.toList();
      modeCalls.clear();
      colorCalls.clear();

      await tester.pumpWidget(settings(scheme: 'blue', tint: Colors.blue));
      await tester.pumpAndSettle();

      expect(callsById, hasLength(2));
      expect(disposed, isEmpty);
      expect(modeCalls.map((call) => call.method), ['setStyle']);
      expect(modeCalls.single.arguments, {'tint': Colors.blue.toARGB32()});
      expect(
        colorCalls.singleWhere((call) => call.method == 'setButtonTitle').arguments,
        {'title': '系统蓝'},
      );
      final items = colorCalls.singleWhere((call) => call.method == 'setItems').arguments
          as Map<Object?, Object?>;
      expect(items['checked'], [false, true]);
      expect(colorCalls.map((call) => call.method), contains('getIntrinsicSize'));
    },
  );

  testWidgets(
    'macOS AdaptiveSelect renders AppKitView and updates selection',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final callsById = <int, List<MethodCall>>{};
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
          final calls = callsById[id] = [];
          messenger.setMockMethodCallHandler(
            MethodChannel('TechPieMacPopUpButton_$id'),
            (call) async {
              calls.add(call);
              if (call.method == 'getIntrinsicSize') return {'width': 120.0};
              return null;
            },
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform_views, null),
      );

      String value = 'system';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: AdaptiveSelect(
                label: '主题模式',
                value: value,
                shrinkWrap: true,
                options: const [
                  AdaptiveSelectOption(value: 'system', label: '跟随系统'),
                  AdaptiveSelectOption(value: 'dark', label: '深色'),
                ],
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('主题模式'), findsOneWidget);
      final view = tester.widget<AppKitView>(find.byType(AppKitView));
      expect(view.viewType, 'TechPieMacPopUpButton');

      final id = callsById.keys.single;
      final codec = const StandardMethodCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'TechPieMacPopUpButton_$id',
        codec.encodeMethodCall(
          const MethodCall('itemSelected', {'index': 1}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(value, 'dark');
    },
  );

  testWidgets(
    'iOS direct UIKit flag switches AdaptiveSelect to UiKitView',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      debugForceDirectIosUiKitViews = true;
      addTearDown(() => debugForceDirectIosUiKitViews = false);

      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map<Object?, Object?>)['id'] as int;
          messenger.setMockMethodCallHandler(
            MethodChannel('CupertinoNativePopupMenuButton_$id'),
            (call) async {
              if (call.method == 'getIntrinsicSize') return {'width': 96.0};
              return null;
            },
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform_views, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSelect(
              value: 'a',
              options: const [
                AdaptiveSelectOption(value: 'a', label: 'A'),
                AdaptiveSelectOption(value: 'b', label: 'B'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, 'CupertinoNativePopupMenuButton');
    },
  );
}
