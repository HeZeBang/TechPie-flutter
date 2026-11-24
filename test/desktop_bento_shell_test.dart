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
import 'package:techpie/widgets/app_shell/desktop/desktop_shell.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_item.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_tokens.dart';
import 'package:techpie/widgets/app_shell/tg_bottom_nav_bar.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
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
    expect(find.text('TechPie'), findsOneWidget);

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

    final material = tester.widget<Material>(
      find.descendant(of: selectedItemFinder, matching: find.byType(Material)),
    );
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: selectedItemFinder, matching: find.byType(InkWell)),
    );
    final label = tester.widget<Text>(
      find.descendant(of: selectedItemFinder, matching: find.byType(Text)),
    );

    final tp = TpColors.light();
    expect(material.color, tp.opaqueBrandContainer);
    expect(inkWell.hoverColor, Colors.transparent);
    expect(label.style?.color, tp.textPrimary);
  });

  testWidgets('SettingsPage toggles update live on wide desktop window',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);

    await tester.tap(find.text('我的').first);
    await tester.pumpAndSettle();

    final maskRow = find.byKey(const ValueKey('settings.mask-personal-info'));
    expect(maskRow, findsOneWidget);
    final switchFinder = find.descendant(
      of: maskRow,
      matching: find.byType(Switch),
    );
    final before = tester.widget<Switch>(switchFinder).value;
    await tester.tap(maskRow);
    await tester.pumpAndSettle();
    final after = tester.widget<Switch>(switchFinder).value;
    expect(after, isNot(before));
  });
}
