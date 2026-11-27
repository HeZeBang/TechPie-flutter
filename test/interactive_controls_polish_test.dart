import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/presentation/theme/colors.dart';
import 'package:techpie/features/campus_card/presentation/widgets/gp_button.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/debug_log_page.dart';
import 'package:techpie/pages/oa_gym_page.dart';
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
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/adaptive_text_input_dialog.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_sidebar_item.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/desktop_popup.dart';
import 'package:techpie/widgets/desktop_select_popover.dart';
import 'package:techpie/widgets/swipeable_card.dart';

class _SignedInAuth extends AuthService {
  _SignedInAuth(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;

  @override
  UserSession? get session => UserSession(
        userId: '20240001',
        userName: '张同学',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _BoundThirdParty extends ThirdPartyAuthService {
  _BoundThirdParty(super.storage, super.http);

  static final ThirdPartyAccount _ids = ThirdPartyAccount(
    platform: ThirdPartyPlatform.ids,
    account: '20240001',
    sid: '20240001',
    name: '张同学',
    email: 'zhang@shanghaitech.edu.cn',
    token: 'mock-token',
    boundAt: DateTime(2026, 1, 1),
  );

  @override
  bool get hasIdsBinding => true;

  @override
  ThirdPartyAccount? get idsAccount => _ids;

  @override
  String get idsStudentId => _ids.idsStudentId;
}

class _ReadyOaGymService extends OaGymService {
  _ReadyOaGymService(super.auth, super.storage, super.tpAuth);

  @override
  Future<void> ensureReady() async {}

  @override
  Map<String, String> get venues => const {'羽毛球1号场': '1'};
}

Future<({TechPieApp app, ThemeService theme, StorageService storage})>
    _createFullApp({
  bool signedIn = true,
  bool debugEnabled = false,
  Map<String, Object> extraPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'privacy_accepted_v1': true,
    ...extraPrefs,
  });
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger()..enabled = debugEnabled;
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = signedIn
      ? _SignedInAuth(storage, http, uniAuth)
      : AuthService(storage, http, uniAuth);
  final tpAuth = signedIn
      ? _BoundThirdParty(storage, http)
      : ThirdPartyAuthService(storage, http);
  final theme = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  await schedule.loadCachedData();
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)
    ..loadCached();
  final campusCard = CampusCardService();
  addTearDown(http.close);

  final app = TechPieApp(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: theme,
    scheduleService: schedule,
    assignmentService: assignments,
    thirdPartyAuthService: tpAuth,
    oaGymService: OaGymService(auth, storage, tpAuth),
    egateAppService: EgateAppService(auth, storage, tpAuth),
    uniAuthService: uniAuth,
    syncService: SyncService(auth, tpAuth, storage),
    updateService: UpdateService(),
    campusCardService: campusCard,
    ecardBindService: EcardBindService(),
  );
  return (app: app, theme: theme, storage: storage);
}

void main() {
  testWidgets(
    'DesktopShell renders exact 960dp Bento, preserves per-tab stacks, shows collapsed tooltips, and persists collapse state',
    (tester) async {
      tester.view.physicalSize = const Size(960, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final built = await _createFullApp(
        signedIn: true,
        debugEnabled: true,
      );
      await tester.pumpWidget(built.app);
      await tester.pumpAndSettle();

      // 1. Exact 960dp window immediately enters two-column Bento (no 960–986dp dead zone).
      final coursesPos = tester.getTopLeft(
        find.byKey(const ValueKey('home.today-courses')),
      );
      final cardPos = tester.getTopLeft(
        find.byKey(const ValueKey('home.campus-card-strip')),
      );
      expect(cardPos.dx, greaterThan(coursesPos.dx));

      // Desktop sidebar merges profile into the footer tile and hides the
      // duplicate Home header avatar.
      expect(find.byKey(const ValueKey('home.avatar')), findsNothing);
      final accountTile = find.byKey(const ValueKey('desktop.sidebar-account'));
      expect(
        find.descendant(of: accountTile, matching: find.text('张')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: accountTile, matching: find.text('张同学')),
        findsOneWidget,
      );

      // 2. Collapsing sidebar exposes Tooltips and persists collapse preference.
      await tester.tap(find.byKey(const ValueKey('desktop.sidebar-toggle')));
      await tester.pumpAndSettle();
      expect(built.storage.desktopSidebarCollapsed, isTrue);
      for (final label in ['首页', '课表', 'Deadlines']) {
        expect(
          find.descendant(
            of: find.byType(DesktopSidebarItem),
            matching: find.byWidgetPredicate(
              (w) => w is Tooltip && w.message == label,
            ),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.byType(DesktopSidebarItem),
          matching: find.text('我的'),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: accountTile,
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && (w.message?.contains('张同学') ?? false),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('desktop.sidebar-toggle')));
      await tester.pumpAndSettle();
      expect(built.storage.desktopSidebarCollapsed, isFalse);

      // 3. Account header shows plain username + GeekPie Uni-Auth (no blur switch).
      await tester.tap(accountTile);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text('张同学'),
        ),
        findsOneWidget,
      );
      expect(find.text('GeekPie Uni-Auth'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings.mask-personal-info')), findsNothing);

      // Push DeveloperOptionsPage -> DebugLogPage onto Settings tab stack,
      // switch to Home, then switch back to Settings and confirm DebugLogPage
      // was preserved.
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings.developer-options')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings.developer-options')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看日志'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看日志'));
      await tester.pumpAndSettle();
      expect(find.byType(DebugLogPage), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DesktopSidebarItem),
          matching: find.text('首页'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(accountTile);
      await tester.pumpAndSettle();
      expect(find.byType(DebugLogPage), findsOneWidget);

      // Tapping active sidebar account tile unwinds its stack back to root.
      await tester.tap(accountTile);
      await tester.pumpAndSettle();
      expect(find.byType(DebugLogPage), findsNothing);
    },
  );

  testWidgets(
    'DesktopSelectPopover & showDesktopPopover dismiss on Escape, dim disabled items, and keep ripple unobstructed',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selected = 2;
      final anchorKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true).copyWith(
            extensions: [TpColors.light()],
          ),
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DesktopSelectPopover<int>(
                    items: const [1, 2, 3],
                    value: selected,
                    onChanged: (v) => selected = v,
                    labelBuilder: (v) => '第 $v 周',
                    anchorBuilder: (_, __, toggle) => TextButton(
                      onPressed: toggle,
                      child: const Text('OpenSelect'),
                    ),
                  ),
                  Builder(
                    key: anchorKey,
                    builder: (context) => TextButton(
                      onPressed: () => showDesktopPopover(
                        anchorContext: context,
                        builder: (_, close) => DesktopPopoverSurface(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DesktopMenuRow(
                                selected: true,
                                leading: const Icon(TpIcons.check, size: 18),
                                title: const Text('EnabledRow'),
                                onTap: close,
                              ),
                              const DesktopMenuRow(
                                leading: Icon(TpIcons.add, size: 18),
                                title: Text('DisabledRow'),
                                onTap: null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      child: const Text('OpenPopover'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // DesktopSelectPopover: outer Material paints selection, Escape dismisses.
      await tester.tap(find.text('OpenSelect'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      final selectedRowMaterial = tester.widget<Material>(
        find.ancestor(
          of: find.text('第 2 周'),
          matching: find.byType(Material),
        ).first,
      );
      expect(selectedRowMaterial.color, TpColors.light().opaqueBrandContainer);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsNothing);

      // showDesktopPopover: disabled DesktopMenuRow dims cleanly, Escape dismisses.
      await tester.tap(find.text('OpenPopover'));
      await tester.pumpAndSettle();
      expect(find.text('DisabledRow'), findsOneWidget);
      final disabledOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('DisabledRow'),
          matching: find.byType(Opacity),
        ).first,
      );
      expect(disabledOpacity.opacity, closeTo(0.42, 0.01));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('DisabledRow'), findsNothing);
    },
  );

  testWidgets(
    'AdaptiveTextInputDialog blocks whitespace-only trimResult, supports Enter->next & password visibility toggle',
    (tester) async {
      String? dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true).copyWith(
            extensions: [TpColors.light()],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  dialogResult = await showAdaptiveTextInputDialog(
                    context: context,
                    title: '主密码',
                    fieldLabel: '密码',
                    confirmationFieldLabel: '确认密码',
                    confirmLabel: '保存',
                    obscureText: true,
                    trimResult: true,
                  );
                },
                child: const Text('LaunchDialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('LaunchDialog'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));

      // Whitespace-only input must keep confirm disabled when trimResult == true.
      await tester.enterText(fields.at(0), '   ');
      await tester.enterText(fields.at(1), '   ');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      // Toggle password visibility flips obscureText on both fields.
      expect(tester.widget<TextField>(fields.at(0)).obscureText, isTrue);
      await tester.tap(find.byTooltip('显示密码').first);
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(0)).obscureText, isFalse);

      // Matching password + submit on field 2 returns trimmed value.
      await tester.enterText(fields.at(0), ' secret ');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      await tester.enterText(fields.at(1), ' secret ');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(dialogResult, 'secret');
    },
  );

  testWidgets(
    'AssignmentsPage provides desktop quick-complete & quick-hide buttons and Escape exits selection mode',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dueSoon = DateTime.now().add(const Duration(hours: 12));
      final dueLater = DateTime.now().add(const Duration(days: 15, hours: 7));
      const firstTitle = 'CS100 Homework 1: Final Reports';
      final cachedJson = jsonEncode([
        Assignment(
          id: 'hw-1',
          title: firstTitle,
          course: 'CS100',
          platform: 'gradescope',
          due: dueSoon,
          status: 'No Submission',
        ).toJson(),
        Assignment(
          id: 'hw-5',
          title: 'hw5',
          course: '编译原理 2026秋',
          platform: 'blackboard',
          due: dueLater,
          status: 'Open',
        ).toJson(),
        ExamAssignment(
          id: 'exam-1',
          title: '期末考试',
          course: 'CS100',
          due: dueLater.add(const Duration(days: 1)),
          semesterId: '2026',
          location: '教室 101',
          batchName: '期末',
        ).toJson(),
      ]);

      SharedPreferences.setMockInitialValues({
        'privacy_accepted_v1': true,
        'cached_assignments': cachedJson,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      final uniAuth = UniAuthService();
      final auth = _SignedInAuth(storage, http, uniAuth);
      final tpAuth = _BoundThirdParty(storage, http);
      final theme = ThemeService(storage);
      final schedule = ScheduleService(storage, http, auth, tpAuth);
      final assignments = AssignmentService(storage, http, auth, tpAuth, schedule)
        ..loadCached();
      final campusCard = CampusCardService();
      final allowance = StudentAllowanceService(auth, tpAuth);
      addTearDown(campusCard.dispose);
      addTearDown(allowance.dispose);
      addTearDown(http.close);

      await tester.pumpWidget(
        ServiceProvider(
          authService: auth,
          debugLogger: logger,
          storageService: storage,
          themeService: theme,
          scheduleService: schedule,
          assignmentService: assignments,
          thirdPartyAuthService: tpAuth,
          oaGymService: OaGymService(auth, storage, tpAuth),
          egateAppService: EgateAppService(auth, storage, tpAuth),
          studentAllowanceService: allowance,
          uniAuthService: uniAuth,
          syncService: SyncService(auth, tpAuth, storage),
          updateService: UpdateService(),
          campusCardService: campusCard,
          ecardBindService: EcardBindService(),
          child: MaterialApp(
            theme: theme.lightTheme,
            builder: (_, child) => AdaptiveFeedbackHost(
              key: adaptiveFeedbackHostKey,
              child: child!,
            ),
            home: const AssignmentsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Upcoming items share one card.
      expect(find.byType(TpCard), findsOneWidget);
      expect(find.text('即将截止'), findsOneWidget);
      expect(find.text('3 项'), findsOneWidget);
      // Clean metadata casing & no redundant Open/No Submission noise.
      expect(find.text('编译原理 2026秋 · Blackboard'), findsOneWidget);
      expect(find.text('剩余 15 天'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(find.text('No Submission'), findsNothing);

      // Geometry guard: slim row height (<96dp) and trailing controls pinned
      // flush to the card's right edge (never floating in the middle).
      final cardRect = tester.getRect(find.byType(TpCard));
      final firstRowSwipe = find
          .ancestor(
            of: find.text(firstTitle),
            matching: find.byType(SwipeableCard),
          )
          .first;
      expect(tester.getSize(firstRowSwipe).height, lessThan(96));

      final quickHideRect = tester.getRect(find.byTooltip('忽略').first);
      expect(cardRect.right - quickHideRect.right, lessThanOrEqualTo(24));

      // Desktop quick actions are visible and functional.
      expect(find.byTooltip('标记完成'), findsNWidgets(3));
      expect(find.byTooltip('忽略'), findsNWidgets(3));

      // Long-press enters multi-select, Escape exits cleanly.
      final firstTitleSize = tester.getSize(find.text(firstTitle));
      await tester.longPress(find.text(firstTitle));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 个'), findsOneWidget);
      expect(tester.getSize(find.text(firstTitle)), firstTitleSize);
      expect(tester.getRect(find.byType(TpCard)), cardRect);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Deadlines'), findsOneWidget);

      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.text('Deadlines'), findsNothing);
      expect(find.text('选择截止事项'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
      expect(tester.getRect(find.byType(TpCard)), cardRect);

      await tester.tap(find.byTooltip('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 3 个'), findsOneWidget);
      await tester.tap(find.byTooltip('全不选'));
      await tester.pumpAndSettle();
      expect(find.text('选择截止事项'), findsOneWidget);

      await tester.tap(find.byTooltip('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('反选'));
      await tester.pumpAndSettle();
      expect(find.text('选择截止事项'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Deadlines'), findsOneWidget);

      // Quick-complete marks the item completed and collapses into 已完成.
      await tester.tap(find.byTooltip('标记完成').first);
      await tester.pumpAndSettle();
      expect(find.text('已完成 (1)'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'OaGymPage preserves tab state across switches and validates required profile fields',
    (tester) async {
      SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      final uniAuth = UniAuthService();
      final auth = _SignedInAuth(storage, http, uniAuth);
      final tpAuth = _BoundThirdParty(storage, http);
      final theme = ThemeService(storage);
      final schedule = ScheduleService(storage, http, auth, tpAuth);
      final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
      final campusCard = CampusCardService();
      final allowance = StudentAllowanceService(auth, tpAuth);
      addTearDown(campusCard.dispose);
      addTearDown(allowance.dispose);
      addTearDown(http.close);

      await tester.pumpWidget(
        ServiceProvider(
          authService: auth,
          debugLogger: logger,
          storageService: storage,
          themeService: theme,
          scheduleService: schedule,
          assignmentService: assignments,
          thirdPartyAuthService: tpAuth,
            oaGymService: _ReadyOaGymService(auth, storage, tpAuth),
            egateAppService: EgateAppService(auth, storage, tpAuth),
            studentAllowanceService: allowance,
            uniAuthService: uniAuth,
            syncService: SyncService(auth, tpAuth, storage),
            updateService: UpdateService(),
            campusCardService: campusCard,
            ecardBindService: EcardBindService(),
            child: MaterialApp(
              theme: theme.lightTheme,
              builder: (_, child) => AdaptiveFeedbackHost(
                key: adaptiveFeedbackHostKey,
                child: child!,
              ),
              home: const OaGymPage(),
            ),
          ),
        );
      await tester.pumpAndSettle();

      // Switch to 查询 tab: initial message prompts search instead of empty result.
      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('选择条件后点击「查询预约记录」'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('选择条件后点击「查询预约记录」'), findsOneWidget);

      // Select a sport chip, switch to 个人信息, edit name, and verify state survives switching back.
      await tester.scrollUntilVisible(
        find.text('羽毛球'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('羽毛球'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('个人信息'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '保留姓名');
      await tester.enterText(fields.at(1), '');
      await tester.pump();

      // Switch back to 查询 and verify 羽毛球 chip stays selected (AutomaticKeepAliveClientMixin).
      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      final badmintonChip = tester.widget<FilterChip>(
        find.ancestor(of: find.text('羽毛球'), matching: find.byType(FilterChip)),
      );
      expect(badmintonChip.selected, isTrue);

      // Switch back to 个人信息 and confirm unsaved text survived + empty phone triggers validation.
      await tester.tap(find.text('个人信息'));
      await tester.pumpAndSettle();
      expect(find.text('保留姓名'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('保存'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请填写手机号'), findsOneWidget);
      adaptiveFeedbackHostKey.currentState?.dismiss();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'GpButton paints background on outer Material for visible ripples and GpColors.lerp interpolates smoothly',
    (tester) async {
      final lightTheme = ThemeData.light(useMaterial3: true).copyWith(
        extensions: [TpColors.light()],
      );
      final darkTheme = ThemeData.dark(useMaterial3: true).copyWith(
        extensions: [TpColors.dark()],
      );
      final gpLight = GpColors.fromTheme(lightTheme);
      final gpDark = GpColors.fromTheme(darkTheme);
      final mid = gpLight.lerp(gpDark, 0.5);
      expect(mid.bg, Color.lerp(gpLight.bg, gpDark.bg, 0.5));
      expect(mid.action, Color.lerp(gpLight.action, gpDark.action, 0.5));

      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: Scaffold(
            body: Center(
              child: GpButton(
                label: '立即亮码',
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(GpButton),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, gpLight.action);
      await tester.tap(find.text('立即亮码'));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'AppShell has zero overflow across narrow, short desktop, and 1.25x text scale in Light/Dark/AMOLED',
    (tester) async {
      final built = await _createFullApp(signedIn: false);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: built.app,
        ),
      );

      for (final mode in [
        AppThemeMode.light,
        AppThemeMode.dark,
        AppThemeMode.amoled,
      ]) {
        await built.theme.setMode(mode);
        for (final size in [
          const Size(390, 844),
          const Size(800, 480),
          const Size(1280, 800),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
