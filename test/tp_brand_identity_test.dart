import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
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
import 'package:techpie/theme/tp_colors.dart';
import 'package:techpie/theme/tp_tokens.dart';
import 'package:techpie/widgets/app_shell/app_destination.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_shell.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/privacy_consent.dart';

class _SignedInAuth extends AuthService {
  _SignedInAuth(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;
}

class _AssignmentsWithFixture extends AssignmentService {
  _AssignmentsWithFixture(
    super.storage,
    super.http,
    super.auth,
    super.tpAuth,
    super.schedule,
    this.visibleAssignments,
  );

  @override
  final List<Assignment> visibleAssignments;
}

Future<Widget> _buildHomeHost({
  required Widget child,
  List<Assignment>? visibleAssignments,
}) async {
  SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final logger = DebugLogger();
  final http = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = visibleAssignments == null
      ? AuthService(storage, http, uniAuth)
      : _SignedInAuth(storage, http, uniAuth);
  final tpAuth = ThirdPartyAuthService(storage, http);
  final themeService = ThemeService(storage);
  final schedule = ScheduleService(storage, http, auth, tpAuth);
  final assignments = visibleAssignments == null
      ? AssignmentService(storage, http, auth, tpAuth, schedule)
      : _AssignmentsWithFixture(
          storage,
          http,
          auth,
          tpAuth,
          schedule,
          visibleAssignments,
        );
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

  testWidgets('dark TechPie glyph maintains contrast at its lowest facet', (
    tester,
  ) async {
    final key = GlobalKey();
    const background = TpTokens.darkSurfaceSubtle;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: const ColoredBox(
              color: background,
              child: TpBrandMark(size: 64),
            ),
          ),
        ),
      ),
    );

    final pixels = await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      } finally {
        image.dispose();
      }
    });
    const footFacetOffset = (55 * 64 + 17) * 4;
    final foot = Color.fromARGB(
      255,
      pixels!.getUint8(footFacetOffset),
      pixels.getUint8(footFacetOffset + 1),
      pixels.getUint8(footFacetOffset + 2),
    );
    final contrast =
        (foot.computeLuminance() + 0.05) / (background.computeLuminance() + 0.05);
    expect(contrast, greaterThanOrEqualTo(3));
  });

  testWidgets('Home labels a long late-submission window as needing attention', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.physicalSize = const Size(420, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();

      await tester.pumpWidget(
        await _buildHomeHost(
          child: const HomePage(),
          visibleAssignments: [
            Assignment(
              id: 'long-late-window',
              platform: 'Gradescope',
              title: 'Homework',
              course: 'Calculus',
              due: now.subtract(const Duration(hours: 1)),
              lateDue: now.add(const Duration(days: 2)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final glance = find.byKey(const ValueKey('home.deadlines-glance'));
      expect(
        find.descendant(of: glance, matching: find.text('1 项需关注')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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
              body: Column(
                children: [
                  TpBrandLockup(
                    axis: Axis.horizontal,
                    showSubtitle: true,
                  ),
                  TpBrandSubtitle(
                    prefix: 'GeekPie',
                    accentSuffix: '_',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        TextStyle? findResolvedStyle(
          InlineSpan node,
          String target, [
          TextStyle? inherited,
        ]) {
          final effective = inherited == null
              ? node.style
              : inherited.merge(node.style);
          if (node is TextSpan) {
            if (node.text == target) {
              return effective ?? const TextStyle();
            }
            final children = node.children;
            if (children != null) {
              for (final child in children) {
                final found = findResolvedStyle(child, target, effective);
                if (found != null) return found;
              }
            }
          }
          return null;
        }

        final lightTp = TpColors.fromTheme(themeService.lightTheme);
        final wordmarkText = tester.widget<Text>(
          find.descendant(
            of: find.byType(TpBrandWordmark),
            matching: find.byType(Text),
          ),
        );
        expect(wordmarkText.style?.color, lightTp.textPrimary);
        expect(wordmarkText.style?.color, isNot(TpTokens.iosBlueLight));
        expect(
          wordmarkText.style?.fontFamily,
          TpBrandWordmark.brandFontFamily,
        );
        expect(wordmarkText.style?.fontWeight, FontWeight.w800);

        final lightDefaultSub = tester.widget<Text>(
          find.descendant(
            of: find.descendant(
              of: find.byType(TpBrandLockup),
              matching: find.byType(TpBrandSubtitle),
            ),
            matching: find.byType(Text),
          ),
        );
        expect(lightDefaultSub.style?.color, lightTp.textMuted);

        final lightAccentRich = tester.widget<RichText>(
          find.descendant(
            of: find.byType(TpBrandSubtitle).last,
            matching: find.byType(RichText),
          ),
        );
        expect(
          findResolvedStyle(lightAccentRich.text, '_')?.color,
          TpTokens.techRedLight,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: themeService.darkTheme,
            home: const Scaffold(
              body: Column(
                children: [
                  TpBrandLockup(
                    axis: Axis.vertical,
                    showSubtitle: true,
                  ),
                  TpBrandSubtitle(
                    prefix: 'GeekPie',
                    accentSuffix: '_',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final darkTp = TpColors.fromTheme(themeService.darkTheme);
        final darkWordmarkText = tester.widget<Text>(
          find.descendant(
            of: find.byType(TpBrandWordmark),
            matching: find.byType(Text),
          ),
        );
        expect(darkWordmarkText.style?.color, darkTp.textPrimary);
        expect(darkWordmarkText.style?.color, isNot(TpTokens.iosBlueDark));
        expect(
          darkWordmarkText.style?.fontFamily,
          TpBrandWordmark.brandFontFamily,
        );
        expect(darkWordmarkText.style?.fontWeight, FontWeight.w800);

        final darkDefaultSub = tester.widget<Text>(
          find.descendant(
            of: find.descendant(
              of: find.byType(TpBrandLockup),
              matching: find.byType(TpBrandSubtitle),
            ),
            matching: find.byType(Text),
          ),
        );
        expect(darkDefaultSub.style?.color, darkTp.textMuted);

        final darkAccentRich = tester.widget<RichText>(
          find.descendant(
            of: find.byType(TpBrandSubtitle).last,
            matching: find.byType(RichText),
          ),
        );
        expect(
          findResolvedStyle(darkAccentRich.text, '_')?.color,
          TpTokens.techRedDarkInk,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('TpBrandLockup renders TechPie and quiet ShanghaiTech · GeekPie caption cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TpBrandLockup(),
              TpBrandLockup(
                axis: Axis.vertical,
                showSubtitle: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('TechPie'), findsNWidgets(2));
    expect(find.text('ShanghaiTech · GeekPie'), findsOneWidget);
  });

  testWidgets('PrivacyConsentPage shows flat TechRed badge brand lockup in both full and compact modes', (
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
      final mark = tester.widget<TpBrandMark>(find.byType(TpBrandMark));
      expect(mark.variant, TpBrandMarkVariant.badge);
      expect(find.text('TechPie'), findsOneWidget);
    }
  });

  testWidgets('HomePage shows compact eyebrow brand mark on mobile and omits it inside DesktopShell', (
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
      final avatar = tester.widget<TpAvatarBadge>(
        find.byKey(const ValueKey('home.avatar')),
      );
      expect(avatar.tone, TpAvatarBadgeTone.brandSoft);

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
