import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/app_shell/app_destination.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_shell.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_item.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_tokens.dart';
import 'package:techpie/widgets/app_shell/tg_bottom_nav_bar.dart';
import 'package:techpie/widgets/design_system/tp_brand_mark.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    Map<String, Object> extraPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'privacy_accepted_v1': true,
      ...extraPrefs,
    });
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    addTearDown(http.close);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
    await tester.pumpWidget(
      TechPieApp(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: OaGymService(auth, storage, tpAuth),
        egateAppService: EgateAppService(auth, storage, tpAuth),
        uniAuthService: uniAuth,
        syncService: SyncService(auth, tpAuth, storage),
        updateService: UpdateService(),
        campusCardService: CampusCardService(),
        ecardBindService: EcardBindService(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide window renders DesktopShell sidebar and two-column Bento Home',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(DesktopSidebar), findsOneWidget);
    expect(find.byType(TgBottomNavBar), findsNothing);
    expect(find.byType(TpBrandMark), findsOneWidget);
    expect(find.text('TechPie'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DesktopSidebar),
        matching: find.byIcon(TpIcons.graduation),
      ),
      findsNothing,
    );

    // Bento Home places Campus Card & Quick Actions to the right of Today Courses.
    final coursesPos = tester.getTopLeft(
      find.byKey(const ValueKey('home.today-courses')),
    );
    final cardPos = tester.getTopLeft(
      find.byKey(const ValueKey('home.campus-card-strip')),
    );
    final actionsPos = tester.getTopLeft(
      find.byKey(const ValueKey('home.quick-actions')),
    );
    expect(cardPos.dx, greaterThan(coursesPos.dx));
    expect(actionsPos.dx, greaterThan(coursesPos.dx));

    // Toggle sidebar collapse and expand cleanly.
    final expandedWidth = tester.getSize(find.byType(DesktopSidebar)).width;
    expect(expandedWidth, greaterThan(DesktopSidebarTokens.collapsedWidth));
    await tester.tap(find.byKey(const ValueKey('desktop.sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      closeTo(DesktopSidebarTokens.collapsedWidth, 0.5),
    );
    await tester.tap(find.byKey(const ValueKey('desktop.sidebar-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesktopSidebar)).width, expandedWidth);
  });

  testWidgets('AdaptiveFeedback clears bottom bar on mobile but not DesktopShell',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);
    showAdaptiveFeedback(message: '桌面提示');
    await tester.pumpAndSettle();
    final desktopBottom =
        800 - tester.getBottomLeft(find.text('桌面提示')).dy;
    adaptiveFeedbackHostKey.currentState?.dismiss();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(TgBottomNavBar), findsOneWidget);
    showAdaptiveFeedback(message: '手机提示');
    await tester.pumpAndSettle();
    final mobileBottom =
        844 - tester.getBottomLeft(find.text('手机提示')).dy;

    expect(mobileBottom, greaterThan(desktopBottom + 40));
    adaptiveFeedbackHostKey.currentState?.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'selected DesktopSidebarItem maintains high contrast and avoids double-stacked hover tint',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    final selectedItemFinder = find.byWidgetPredicate(
      (widget) => widget is DesktopSidebarItem && widget.selected,
    );
    expect(selectedItemFinder, findsOneWidget);

    final activeIndicator = tester.widget<Material>(
      find.byKey(const ValueKey('desktop.sidebar-active-indicator')),
    );
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: selectedItemFinder, matching: find.byType(InkWell)),
    );
    final label = tester.widget<Text>(
      find.descendant(of: selectedItemFinder, matching: find.byType(Text)),
    );

    final tp = TpColors.light();
    expect(activeIndicator.color, tp.opaqueBrandContainer);
    expect(inkWell.hoverColor, isNotNull);
    expect(inkWell.hoverColor, isNot(Colors.transparent));
    expect(inkWell.hoverColor!.a, lessThan(0.15));
    expect(label.style?.color, tp.textPrimary);

    // Gliding active indicator lands smoothly on the newly tapped destination.
    final indicatorBefore = tester.getTopLeft(
      find.byKey(const ValueKey('desktop.sidebar-active-indicator')),
    );

    // Hovering an unselected item, clicking it, and keeping the pointer on it
    // must keep a constant subtle hover alpha (avoiding InkHighlight turning
    // Colors.transparent into opaque black via Color(0x00000000).withAlpha(255)).
    final scheduleItem = find.ancestor(
      of: find.text('课表'),
      matching: find.byType(DesktopSidebarItem),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(scheduleItem));
    await tester.pumpAndSettle();
    await tester.tap(scheduleItem);
    await tester.pumpAndSettle();

    final indicatorAfter = tester.getTopLeft(
      find.byKey(const ValueKey('desktop.sidebar-active-indicator')),
    );
    expect(
      indicatorAfter.dy - indicatorBefore.dy,
      closeTo(
        DesktopSidebarTokens.navItemHeight + DesktopSidebarTokens.navItemSpacing,
        0.5,
      ),
    );

    final scheduleInkWell = tester.widget<InkWell>(
      find.descendant(of: scheduleItem, matching: find.byType(InkWell)),
    );
    expect(scheduleInkWell.hoverColor, isNot(Colors.transparent));
    expect(scheduleInkWell.hoverColor!.a, lessThan(0.15));
  });

  testWidgets('SettingsPage toggles update live on wide desktop window',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('desktop.sidebar-account')));
    await tester.pumpAndSettle();

    final devOptionsRow =
        find.byKey(const ValueKey('settings.developer-options'));
    await tester.scrollUntilVisible(
      devOptionsRow,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(devOptionsRow);
    await tester.pumpAndSettle();

    final debugRow = find.byKey(const ValueKey('settings.debug-mode'));
    await tester.pumpAndSettle();
    expect(debugRow, findsOneWidget);
    final switchFinder = find.descendant(
      of: debugRow,
      matching: find.byType(Switch),
    );
    final before = tester.widget<Switch>(switchFinder).value;
    await tester.tap(debugRow);
    await tester.pumpAndSettle();
    final after = tester.widget<Switch>(switchFinder).value;
    expect(after, isNot(before));
  });

  testWidgets('DesktopShell restores persisted sidebar collapsed state',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester, extraPrefs: {'desktop_sidebar_collapsed': true});
    expect(
      tester.getSize(find.byType(DesktopSidebar)).width,
      closeTo(DesktopSidebarTokens.collapsedWidth, 0.5),
    );
  });

  testWidgets(
      'DesktopSidebar renders expanded urgent/calm/99+ badges and collapsed dot with tooltip',
      (tester) async {
    const destinations = [
      AppDestination(
        label: '首页',
        icon: TpIcons.home,
        selectedIcon: TpIcons.home,
        sfSymbol: 'house',
        selectedSfSymbol: 'house.fill',
        page: SizedBox(),
      ),
      AppDestination(
        label: 'Deadlines',
        icon: TpIcons.deadlines,
        selectedIcon: TpIcons.deadlines,
        sfSymbol: 'checkmark.circle',
        selectedSfSymbol: 'checkmark.circle.fill',
        page: SizedBox(),
      ),
    ];
    final tp = TpColors.light();
    Widget wrapSidebar({
      required bool collapsed,
      required SidebarBadgeData badge,
    }) =>
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: tp.toColorScheme(),
            extensions: [tp],
          ),
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: collapsed
                      ? DesktopSidebarTokens.collapsedWidth
                      : DesktopSidebarTokens.maxExpandedWidth,
                  child: DesktopSidebar(
                    destinations: destinations,
                    selectedIndex: 0,
                    collapsed: collapsed,
                    badges: {1: badge},
                    onSelected: (_) {},
                    onToggleCollapsed: () {},
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        );

    final badgeFinder = find.byKey(const ValueKey('sidebar-badge-Deadlines'));

    // Urgent badge caps >99 at 99+ with dangerRed background.
    await tester.pumpWidget(
      wrapSidebar(
        collapsed: false,
        badge: const SidebarBadgeData(count: 120, urgent: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
    expect(
      (tester.widget<Container>(badgeFinder).decoration! as BoxDecoration)
          .color,
      tp.dangerRed,
    );

    // Calm badge uses surfaceSubtle.
    await tester.pumpWidget(
      wrapSidebar(
        collapsed: false,
        badge: const SidebarBadgeData(count: 4, urgent: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    expect(
      (tester.widget<Container>(badgeFinder).decoration! as BoxDecoration)
          .color,
      tp.surfaceSubtle,
    );

    // Collapsed mode swaps pill for dot + count in Tooltip.
    await tester.pumpWidget(
      wrapSidebar(
        collapsed: true,
        badge: const SidebarBadgeData(count: 5, urgent: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(badgeFinder, findsNothing);
    expect(
      find.byKey(const ValueKey('sidebar-badge-dot-Deadlines')),
      findsOneWidget,
    );
    expect(find.byTooltip('Deadlines (5)'), findsOneWidget);
  });
}
