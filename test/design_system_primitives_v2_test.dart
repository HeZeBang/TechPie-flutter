import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/widgets/design_system/design_system.dart';

Widget _themedHost(
  Widget child, {
  TpColors? tpColors,
  bool disableAnimations = false,
}) {
  final colors = tpColors ?? TpColors.light();
  final baseTheme = ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    scaffoldBackgroundColor: colors.canvas,
    colorScheme: colors.toColorScheme(),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
  return MaterialApp(
    theme: baseTheme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('TpDensity resolves comfortable on mobile and compact on desktop',
      (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        late TpDensity resolved;
        await tester.pumpWidget(
          _themedHost(
            Builder(
              builder: (context) {
                resolved = context.tpDensity;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(resolved, TpDensity.comfortable);
        expect(resolved.isCompact, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        late TpDensity resolved;
        await tester.pumpWidget(
          _themedHost(
            Builder(
              builder: (context) {
                resolved = context.tpDensity;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(resolved, TpDensity.compact);
        expect(resolved.isCompact, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets('TpDensityScope drives TpCard header and TpListRow padding',
      (tester) async {
    Future<(EdgeInsetsGeometry cardPad, EdgeInsetsGeometry rowPad, double iconSize)>
        measureDensity(TpDensity density) async {
      await tester.pumpWidget(
        _themedHost(
          TpDensityScope(
            density: density,
            child: const Column(
              children: [
                TpCard(title: '标题', child: Text('内容')),
                TpListRow(
                  icon: TpIcons.settings,
                  title: '行标题',
                ),
              ],
            ),
          ),
        ),
      );
      final headerPadding = tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.text('标题'),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding;
      final rowPadding = tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.text('行标题'),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding;
      final rowIconSize = tester
          .widget<Icon>(
            find.descendant(
              of: find.byType(TpListRow),
              matching: find.byType(Icon),
            ),
          )
          .size!;
      return (headerPadding, rowPadding, rowIconSize);
    }

    final comfortable = await measureDensity(TpDensity.comfortable);
    final compact = await measureDensity(TpDensity.compact);

    expect(comfortable.$1, TpDensity.comfortable.cardHeaderPadding);
    expect(compact.$1, TpDensity.compact.cardHeaderPadding);
    expect(comfortable.$2, TpDensity.comfortable.rowPadding);
    expect(compact.$2, TpDensity.compact.rowPadding);
    expect(comfortable.$3, TpTokens.iconM);
    expect(compact.$3, TpDensity.compact.iconSize);
  });

  testWidgets(
      'TpSkeleton, TpSkeletonCard, and TpSkeletonList support all themes and reduced motion',
      (tester) async {
    for (final colors in [
      TpColors.light(),
      TpColors.dark(),
      TpColors.dark(amoled: true),
    ]) {
      await tester.pumpWidget(
        _themedHost(
          const SingleChildScrollView(
            child: Column(
              children: [
                TpSkeleton(width: 120, height: 14),
                TpSkeletonList(
                  itemCount: 2,
                  showLeadingAvatar: true,
                  showTrailingBadge: true,
                ),
              ],
            ),
          ),
          tpColors: colors,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TpSkeletonCard), findsNWidgets(2));
    }

    // With reduced motion enabled, animation stops cleanly so pumpAndSettle finishes.
    await tester.pumpWidget(
      _themedHost(
        const TpSkeletonList(
          itemCount: 3,
          scrollable: true,
          padding: EdgeInsets.all(TpTokens.space4),
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TpSkeletonCard), findsNWidgets(3));
  });

  testWidgets(
      'TpStateCard variants render actions and invoke callbacks on Android and iOS',
      (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        var primaryTaps = 0;
        var secondaryTaps = 0;

        await tester.pumpWidget(
          _themedHost(
            SingleChildScrollView(
              child: Column(
                children: [
                  TpStateCard.empty(
                    title: '暂无记录',
                    message: '当前学期尚未同步到相关数据。',
                    primaryActionLabel: '刷新数据',
                    onPrimaryAction: () => primaryTaps++,
                    secondaryActionLabel: '查看帮助',
                    onSecondaryAction: () => secondaryTaps++,
                  ),
                  const TpStateCard.error(
                    title: '加载失败',
                    message: '网络波动，请稍后重试。',
                    compact: true,
                  ),
                  const TpStateCard.prerequisite(
                    title: '需要绑定教务系统',
                    message: '完成认证绑定后即可查看详情。',
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('暂无记录'), findsOneWidget);
        expect(find.text('加载失败'), findsOneWidget);
        expect(find.text('需要绑定教务系统'), findsOneWidget);

        await tester.tap(find.text('刷新数据'));
        await tester.pump();
        await tester.tap(find.text('查看帮助'));
        await tester.pump();
        expect(primaryTaps, 1);
        expect(secondaryTaps, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  test(
      'ThemeService configures PredictiveBack on Android and pure-Dart Lucide icons',
      () async {
    SharedPreferences.setMockInitialValues({});
    final themeService = ThemeService(
      StorageService(await SharedPreferences.getInstance()),
    );

    final builders = themeService.lightTheme.pageTransitionsTheme.builders;
    expect(
      builders[TargetPlatform.android],
      isA<PredictiveBackPageTransitionsBuilder>(),
    );
    expect(
      builders[TargetPlatform.iOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );
    expect(
      builders[TargetPlatform.macOS],
      isA<CupertinoPageTransitionsBuilder>(),
    );

    for (final mode in AppThemeMode.values) {
      expect(mode.icon.fontFamily, 'lucide');
      expect(mode.icon.fontPackage, 'flutter_lucide');
    }
    for (final scheme in AppColorScheme.values) {
      expect(scheme.icon.fontFamily, 'lucide');
      expect(scheme.icon.fontPackage, 'flutter_lucide');
    }
  });
}
