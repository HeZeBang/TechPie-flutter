import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/theme/tp_colors.dart';
import 'package:techpie/widgets/adaptive_segmented_control.dart';
import 'package:techpie/widgets/design_system/design_system.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('TpSegmentedControl renders and slides across Light, Dark, and AMOLED themes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final themeService = ThemeService(StorageService(prefs));
    final lightTheme = themeService.lightTheme;
    final darkTheme = themeService.darkTheme;
    await themeService.setMode(AppThemeMode.amoled);
    final amoledTheme = themeService.darkTheme;

    for (final theme in [lightTheme, darkTheme, amoledTheme]) {
      var selected = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: TpSegmentedControl(
                  value: selected,
                  segments: const ['预约', '查询', '个人信息'],
                  onChanged: (idx) => setState(() => selected = idx),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialPos = tester.getTopLeft(
        find.byWidgetPredicate(
          (w) =>
              w is PositionedDirectional &&
              w.child is IgnorePointer,
        ),
      );

      await tester.tap(find.text('个人信息'));
      await tester.pumpAndSettle();
      expect(selected, 2);

      final finalPos = tester.getTopLeft(
        find.byWidgetPredicate(
          (w) =>
              w is PositionedDirectional &&
              w.child is IgnorePointer,
        ),
      );
      expect(finalPos.dx, greaterThan(initialPos.dx));
    }
  });

  testWidgets('TpSegmentedControl falls back safely in bare MaterialApp without ThemeService', (
    tester,
  ) async {
    var selected = 1;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: TpSegmentedControl(
              value: selected,
              segments: const ['全部', '主修'],
              onChanged: (idx) => setState(() => selected = idx),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(TpColors.of(tester.element(find.byType(TpSegmentedControl))).isDark, isTrue);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(selected, 0);
  });

  testWidgets('TpSegmentedControl shrinkWrap works inside bounded Center and unbounded Row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TpSegmentedControl(
                value: 0,
                segments: const ['周课表', '日程'],
                shrinkWrap: true,
                onChanged: (_) {},
              ),
              Row(
                children: [
                  TpSegmentedControl(
                    value: 1,
                    segments: const ['我的课程', '公告'],
                    shrinkWrap: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final boxes = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(TpSegmentedControl),
            matching: find.byType(Container),
          ),
        )
        .toList();
    expect(boxes, hasLength(2));
  });

  testWidgets('TpSegmentedControl ignores taps when disabled and snaps on segment count change or reduced motion', (
    tester,
  ) async {
    var selected = 2;
    var segments = const ['一', '二', '三'];

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TpSegmentedControl(
                  value: selected,
                  segments: segments,
                  enabled: false,
                  onChanged: (idx) => setState(() => selected = idx),
                ),
                TextButton(
                  onPressed: () => setState(() => segments = const ['甲', '乙']),
                  child: const Text('Shrink'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('一'));
    await tester.pumpAndSettle();
    expect(selected, 2);

    await tester.tap(find.text('Shrink'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    var reducedSelected = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: TpSegmentedControl(
                value: reducedSelected,
                segments: const ['A', 'B'],
                onChanged: (idx) => setState(() => reducedSelected = idx),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(reducedSelected, 1);
    // Drain AppHaptics.play's 300ms platform channel timeout timer.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  });

  testWidgets('AdaptiveSegmentedControl renders TpSegmentedControl uniformly on macOS, iOS, and Android', (
    tester,
  ) async {
    try {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdaptiveSegmentedControl(
                value: 0,
                segments: const ['预约', '查询', '个人信息'],
                onChanged: (_) {},
              ),
            ),
          ),
        );
        expect(find.byType(TpSegmentedControl), findsOneWidget);
        expect(find.byType(AppKitView), findsNothing);
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byType(SegmentedButton<int>), findsNothing);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
