import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/features/campus_card/presentation/icons/platform_icons.dart';
import 'package:techpie/features/campus_card/presentation/theme/glass.dart';
import 'package:techpie/features/campus_card/presentation/theme/theme.dart';
import 'package:techpie/features/campus_card/presentation/widgets/apple_wallet_components.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

void main() {
  testWidgets('list rows expose their tap action to accessibility',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppleListRow(
            label: 'Date Range',
            value: 'No Date Range',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(AppleListRow));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('settings rows preserve the trailing switch accessibility action',
      (tester) async {
    final handle = tester.ensureSemantics();
    var enabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppleListRow(
              label: 'Debug mode',
              trailing: Switch.adaptive(
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
            ),
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(AppleListRow));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();
    expect(enabled, isTrue);
    handle.dispose();
  });

  testWidgets('keeps list item icons and labels on the same center line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppleSection(
            children: [
              AppleListRow(icon: CupertinoIcons.lock_shield, label: '安全中心'),
            ],
          ),
        ),
      ),
    );

    final iconCenter = tester.getCenter(
      find.byIcon(CupertinoIcons.lock_shield),
    );
    final textCenter = tester.getCenter(find.text('安全中心'));
    expect((iconCenter.dy - textCenter.dy).abs(), lessThan(0.1));
  });

  testWidgets('keeps four mask dots at natural width, separate from the digits',
      (
    tester,
  ) async {
    for (final fontSize in [9.0, 14.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MaskedCardNumberText(
            maskedNumber: '2025233184',
            style: TextStyle(fontSize: fontSize),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.text.toPlainText(), '••••\u00A03184');
      final paragraph =
          tester.renderObject<RenderParagraph>(find.byType(RichText));
      final dots = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
          )
          .single;
      final natural = TextPainter(
        text: TextSpan(text: '••••', style: richText.text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(dots.right - dots.left, greaterThanOrEqualTo(natural.width - 0.1));
      natural.dispose();
    }
  });

  test('uses only the Chinese cardholder name in the Chinese layout', () {
    expect(
      cardholderDisplayName('陆天成 Lu Tiancheng', languageCode: 'zh'),
      '陆天成',
    );
    expect(
      cardholderDisplayName('陆天成 Lu Tiancheng', languageCode: 'en'),
      '陆天成 Lu Tiancheng',
    );
  });

  testWidgets('uses one sliding thumb for information and activity', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => AppleSegmentedControl(
            labels: const ['信息', '使用明细'],
            selectedIndex: selected,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    await tester.tap(find.text('使用明细'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('renders transaction signs and icons from real semantics', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 2, 22, 32, 54);
    final records = [
      TransactionRecord(
        id: 'ACTION',
        occurredAt: now,
        title: '持卡人修改消费限额',
        merchantName: '持卡人修改消费限额',
        amount: MoneyFen.zero,
        kind: TransactionKind.adjustment,
      ),
      TransactionRecord(
        id: 'CARRY',
        occurredAt: now,
        title: '余额结转',
        merchantName: '余额结转',
        amount: const MoneyFen(9207),
        kind: TransactionKind.recharge,
      ),
      TransactionRecord(
        id: 'PAY',
        occurredAt: now,
        title: '虚拟卡主扫支付',
        merchantName: '合成场馆',
        amount: const MoneyFen(-1),
        kind: TransactionKind.consumption,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [TransactionList(items: records, onTap: (_) {})],
          ),
        ),
      ),
    );

    expect(find.text('¥0.00'), findsOneWidget);
    expect(find.text('+¥92.07'), findsOneWidget);
    expect(find.text('-¥0.01'), findsOneWidget);
    expect(find.byIcon(GpPlatformIcons.limits.android), findsOneWidget);
    expect(find.byIcon(GpPlatformIcons.recharge.android), findsOneWidget);
    expect(find.byIcon(GpPlatformIcons.consumption.android), findsOneWidget);
  });

  testWidgets('appending a page preserves an in-progress transaction tap',
      (tester) async {
    TransactionRecord record(int index) => TransactionRecord(
          id: 'PAGE-$index',
          occurredAt: DateTime.utc(2026, 9, 1),
          title: 'Consumption',
          merchantName: 'page merchant $index',
          amount: const MoneyFen(-100),
          kind: TransactionKind.consumption,
        );
    var records = [record(0), record(1)];
    String? selected;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return CustomScrollView(
                slivers: [
                  TransactionList(
                    items: records,
                    onTap: (item) => selected = item.id,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.text('page merchant 1')),
    );
    await tester.pump();
    update(() => records = [...records, record(2)]);
    await tester.pump();
    await pointer.up();
    await tester.pump();
    expect(selected, 'PAGE-1');
  });

  testWidgets('applies and clears pressed color without an animation delay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppleSection(
            children: [AppleListRow(label: '可点击条目', onTap: () {})],
          ),
        ),
      ),
    );
    final row = find.byType(AppleListRow);
    final colored = find.descendant(of: row, matching: find.byType(ColoredBox));
    expect((tester.widget<ColoredBox>(colored).color), Colors.transparent);

    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump();
    expect(tester.widget<ColoredBox>(colored).color, isNot(Colors.transparent));

    await gesture.up();
    await tester.pump();
    expect((tester.widget<ColoredBox>(colored).color), Colors.transparent);
  });

  testWidgets('Android runs the complete success animation and haptic event', (
    tester,
  ) async {
    final feedback = InMemoryFeedbackPort();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: AnimatedSuccessCheck(
            key: const Key('android-success-animation'),
            feedback: feedback,
          ),
        ),
      ),
    );
    await tester.pump();

    double scale() {
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byKey(const Key('android-success-animation')),
          matching: find.byType(Transform),
        ),
      );
      return transform.transform.getMaxScaleOnAxis();
    }

    final initialScale = scale();
    await tester.pump(const Duration(milliseconds: 360));
    final middleScale = scale();
    await tester.pump(const Duration(milliseconds: 500));
    final completedScale = scale();

    expect(middleScale, isNot(closeTo(initialScale, 0.001)));
    expect(completedScale, closeTo(1, 0.001));
    expect(feedback.events, [FeedbackEvent.paymentSuccess]);
  });

  testWidgets('pinned page header does not move with its scrollable content', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplePinnedHeaderLayout(
            leading: CampusCardHeaderAction(
              id: 'back',
              key: const Key('fixed-header-icon'),
              icon: Icons.arrow_back,
              sfSymbol: 'chevron.left',
              label: 'Back',
              onPressed: () {},
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.only(
                top: ApplePinnedHeaderLayout.contentTop,
              ),
              children: const [SizedBox(height: 1200)],
            ),
          ),
        ),
      ),
    );
    final before = tester.getTopLeft(
      find.byKey(const Key('fixed-header-icon')),
    );

    controller.jumpTo(500);
    await tester.pump();

    expect(
      tester.getTopLeft(find.byKey(const Key('fixed-header-icon'))),
      before,
    );
  });

  testWidgets('pull-to-refresh stays below the header and uses neutral gray', (
    tester,
  ) async {
    const primary = Color(0xFF6750A4);
    const neutralGray = Color(0xFF74747C);
    await tester.pumpWidget(
      MaterialApp(
        theme: GeekPayTheme.inherit(
          ThemeData(
            colorScheme: const ColorScheme.light(
              primary: primary,
              onSurfaceVariant: neutralGray,
            ),
          ),
        ),
        home: Scaffold(
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              EcardSliverRefreshControl(onRefresh: () async {}),
              const SliverToBoxAdapter(child: SizedBox(height: 1000)),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 150));
    await tester.pump();

    final finder = find.byKey(
      const Key('ecard-pull-to-refresh-indicator'),
    );
    expect(finder, findsOneWidget);
    final indicator = tester.widget<CupertinoActivityIndicator>(finder);
    expect(indicator.color, neutralGray);
    expect(
      tester.getCenter(finder).dy,
      greaterThan(ApplePinnedHeaderLayout.contentTop),
    );
  });

  testWidgets(
      'header actions use native items and preserve visual order on iOS',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var infoPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApplePinnedHeaderLayout(
            title: 'Campus card',
            leading: CampusCardHeaderAction(
              id: 'back',
              icon: Icons.arrow_back,
              sfSymbol: 'chevron.left',
              label: 'Back',
              onPressed: () {},
            ),
            actions: [
              const CampusCardHeaderAction(
                id: 'scan',
                icon: Icons.qr_code_scanner,
                sfSymbol: 'qrcode.viewfinder',
                label: 'Scan',
                onPressed: null,
              ),
              CampusCardHeaderAction(
                id: 'info',
                icon: Icons.info_outline,
                sfSymbol: 'info.circle',
                label: 'Card details',
                onPressed: () => infoPressed = true,
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final bar = tester
        .widget<IosNativeNavigationBar>(find.byType(IosNativeNavigationBar));
    expect(bar.leadingItems.single.sfSymbol, 'chevron.left');
    expect(bar.trailingItems.map((item) => item.id), ['info', 'scan']);
    expect(bar.trailingItems.last.enabled, isFalse);
    bar.onItemPressed!('info');
    expect(infoPressed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS glass has a liquid tint over a blurred backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: const GpGlass(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          child: SizedBox(width: 100, height: 52),
        ),
      ),
    );

    final tint = tester.widget<DecoratedBox>(
      find.byKey(const Key('gp-liquid-glass-tint')),
    );
    expect((tint.decoration as BoxDecoration).gradient, isA<LinearGradient>());
    expect(find.byKey(const Key('gp-liquid-glass-blur')), findsOneWidget);
  });

  testWidgets('Android glass uses its platform blur without liquid tint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: const GpGlass(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          child: SizedBox(width: 100, height: 52),
        ),
      ),
    );

    final tint = tester.widget<DecoratedBox>(
      find.byKey(const Key('gp-android-blur-tint')),
    );
    expect((tint.decoration as BoxDecoration).gradient, isNull);
    expect(find.byKey(const Key('gp-android-glass-blur')), findsOneWidget);
  });
}
