import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/widgets/design_system/design_system.dart';

void main() {
  Widget wrap(Widget child, {ThemeData? theme}) {
    final tp = theme?.extension<TpColors>() ?? TpColors.light();
    return MaterialApp(
      theme: theme ??
          ThemeData(
            useMaterial3: true,
            colorScheme: tp.toColorScheme(),
            scaffoldBackgroundColor: tp.canvas,
            extensions: <ThemeExtension<dynamic>>[tp],
          ),
      home: Scaffold(body: child),
    );
  }

  testWidgets('TpCard renders borderless in light and bordered in dark/AMOLED',
      (tester) async {
    for (final tp in [
      TpColors.light(),
      TpColors.dark(),
      TpColors.dark(amoled: true),
    ]) {
      await tester.pumpWidget(
        wrap(
          const TpCard(
            title: '今日课程',
            trailing: Text('2 节'),
            child: Padding(
              padding: EdgeInsets.all(TpTokens.space4),
              child: Text('计算机体系结构 I'),
            ),
          ),
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: tp.toColorScheme(),
            scaffoldBackgroundColor: tp.canvas,
            extensions: <ThemeExtension<dynamic>>[tp],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今日课程'), findsOneWidget);
      expect(find.text('2 节'), findsOneWidget);
      expect(find.text('计算机体系结构 I'), findsOneWidget);
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(TpCard), matching: find.byType(Material)).first,
      );
      final shape = material.shape! as RoundedRectangleBorder;
      if (tp.isDark) {
        expect(shape.side, isNot(BorderSide.none));
      } else {
        expect(shape.side, BorderSide.none);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('TpPageHeader, TpAccentRow, TpProgressRow, TpBadge render cleanly',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        ListView(
          padding: const EdgeInsets.all(TpTokens.space4),
          children: [
            TpPageHeader(
              subtitle: '11月24日 星期二 · 第 12 周',
              title: '下午好',
              trailing: TpAvatarBadge(
                text: 'GP',
                onTap: () => tapped = true,
              ),
            ),
            const TpCard(
              title: '今日课程',
              trailing: Text('1 节'),
              child: TpAccentRow(
                accentColor: TpTokens.techRedLight,
                title: '计算机体系结构 I',
                subtitle: '13:00 – 14:40 · SIST 1A-108',
                trailing: TpBadge(label: '进行中'),
                boldTitle: true,
              ),
            ),
            const SizedBox(height: TpTokens.sectionGap),
            const TpCard(
              title: 'Deadlines',
              trailing: Text('1 项待完成'),
              child: TpProgressRow(
                title: 'Homework 5',
                subtitle: 'Gradescope · CS110',
                trailingLabel: '剩余 1 天 3 小时',
                progress: 0.84,
                color: TpTokens.techRedLight,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('下午好'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('Homework 5'), findsOneWidget);
    expect(find.byType(TpProgressBar), findsOneWidget);
    await tester.tap(find.text('GP'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TpCampusCardStrip respects balance eye toggle and configured state',
      (tester) async {
    var payTaps = 0;
    var cardTaps = 0;
    var toggleTaps = 0;

    // Configured + hidden balance
    await tester.pumpWidget(
      wrap(
        TpCampusCardStrip(
          configured: true,
          balanceText: '¥ 128.50',
          hideBalance: true,
          onToggleHideBalance: () => toggleTaps++,
          onOpenPayCode: () => payTaps++,
          onOpenCard: () => cardTaps++,
        ),
      ),
    );
    expect(find.text('余额 ••••'), findsOneWidget);
    expect(find.text('余额 ¥ 128.50'), findsNothing);
    expect(find.text('亮码'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home.campus-card-balance-toggle')));
    expect(toggleTaps, 1);
    expect(cardTaps, 0);
    await tester.tap(find.byKey(const ValueKey('home.campus-card-pay')));
    expect(payTaps, 1);

    // Configured + visible balance (default)
    await tester.pumpWidget(
      wrap(
        TpCampusCardStrip(
          configured: true,
          balanceText: '¥ 128.50',
          onToggleHideBalance: () => toggleTaps++,
          onOpenPayCode: () => payTaps++,
          onOpenCard: () => cardTaps++,
        ),
      ),
    );
    expect(find.text('余额 ¥ 128.50'), findsOneWidget);
    await tester.tap(find.text('余额 ¥ 128.50'));
    expect(cardTaps, 1);

    // Unconfigured
    await tester.pumpWidget(
      wrap(
        TpCampusCardStrip(
          configured: false,
          balanceText: null,
          hideBalance: true,
          onOpenPayCode: () => payTaps++,
          onOpenCard: () => cardTaps++,
        ),
      ),
    );
    expect(find.text('进入'), findsOneWidget);
    expect(find.text('绑定后可一键亮码与查看余额'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home.campus-card-balance-toggle')),
      findsNothing,
    );
  });

  testWidgets('TpFeatureGrid fits 4 columns cleanly at 320px narrow width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? tappedId;
    await tester.pumpWidget(
      wrap(
        TpCard(
          title: '快捷功能',
          child: TpFeatureGrid(
            items: [
              for (var i = 0; i < 7; i++)
                TpFeatureGridItem(
                  id: 'feat-$i',
                  label: '功能$i',
                  icon: TpIcons.campusCard,
                  onTap: () => tappedId = 'feat-$i',
                ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('功能6'), findsOneWidget);
    await tester.tap(find.text('功能6'));
    expect(tappedId, 'feat-6');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TpBentoGrid switches between single column and two columns',
      (tester) async {
    // Narrow: single Column
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrap(
        const SingleChildScrollView(
          child: TpBentoGrid(
            primaryColumn: [Text('Primary')],
            secondaryColumn: [Text('Secondary')],
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Secondary')).dy,
      greaterThan(tester.getTopLeft(find.text('Primary')).dy),
    );

    // Wide >= 960: two-column Row
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Secondary')).dx,
      greaterThan(tester.getTopLeft(find.text('Primary')).dx),
    );
  });
}
