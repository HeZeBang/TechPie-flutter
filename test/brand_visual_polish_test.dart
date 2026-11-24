import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/settings_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/theme/theme.dart';
import 'package:techpie/widgets/app_shell/app_destination.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_tokens.dart';
import 'package:techpie/widgets/course_detail_panel.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/desktop_popup.dart';

ThemeData _lightTheme() {
  final tp = TpColors.light();
  return ThemeData(
    useMaterial3: true,
    colorScheme: tp.toColorScheme(),
    extensions: [tp],
  );
}

void main() {
  Widget wrapTheme(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme ?? _lightTheme(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  Future<ServiceProvider> buildServiceProvider({
    required Widget child,
  }) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments =
        AssignmentService(storage, http, auth, tpAuth, schedule);
    return ServiceProvider(
      authService: auth,
      debugLogger: logger,
      storageService: storage,
      themeService: ThemeService(storage),
      scheduleService: schedule,
      assignmentService: assignments,
      thirdPartyAuthService: tpAuth,
      oaGymService: OaGymService(auth, storage, tpAuth),
      egateAppService: EgateAppService(auth, storage, tpAuth),
      studentAllowanceService: StudentAllowanceService(auth, tpAuth),
      uniAuthService: uniAuth,
      syncService: SyncService(auth, tpAuth, storage),
      updateService: UpdateService(),
      campusCardService: CampusCardService(),
      ecardBindService: EcardBindService(),
      child: child,
    );
  }

  testWidgets(
      'TpCampusCardStrip expanded entity card renders artwork, blur, and pay action',
      (tester) async {
    var payTaps = 0;
    var cardTaps = 0;

    await tester.pumpWidget(
      wrapTheme(
        SizedBox(
          width: 360,
          child: TpCampusCardStrip(
            configured: true,
            balanceText: '¥ 128.50',
            maskPersonalInfo: true,
            expandedCard: true,
            onOpenPayCode: () => payTaps++,
            onOpenCard: () => cardTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('校园卡'), findsOneWidget);
    expect(find.text('••••'), findsOneWidget);
    expect(find.text('¥ 128.50'), findsNothing);
    expect(find.text('亮码'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home.campus-card-pay')));
    await tester.pumpAndSettle();
    expect(payTaps, 1);

    await tester.pumpWidget(
      wrapTheme(
        SizedBox(
          width: 360,
          child: TpCampusCardStrip(
            configured: true,
            balanceText: '¥ 128.50',
            maskPersonalInfo: false,
            expandedCard: true,
            onOpenPayCode: () => payTaps++,
            onOpenCard: () => cardTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¥ 128.50'), findsOneWidget);
    await tester.tap(find.text('¥ 128.50'));
    await tester.pumpAndSettle();
    expect(cardTaps, 1);

    // Unconfigured expanded card preserves setup CTA.
    await tester.pumpWidget(
      wrapTheme(
        SizedBox(
          width: 360,
          child: TpCampusCardStrip(
            configured: false,
            balanceText: null,
            maskPersonalInfo: true,
            expandedCard: true,
            onOpenPayCode: () => payTaps++,
            onOpenCard: () => cardTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('校园一卡通'), findsOneWidget);
    expect(find.text('点击绑定'), findsOneWidget);
    expect(find.text('进入'), findsOneWidget);

    // Compact strip renders mini entity thumbnail.
    await tester.pumpWidget(
      wrapTheme(
        SizedBox(
          width: 360,
          child: TpCampusCardStrip(
            configured: true,
            balanceText: '¥ 128.50',
            maskPersonalInfo: false,
            expandedCard: false,
            onOpenPayCode: () => payTaps++,
            onOpenCard: () => cardTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('home.campus-card-mini-thumb')),
      findsOneWidget,
    );
  });

  testWidgets(
      'TpCampusCardStrip expanded card maintains full-bleed aspect ratio across resizes and fills bounded height',
      (tester) async {
    for (final width in [304.0, 400.0, 496.0]) {
      await tester.pumpWidget(
        wrapTheme(
          SizedBox(
            width: width,
            child: TpCampusCardStrip(
              configured: true,
              balanceText: '¥ 128.50',
              maskPersonalInfo: false,
              expandedCard: true,
              onOpenPayCode: () {},
              onOpenCard: () {},
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

    // Bounded height fills 100% top-to-bottom without clipping or gaps.
    await tester.pumpWidget(
      wrapTheme(
        SizedBox(
          width: 420,
          height: 310,
          child: TpCampusCardStrip(
            configured: true,
            balanceText: '¥ 128.50',
            maskPersonalInfo: false,
            expandedCard: true,
            onOpenPayCode: () {},
            onOpenCard: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final stretchedSize = tester.getSize(
      find.byKey(const ValueKey('home.campus-card-strip')),
    );
    expect(stretchedSize.height, closeTo(310.0, 2.0));
    expect(tester.takeException(), isNull);
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

    // Urgent badge expanded (>99 caps at 99+)
    await tester.pumpWidget(
      wrapTheme(
        Row(
          children: [
            SizedBox(
              width: DesktopSidebarTokens.maxExpandedWidth,
              child: DesktopSidebar(
                destinations: destinations,
                selectedIndex: 0,
                collapsed: false,
                badges: const {
                  1: SidebarBadgeData(count: 120, urgent: true),
                },
                onSelected: (_) {},
                onToggleCollapsed: () {},
              ),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badgeFinder = find.byKey(const ValueKey('sidebar-badge-Deadlines'));
    expect(badgeFinder, findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    final urgentDecor =
        tester.widget<Container>(badgeFinder).decoration! as BoxDecoration;
    expect(urgentDecor.color, TpColors.light().dangerRed);

    // Calm non-urgent badge expanded
    await tester.pumpWidget(
      wrapTheme(
        Row(
          children: [
            SizedBox(
              width: DesktopSidebarTokens.maxExpandedWidth,
              child: DesktopSidebar(
                destinations: destinations,
                selectedIndex: 0,
                collapsed: false,
                badges: const {
                  1: SidebarBadgeData(count: 4, urgent: false),
                },
                onSelected: (_) {},
                onToggleCollapsed: () {},
              ),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    final calmDecor =
        tester.widget<Container>(badgeFinder).decoration! as BoxDecoration;
    expect(calmDecor.color, TpColors.light().surfaceSubtle);

    // Collapsed shows dot indicator + count in Tooltip
    await tester.pumpWidget(
      wrapTheme(
        Row(
          children: [
            SizedBox(
              width: DesktopSidebarTokens.collapsedWidth,
              child: DesktopSidebar(
                destinations: destinations,
                selectedIndex: 0,
                collapsed: true,
                badges: const {
                  1: SidebarBadgeData(count: 5, urgent: true),
                },
                onSelected: (_) {},
                onToggleCollapsed: () {},
              ),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
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

  testWidgets(
      'CourseDetailContent renders accent bar, kind badges, and copies title & location',
      (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const examCourse = Course(
      name: '线性代数期末考试',
      location: '教学中心 204',
      dayOfWeek: 3,
      placement: CoursePlacement(
        startPeriod: 1,
        endPeriod: 2,
        gridStart: 0,
        gridEnd: 2,
        usesCustomTime: false,
        startTime: '08:15',
        endTime: '09:55',
        label: '08:15 – 09:55 (第1-2节)',
      ),
      color: CourseColor.error,
      teachers: '王老师',
      weeksText: '第 18 周',
      source: ExamCourseSource('exam-1'),
    );

    await tester.pumpWidget(
      wrapTheme(
        const SizedBox(
          width: 360,
          child: CourseDetailContent(course: examCourse),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('course-detail.accent-bar')),
      findsOneWidget,
    );
    expect(find.text('考试'), findsOneWidget);
    expect(find.text('线性代数期末考试'), findsOneWidget);
    expect(find.text('教学中心 204'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('course-detail.title')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(copiedText, '线性代数期末考试');

    await tester.tap(find.byKey(const ValueKey('course-detail.location')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(copiedText, '教学中心 204');
  });

  testWidgets(
      'AssignmentsPage uses frosted DesktopPopoverSurface on wide desktop',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tree = await buildServiceProvider(
      child: MaterialApp(
        theme: _lightTheme(),
        home: const AssignmentsPage(),
      ),
    );
    await tester.pumpWidget(tree);
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.byType(DesktopPopoverSurface), findsOneWidget);
    expect(find.byType(DesktopMenuRow), findsWidgets);
    expect(find.text('显示作业'), findsOneWidget);
    expect(find.text('添加 Deadline'), findsOneWidget);
  });

  testWidgets('SettingsPage renders TpBrandMark in About row and GeekPie footer',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tree = await buildServiceProvider(
      child: MaterialApp(
        theme: _lightTheme(),
        home: const SettingsPage(),
      ),
    );
    await tester.pumpWidget(tree);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings.brand-footer')),
      300,
    );
    await tester.pumpAndSettle();

    expect(find.byType(TpBrandMark), findsAtLeastNWidgets(2));
    expect(
      find.text('TechPie · Built with Flutter by GeekPie_'),
      findsOneWidget,
    );
  });
}
