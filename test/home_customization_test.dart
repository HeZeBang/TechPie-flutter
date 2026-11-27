import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/home_layout.dart';
import 'package:techpie/pages/campus_services_page.dart';
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
    const feedbackChannel = MethodChannel('techpie/feedback');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(feedbackChannel, (_) async => null);

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
      messenger.setMockMethodCallHandler(feedbackChannel, null);
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

  testWidgets(
      'desktop hides hover edit pill and supports direct hold-drag outside Edit Mode including waking empty column',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(1280, 800),
      platformOverride: TargetPlatform.macOS,
      body: (storage) async {
        // Hovering cards must not show an obtrusive "编辑" corner badge.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('home.today-courses'))),
        );
        await tester.pumpAndSettle();
        expect(find.text('编辑'), findsNothing);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('home.campus-card-strip'))),
        );
        await tester.pumpAndSettle();
        expect(find.text('编辑'), findsNothing);

        // Press and hold quickActions outside Edit Mode (past 260ms delay):
        // lifts a translucent scaled copy of the real card AND auto-enters Edit
        // Mode so card-level style/settings controls become discoverable.
        final quickDrag =
            find.byKey(const ValueKey('home.draggable-quick_actions'));
        final gesture = await tester.startGesture(tester.getCenter(quickDrag));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 160));

        final dragFeedback =
            find.byKey(const ValueKey('home.drag-feedback-quick_actions'));
        expect(dragFeedback, findsOneWidget);
        expect(
          find.descendant(
            of: dragFeedback,
            matching: find.byKey(const ValueKey('home.quick-actions')),
          ),
          findsOneWidget,
        );
        final feedbackOpacity = tester.widget<Opacity>(
          find.descendant(
            of: dragFeedback,
            matching: find.byType(Opacity),
          ).first,
        );
        expect(feedbackOpacity.opacity, closeTo(0.58, 0.01));
        final feedbackScale = tester.widget<Transform>(
          find.descendant(
            of: dragFeedback,
            matching: find.byWidgetPredicate(
              (w) => w is Transform && w.transform.storage[0] != 1.0,
            ),
          ),
        );
        expect(feedbackScale.transform.storage[0], closeTo(0.86, 0.01));
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('home.campus-card-style-compact')),
          findsOneWidget,
        );

        // Hovering upper half of todayCourses highlights home.drop-primary-0 and
        // dropping commits quickActions into slot 0 via smart snap.
        final todayCoursesSnapTop =
            find.byKey(const ValueKey('home.snap-today_courses-top'));
        expect(todayCoursesSnapTop, findsOneWidget);
        await gesture.moveTo(tester.getCenter(todayCoursesSnapTop));
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('home.drop-primary-0')),
            matching: find.text('放置「快捷入口」到此处'),
          ),
          findsOneWidget,
        );
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          storage.homeDesktopLayout.primary.first,
          HomeWidgetId.quickActions,
        );
        expect(
          find.byKey(const ValueKey('home.drag-feedback-quick_actions')),
          findsNothing,
        );
        // Remains in Edit Mode after pick-up drop until Done / Escape.
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);

        // Tapping "定制" on Quick Actions opens HomeShortcutEditorPage directly
        // rather than routing through CampusServicesPage.
        await tester.tap(
          find.byKey(const ValueKey('home.configure-quick-actions')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HomeShortcutEditorPage), findsOneWidget);
        expect(find.byType(CampusServicesPage), findsNothing);
        await tester.tap(find.byTooltip('取消'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeShortcutEditorPage), findsNothing);
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);

        // Inside Edit Mode, immediately drag campusCard (0ms delay) into primary,
        // emptying secondary column.
        final campusDrag =
            find.byKey(const ValueKey('home.draggable-campus_card'));
        final g2 = await tester.startGesture(tester.getCenter(campusDrag));
        await tester.pump(const Duration(milliseconds: 50));
        final slotAfterQuick = find.byKey(const ValueKey('home.drop-primary-1'));
        await g2.moveTo(tester.getCenter(slotAfterQuick));
        await tester.pump(const Duration(milliseconds: 100));
        await g2.up();
        await tester.pumpAndSettle();

        expect(storage.homeDesktopLayout.secondary, isEmpty);

        // Exit Edit Mode via Escape -> empty secondary column collapses cleanly.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);
        expect(
          find.byKey(const ValueKey('home.bento-col-secondary')),
          findsNothing,
        );

        // Hold-dragging a card from collapsed single-column primary auto-enters
        // Edit Mode and wakes up the empty secondary drop zone mid-drag.
        final g3 = await tester.startGesture(
          tester.getCenter(
            find.byKey(const ValueKey('home.draggable-quick_actions')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);
        final wokenSecondary =
            find.byKey(const ValueKey('home.empty-column-secondary'));
        expect(wokenSecondary, findsOneWidget);
        await g3.moveTo(tester.getCenter(wokenSecondary));
        await tester.pump(const Duration(milliseconds: 100));
        await g3.up();
        await tester.pumpAndSettle();

        expect(
          storage.homeDesktopLayout.secondary,
          [HomeWidgetId.quickActions],
        );
        expect(
          find.byKey(const ValueKey('home.bento-col-secondary')),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets(
      'mobile hold shows perimeter charging halo on non-campus cards and cancels cleanly on scroll',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(390, 844),
      platformOverride: TargetPlatform.iOS,
      body: (_) async {
        final coursesCard = find.byKey(const ValueKey('home.today-courses'));
        final gesture = await tester.startGesture(tester.getCenter(coursesCard));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 150));

        // Anticipation focus halo renders past 120ms without entering edit mode yet.
        expect(
          find.byKey(const ValueKey('home.hold-halo-today_courses')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);

        // Moving finger to scroll cancels hold affordance cleanly.
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('home.hold-halo-today_courses')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);
      },
    );
  });

  testWidgets(
      'mobile immediate swipe scrolls cleanly without triggering reorder or Edit Mode',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(390, 600),
      platformOverride: TargetPlatform.iOS,
      body: (storage) async {
        final scrollableFinder = find.descendant(
          of: find.byKey(const ValueKey('home.scroll-body')),
          matching: find.byType(Scrollable),
        );
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        expect(scrollableState.position.pixels, 0);

        await tester.drag(
          find.byKey(const ValueKey('home.today-courses')),
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();

        expect(scrollableState.position.pixels, greaterThan(0));
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);
        expect(
          find.byKey(const ValueKey('home.mobile-drag-proxy-today_courses')),
          findsNothing,
        );
        expect(storage.homeMobileLayout.order, HomeMobileLayout.defaultOrder);
      },
    );
  });

  testWidgets(
      'mobile press-and-hold outside Edit Mode lifts and reorders tall/short cards cleanly then enters Edit Mode',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(390, 844),
      platformOverride: TargetPlatform.iOS,
      body: (storage) async {
        final coursesRect =
            tester.getRect(find.byKey(const ValueKey('home.today-courses')));
        final campusRect = tester
            .getRect(find.byKey(const ValueKey('home.campus-card-strip')));
        final coursesCenter = coursesRect.center;
        // Overshoot past the top of short compact campusCard (~75px) to verify
        // monotonic slot selection never snaps back like SliverReorderableList.
        final targetPointerY = campusRect.top - 24;

        final gesture = await tester.startGesture(coursesCenter);
        await tester.pump(const Duration(milliseconds: 420));

        // Card lifts past hold delay without shifting the list into Edit Mode mid-drag.
        expect(
          find.byKey(const ValueKey('home.mobile-drag-proxy-today_courses')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);

        final totalDeltaY = targetPointerY - coursesCenter.dy;
        for (var step = 1; step <= 12; step++) {
          await gesture.moveTo(
            Offset(
              coursesCenter.dx,
              coursesCenter.dy + totalDeltaY * (step / 12),
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }

        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          storage.homeMobileLayout.order.first,
          HomeWidgetId.todayCourses,
        );
        final coursesTop =
            tester.getTopLeft(find.byKey(const ValueKey('home.today-courses'))).dy;
        final cardTop = tester
            .getTopLeft(find.byKey(const ValueKey('home.campus-card-strip')))
            .dy;
        expect(coursesTop, lessThan(cardTop));
        expect(
          find.byKey(const ValueKey('home.mobile-drag-proxy-today_courses')),
          findsNothing,
        );
        // Settling the continuous drag automatically enters Edit Mode for fine-tuning.
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);

        // Drag short campusCard (index 1) UP past taller todayCourses (index 0)
        // in Edit Mode, then drag it right back DOWN past todayCourses.
        final coursesItemRect = tester
            .getRect(find.byKey(const ValueKey('home.mobile-item-today_courses')));
        final campusItemCenter = tester
            .getCenter(find.byKey(const ValueKey('home.campus-card-strip')));
        final gUp = await tester.startGesture(campusItemCenter);
        await tester.pump(const Duration(milliseconds: 260));
        expect(
          find.byKey(const ValueKey('home.mobile-drag-proxy-campus_card')),
          findsOneWidget,
        );
        final upDelta = (coursesItemRect.top + 24) - campusItemCenter.dy;
        for (var step = 1; step <= 12; step++) {
          await gUp.moveTo(
            Offset(
              campusItemCenter.dx,
              campusItemCenter.dy + upDelta * (step / 12),
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await gUp.up();
        await tester.pumpAndSettle();
        expect(
          storage.homeMobileLayout.order.first,
          HomeWidgetId.campusCard,
        );
        expect(storage.homeMobileLayout.order[1], HomeWidgetId.todayCourses);

        // Now drag short campusCard (index 0) DOWN past taller todayCourses (index 1).
        final campusCenterAfterUp = tester
            .getCenter(find.byKey(const ValueKey('home.campus-card-strip')));
        final coursesBottom = tester
            .getRect(find.byKey(const ValueKey('home.mobile-item-today_courses')))
            .bottom;
        final gDown = await tester.startGesture(campusCenterAfterUp);
        await tester.pump(const Duration(milliseconds: 260));
        expect(
          find.byKey(const ValueKey('home.mobile-drag-proxy-campus_card')),
          findsOneWidget,
        );
        final downDelta = (coursesBottom - 16) - campusCenterAfterUp.dy;
        for (var step = 1; step <= 12; step++) {
          await gDown.moveTo(
            Offset(
              campusCenterAfterUp.dx,
              campusCenterAfterUp.dy + downDelta * (step / 12),
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await gDown.up();
        await tester.pumpAndSettle();
        expect(
          storage.homeMobileLayout.order.first,
          HomeWidgetId.todayCourses,
        );
        expect(storage.homeMobileLayout.order[1], HomeWidgetId.campusCard);
      },
    );
  });

  testWidgets(
      'mobile Edit Mode hides duplicate confirm/reset buttons at 320px and supports card-body hold-drag vs immediate scroll',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(320, 600),
      platformOverride: TargetPlatform.iOS,
      body: (storage) async {
        await tester.tap(find.byKey(const ValueKey('home.edit-toggle')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);
        expect(find.byKey(const ValueKey('home.edit-done')), findsOneWidget);
        expect(find.byKey(const ValueKey('home.edit-toggle')), findsNothing);
        expect(find.byKey(const ValueKey('home.avatar')), findsNothing);
        expect(find.byKey(const ValueKey('home.reset-layout')), findsNothing);

        final scrollableFinder = find.descendant(
          of: find.byKey(const ValueKey('home.scroll-body')),
          matching: find.byType(Scrollable),
        );
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);

        // Immediate swipe across a card body scrolls cleanly inside Edit Mode.
        await tester.drag(
          find.byKey(const ValueKey('home.mobile-item-today_courses')),
          const Offset(0, -140),
        );
        await tester.pumpAndSettle();
        expect(scrollableState.position.pixels, greaterThan(0));
        expect(storage.homeMobileLayout.order, HomeMobileLayout.defaultOrder);

        // Scroll back to top before testing hold-drag on the card body.
        await tester.drag(
          find.byKey(const ValueKey('home.mobile-item-today_courses')),
          const Offset(0, 140),
        );
        await tester.pumpAndSettle();

        final coursesRectC =
            tester.getRect(find.byKey(const ValueKey('home.today-courses')));
        final campusRectC = tester
            .getRect(find.byKey(const ValueKey('home.campus-card-strip')));
        final coursesCenter = coursesRectC.center;
        final targetY = campusRectC.top - 24;

        final gesture = await tester.startGesture(coursesCenter);
        await tester.pump(const Duration(milliseconds: 280));
        expect(
          find.byKey(const ValueKey('home.mobile-drag-proxy-today_courses')),
          findsOneWidget,
        );

        final totalDeltaY = targetY - coursesCenter.dy;
        for (var step = 1; step <= 12; step++) {
          await gesture.moveTo(
            Offset(
              coursesCenter.dx,
              coursesCenter.dy + totalDeltaY * (step / 12),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }

        await gesture.up();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          storage.homeMobileLayout.order.first,
          HomeWidgetId.todayCourses,
        );
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);
      },
    );
  });

  testWidgets(
      'mobile single-widget edge case enters Edit Mode cleanly and quick tap leaves no pending timers',
      (tester) async {
    await runWithHomeApp(
      tester,
      size: const Size(390, 844),
      platformOverride: TargetPlatform.iOS,
      body: (storage) async {
        await tester.tap(find.byKey(const ValueKey('home.edit-toggle')));
        await tester.pumpAndSettle();

        for (final id in [
          HomeWidgetId.campusCard,
          HomeWidgetId.deadlines,
          HomeWidgetId.quickActions,
        ]) {
          final finder = find.byKey(ValueKey('home.remove-${id.key}'));
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
          adaptiveFeedbackHostKey.currentState?.dismiss();
          await tester.pumpAndSettle();
        }
        expect(storage.homeMobileLayout.order, [HomeWidgetId.todayCourses]);

        await tester.tap(find.byKey(const ValueKey('home.edit-done')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsNothing);

        await tester.longPress(find.byKey(const ValueKey('home.today-courses')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home.edit-bar')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('home.edit-done')));
        await tester.pump();
      },
    );
  });
}
