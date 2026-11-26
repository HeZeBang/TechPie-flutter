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

  testWidgets('balance-only card masks the amount and opens the feature', (tester) async {
    var opens = 0;
    for (final hidden in [false, true]) {
      await tester.pumpWidget(
        wrap(
          TpCampusCardBalance(
            configured: true,
            balanceText: '¥ 128.50',
            hideBalance: hidden,
            onOpen: () => opens++,
          ),
        ),
      );
      expect(find.text('¥ 128.50'), hidden ? findsNothing : findsOneWidget);
      expect(find.text('余额已隐藏'), hidden ? findsOneWidget : findsNothing);
      expect(find.text('亮码'), findsNothing);
      await tester.tap(find.text('校园卡余额'));
    }
    expect(opens, 2);
  });

  testWidgets('TpCampusCardStrip respects balance eye toggle and configured state',
      (tester) async {
    var payTaps = 0;
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
        ),
      ),
    );
    expect(find.text('余额 ••••'), findsOneWidget);
    expect(find.text('余额 ¥ 128.50'), findsNothing);
    expect(find.text('亮码'), findsOneWidget);

    final eyeFinder =
        find.byKey(const ValueKey('home.campus-card-balance-toggle'));
    final eyeSize = tester.getSize(eyeFinder);
    expect(eyeSize.width, greaterThanOrEqualTo(36));
    expect(eyeSize.height, greaterThanOrEqualTo(36));

    await tester.tap(eyeFinder);
    expect(toggleTaps, 1);
    expect(payTaps, 0);

    // Off-center tap near the edge of the enlarged eye hit box still toggles
    // balance without accidentally opening the payment code.
    await tester.tapAt(tester.getCenter(eyeFinder) + const Offset(14, 13));
    expect(toggleTaps, 2);
    expect(payTaps, 0);

    // Tapping the passive QR indicator and the rest of the card both open pay.
    await tester.tap(find.byKey(const ValueKey('home.campus-card-pay')));
    expect(payTaps, 1);
    await tester.tap(find.text('校园卡'));
    expect(payTaps, 2);

    // Configured + visible balance (default)
    await tester.pumpWidget(
      wrap(
        TpCampusCardStrip(
          configured: true,
          balanceText: '¥ 128.50',
          onToggleHideBalance: () => toggleTaps++,
          onOpenPayCode: () => payTaps++,
        ),
      ),
    );
    expect(find.text('余额 ¥ 128.50'), findsOneWidget);
    await tester.tap(find.text('余额 ¥ 128.50'));
    expect(payTaps, 3);

    // Configured + uncached balance prompt
    await tester.pumpWidget(
      wrap(
        TpCampusCardStrip(
          configured: true,
          balanceText: null,
          onToggleHideBalance: () => toggleTaps++,
          onOpenPayCode: () => payTaps++,
        ),
      ),
    );
    expect(find.text('点击亮码'), findsOneWidget);
    expect(find.text('点击查看卡包与余额'), findsNothing);

    // Unconfigured
    await tester.pumpWidget(
      wrap(
        TpCampusCardStrip(
          configured: false,
          balanceText: null,
          hideBalance: true,
          onOpenPayCode: () => payTaps++,
        ),
      ),
    );
    expect(find.text('进入'), findsOneWidget);
    expect(find.text('绑定后可一键亮码与查看余额'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home.campus-card-balance-toggle')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('home.campus-card-strip')));
    expect(payTaps, 4);
  });

  testWidgets(
      'TpCampusCardStrip expanded entity card keeps 707:445 proportions, fills tight height, and opens pay code across surface',
      (tester) async {
    var toggleTaps = 0;
    var payTaps = 0;

    for (final width in [304.0, 400.0, 496.0]) {
      await tester.pumpWidget(
        wrap(
          Center(
            child: SizedBox(
              width: width,
              child: TpCampusCardStrip(
                configured: true,
                balanceText: '¥ 128.50',
                hideBalance: false,
                onToggleHideBalance: () => toggleTaps++,
                expandedCard: true,
                onOpenPayCode: () => payTaps++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cardSize = tester.getSize(
        find.byKey(const ValueKey('home.campus-card-strip')),
      );
      final headerSize = tester.getSize(
        find.byKey(const ValueKey('home.campus-card-header-band')),
      );
      expect(
        cardSize.height,
        closeTo(width / TpCampusCardStrip.cardAspectRatio, 2.0),
      );
      expect(headerSize.width, closeTo(width, 2.0));
      expect(headerSize.height, greaterThanOrEqualTo(54.0));
    }

    final eyeFinder =
        find.byKey(const ValueKey('home.campus-card-balance-toggle'));
    final eyeSize = tester.getSize(eyeFinder);
    expect(eyeSize.width, greaterThanOrEqualTo(36));
    expect(eyeSize.height, greaterThanOrEqualTo(36));

    await tester.tap(eyeFinder);
    await tester.pumpAndSettle();
    expect(toggleTaps, 1);
    expect(payTaps, 0);

    await tester.tapAt(tester.getCenter(eyeFinder) + const Offset(13, 12));
    await tester.pumpAndSettle();
    expect(toggleTaps, 2);
    expect(payTaps, 0);

    await tester.tap(find.byKey(const ValueKey('home.campus-card-header-band')));
    await tester.pumpAndSettle();
    expect(payTaps, 1);

    await tester.tap(find.byKey(const ValueKey('home.campus-card-entity-balance')));
    await tester.pumpAndSettle();
    expect(payTaps, 2);

    await tester.tap(find.byKey(const ValueKey('home.campus-card-pay')));
    await tester.pumpAndSettle();
    expect(payTaps, 3);

    // Configured + uncached balance prompt
    await tester.pumpWidget(
      wrap(
        Center(
          child: SizedBox(
            width: 360,
            child: TpCampusCardStrip(
              configured: true,
              balanceText: null,
              expandedCard: true,
              onToggleHideBalance: () => toggleTaps++,
              onOpenPayCode: () => payTaps++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('点击亮码'), findsOneWidget);

    // Tight bounded height fills 100% top-to-bottom cleanly.
    await tester.pumpWidget(
      wrap(
        Center(
          child: SizedBox(
            width: 420,
            height: 310,
            child: TpCampusCardStrip(
              configured: true,
              balanceText: '¥ 128.50',
              expandedCard: true,
              onOpenPayCode: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('home.campus-card-strip'))).height,
      closeTo(310.0, 2.0),
    );
    expect(tester.takeException(), isNull);
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
