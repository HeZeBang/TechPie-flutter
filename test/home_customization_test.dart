import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/home_layout.dart';
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
import 'package:techpie/widgets/adaptive_feedback.dart';

void main() {
  Future<void> runWithHomeApp(
    WidgetTester tester, {
    required Size size,
    TargetPlatform? platformOverride,
    bool disableAnimations = false,
    Map<String, Object> extraPrefs = const {},
    required Future<void> Function(StorageService storage) body,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    debugDefaultTargetPlatformOverride = platformOverride;
    if (disableAnimations) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    }

    try {
      SharedPreferences.setMockInitialValues({
        'privacy_accepted_v1': true,
        ...extraPrefs,
      });
      final storage = StorageService(await SharedPreferences.getInstance());
      final logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      try {
        final uniAuth = UniAuthService();
        final auth = AuthService(storage, http, uniAuth);
        final tpAuth = ThirdPartyAuthService(storage, http);
        final schedule = ScheduleService(storage, http, auth, tpAuth);
        final assignments =
            AssignmentService(storage, http, auth, tpAuth, schedule);
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
        await body(storage);
      } finally {
        http.close();
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      if (disableAnimations) {
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  testWidgets(
      'mobile long-press enters edit mode, toggles card style, removes with Undo, opens gallery & empties cleanly',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(390, 844),
      platformOverride: TargetPlatform.iOS,
      body: (storage) async {
        // Default mobile renders compact campus card strip first.
        expect(
          find.byKey(const ValueKey('home.campus-card-mini-thumb')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);

        // Long press on a card enters edit mode without triggering navigation.
        await tester.longPress(find.byKey(const ValueKey('home.today-courses')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home.drag-handle-today_courses')),
          findsOneWidget,
        );

        // Switch mobile campus card from compact strip to full card.
        await tester
            .tap(find.byKey(const ValueKey('home.campus-card-style-full')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home.campus-card-header-band')),
          findsOneWidget,
        );
        expect(
          storage.homeMobileLayout.campusCardStyle,
          HomeCampusCardStyle.full,
        );

        // Drag todayCourses handle upward past campusCard to reorder.
        final handleFinder =
            find.byKey(const ValueKey('home.drag-handle-today_courses'));
        await tester.drag(handleFinder, const Offset(0, -260));
        await tester.pumpAndSettle();
        final coursesTopAfterDrag = tester
            .getTopLeft(find.byKey(const ValueKey('home.today-courses')))
            .dy;
        final cardTopAfterDrag = tester
            .getTopLeft(find.byKey(const ValueKey('home.campus-card-strip')))
            .dy;
        expect(coursesTopAfterDrag, lessThan(cardTopAfterDrag));
        expect(
          storage.homeMobileLayout.order.first,
          HomeWidgetId.todayCourses,
        );

        // Remove deadlines card -> verify Undo feedback restores it cleanly.
        await tester.ensureVisible(
          find.byKey(const ValueKey('home.remove-deadlines')),
        );
        await tester.tap(find.byKey(const ValueKey('home.remove-deadlines')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.deadlines')), findsNothing);
        expect(find.text('撤销'), findsOneWidget);

        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.deadlines')), findsOneWidget);
        adaptiveFeedbackHostKey.currentState?.dismiss();
        await tester.pumpAndSettle();

        // Pinned edit bar stays accessible regardless of scroll offset -> open gallery.
        await tester.tap(find.byKey(const ValueKey('home.open-gallery')));
        await tester.pumpAndSettle();

        await tester
            .tap(find.byKey(const ValueKey('home.gallery-style-compact')));
        await tester.pumpAndSettle();
        expect(
          storage.homeMobileLayout.campusCardStyle,
          HomeCampusCardStyle.compact,
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('home.gallery-remove-quick_actions')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('home.gallery-remove-quick_actions')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home.gallery-add-quick_actions')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('home.gallery-add-quick_actions')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('home.gallery-add-quick_actions')),
        );
        await tester.pumpAndSettle();
        expect(
          storage.homeMobileLayout.contains(HomeWidgetId.quickActions),
          isTrue,
        );

        // Close gallery sheet by tapping the close button.
        await tester.tap(find.byKey(const ValueKey('home.gallery-close')));
        await tester.pumpAndSettle();
        adaptiveFeedbackHostKey.currentState?.dismiss();
        await tester.pumpAndSettle();

        // Remove all remaining widgets to verify clean empty state + one-tap restore.
        for (final id in HomeWidgetId.values) {
          final finder = find.byKey(ValueKey('home.remove-${id.key}'));
          if (finder.evaluate().isNotEmpty) {
            await tester.ensureVisible(finder);
            await tester.tap(finder);
            await tester.pumpAndSettle();
            adaptiveFeedbackHostKey.currentState?.dismiss();
            await tester.pumpAndSettle();
          }
        }
        expect(
          find.byKey(const ValueKey('home.empty-widgets')),
          findsOneWidget,
        );

        await tester.tap(find.text('恢复默认'));
        await tester.pumpAndSettle();
        adaptiveFeedbackHostKey.currentState?.dismiss();
        await tester.pumpAndSettle();
        expect(storage.homeMobileLayout, HomeMobileLayout.defaults());

        // Finish edit mode from pinned edit bar.
        await tester.tap(find.byKey(const ValueKey('home.edit-done')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);
      },
    );
  });

  testWidgets(
      'mobile edit mode settles cleanly under dark mode and disableAnimations',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(390, 844),
      platformOverride: TargetPlatform.android,
      disableAnimations: true,
      extraPrefs: {'app_theme_mode': 'dark'},
      body: (_) async {
        await tester.tap(find.byKey(const ValueKey('home.edit-toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);

        // System back pops edit mode rather than leaving the screen.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);
      },
    );
  });

  testWidgets(
      'desktop Bento supports command palette entry, column swap, drag drop, collapse & Escape',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(1280, 800),
      platformOverride: TargetPlatform.macOS,
      body: (storage) async {
        // Open Command Palette via Meta+K and invoke "定制主页控件".
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).last, '定制');
        await tester.pumpAndSettle();
        await tester.tap(find.text('定制主页控件'));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home.bento-col-primary')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home.bento-col-secondary')),
          findsOneWidget,
        );

        // Swap campusCard from secondary -> primary column via toolbar button.
        await tester
            .tap(find.byKey(const ValueKey('home.swap-column-campus_card')));
        await tester.pumpAndSettle();
        expect(
          storage.homeDesktopLayout.columnOf(HomeWidgetId.campusCard),
          HomeBentoColumn.primary,
        );
        expect(storage.homeMobileLayout, HomeMobileLayout.defaults());

        // Drag quickActions from secondary column into primary drop slot 0,
        // emptying secondary column completely.
        final quickDrag =
            find.byKey(const ValueKey('home.draggable-quick_actions'));
        final primaryTopSlot = find.byKey(const ValueKey('home.drop-primary-0'));
        final startCenter = tester.getCenter(quickDrag);
        final endCenter = tester.getCenter(primaryTopSlot);
        final gesture = await tester.startGesture(startCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(endCenter);
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(storage.homeDesktopLayout.secondary, isEmpty);
        expect(
          storage.homeDesktopLayout.primary.first,
          HomeWidgetId.quickActions,
        );
        expect(
          find.byKey(const ValueKey('home.empty-column-secondary')),
          findsOneWidget,
        );

        // Open Widget Gallery on desktop -> renders centered Dialog, toggles
        // campus card style to compact, and closes cleanly.
        await tester.tap(find.byKey(const ValueKey('home.open-gallery')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        await tester
            .tap(find.byKey(const ValueKey('home.gallery-style-compact')));
        await tester.pumpAndSettle();
        expect(
          storage.homeDesktopLayout.campusCardStyle,
          HomeCampusCardStyle.compact,
        );
        await tester.tap(find.byKey(const ValueKey('home.gallery-close')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);

        // Press Escape to exit edit mode -> single populated column expands cleanly.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);
        expect(
          tester.getSize(find.byKey(const ValueKey('home.today-courses'))).width,
          greaterThan(700),
        );
      },
    );
  });
}
