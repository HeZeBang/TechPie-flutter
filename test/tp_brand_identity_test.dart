import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/home_page.dart';
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
import 'package:techpie/theme/tp_tokens.dart';
import 'package:techpie/widgets/app_shell/app_destination.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_shell.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/privacy_consent.dart';

Future<Widget> _buildHomeHost({required Widget child}) async {
  SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = AuthService(storage, http, uniAuth);
  final tpAuth = ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
  final campusCard = CampusCardService();
  final allowance = StudentAllowanceService(auth, tpAuth);
  addTearDown(campusCard.dispose);
  addTearDown(allowance.dispose);
  addTearDown(http.close);

  return ServiceProvider(
    authService: auth,
    debugLogger: logger,
    storageService: storage,
    themeService: themeService,
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
      theme: themeService.lightTheme,
      home: child,
    ),
  );
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
    'TpBrandMark renders pure-vector CustomPaint without Image across Light, Dark, and AMOLED themes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final themeService = ThemeService(StorageService(prefs));
      final lightTheme = themeService.lightTheme;
      final darkTheme = themeService.darkTheme;
      await themeService.setMode(AppThemeMode.amoled);
      final amoledTheme = themeService.darkTheme;

      for (final theme in [lightTheme, darkTheme, amoledTheme]) {
        for (final variant in TpBrandMarkVariant.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: TpBrandMark(size: 36, variant: variant),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(Image), findsNothing);
          expect(
            find.descendant(
              of: find.byType(TpBrandMark),
              matching: find.byType(CustomPaint),
            ),
            findsOneWidget,
          );
        }
      }
    },
  );

  testWidgets(
    'Brand identity keeps classic TechRed accent even when ThemeService switches to system accent',
    (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final themeService = ThemeService(StorageService(prefs));
        await themeService.setColorScheme(AppColorScheme.system);

        await tester.pumpWidget(
          MaterialApp(
            theme: themeService.lightTheme,
            home: const Scaffold(
              body: TpBrandLockup(axis: Axis.horizontal),
            ),
          ),
        );
        await tester.pumpAndSettle();

        TextSpan? findPieSpan(InlineSpan root) {
          TextSpan? found;
          root.visitChildren((span) {
            if (span is TextSpan && span.text == 'Pie') {
              found = span;
              return false;
            }
            return true;
          });
          return found;
        }

        final wordmarkRich = tester.widget<RichText>(
          find.descendant(
            of: find.byType(TpBrandWordmark),
            matching: find.byType(RichText),
          ),
        );
        final pieSpan = findPieSpan(wordmarkRich.text);
        expect(pieSpan?.style?.color, TpTokens.techRedLight);
        expect(pieSpan?.style?.color, isNot(TpTokens.iosBlueLight));

        await tester.pumpWidget(
          MaterialApp(
            theme: themeService.darkTheme,
            home: const Scaffold(
              body: TpBrandLockup(axis: Axis.vertical),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final darkWordmark = tester.widget<RichText>(
          find.descendant(
            of: find.byType(TpBrandWordmark),
            matching: find.byType(RichText),
          ),
        );
        final darkPieSpan = findPieSpan(darkWordmark.text);
        expect(darkPieSpan?.style?.color, TpTokens.techRedDarkInk);
        expect(darkPieSpan?.style?.color, isNot(TpTokens.iosBlueDark));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('TpBrandLockup renders TechPie and by GeekPie_ in horizontal and vertical layouts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TpBrandLockup(),
              TpBrandLockup(axis: Axis.vertical),
            ],
          ),
        ),
      ),
    );

    expect(find.text('TechPie'), findsNWidgets(2));
    expect(find.text('by GeekPie_'), findsNWidgets(2));
  });

  testWidgets('PrivacyConsentPage shows brand lockup in both full and compact modes', (
    tester,
  ) async {
    for (final compact in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyConsentPage(
            compact: compact,
            onAccept: () async {},
          ),
        ),
      );
      expect(find.byKey(const ValueKey('privacy.brand-lockup')), findsOneWidget);
      expect(find.byType(TpBrandMark), findsOneWidget);
      expect(find.text('TechPie'), findsOneWidget);
    }
  });

  testWidgets('HomePage shows lightweight top brand bar on mobile and omits it inside DesktopShell', (
    tester,
  ) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      tester.view.physicalSize = const Size(420, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await _buildHomeHost(child: const HomePage()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home.brand-bar')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home.brand-bar')),
          matching: find.byType(TpBrandMark),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home.avatar')), findsOneWidget);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpWidget(
        await _buildHomeHost(
          child: DesktopShell(
            destinations: const [
              AppDestination(
                label: '首页',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                sfSymbol: 'house',
                selectedSfSymbol: 'house.fill',
                page: SizedBox.shrink(),
              ),
            ],
            selectedIndex: 0,
            sidebarCollapsed: false,
            onDestinationSelected: (_) {},
            onToggleSidebarCollapsed: () {},
            child: const HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home.brand-bar')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('desktop.sidebar-brand')),
          matching: find.byType(TpBrandMark),
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
