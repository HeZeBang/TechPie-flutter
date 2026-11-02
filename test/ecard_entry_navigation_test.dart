import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/presentation/app/shell.dart';
import 'package:techpie/features/campus_card/presentation/scanner/scanner_modal.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/feature.dart';
import 'package:techpie/pages/campus_card_page.dart';
import 'package:techpie/pages/home_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/ecard_widget_service.dart';
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
import 'package:techpie/widgets/app_shell/app_shell.dart';
import 'package:techpie/widgets/blurred_app_bar.dart';

/// The eCard home widget asks TechPie for the payment code without a page to
/// push onto: on a cold start the shell does not exist yet, and while the app
/// runs it is the shell — not the feature — that knows where the page belongs.
/// These pin that hand-off: the intent is expressed once, the shell consumes it
/// exactly once, and the page it pushes behaves like any other page of the
/// destination the user is on.
void main() {
  late AppRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtime = await buildDemoRuntime();
    await runtime.auth.signIn(const DemoAuthCredential());
    appShellPendingEcardEntry.value = null;
  });

  tearDown(() async {
    appShellPendingEcardEntry.value = null;
    await runtime.dispose();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    EcardWidgetService? ecardWidgets,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService(prefs);
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final theme = ThemeService(storage);
    final tpAuth = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);

    await tester.pumpWidget(
      TechPieApp(
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
        ecardBindService: EcardBindService(),
        ecardWidgetService: ecardWidgets,
        campusCardService: CampusCardService.withStore(
          InMemorySecureCredentialStore(),
          runtimeFactory: () => runtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'scanner covers the shell while retaining the campus-card scope',
    (tester) async {
      appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;
      await pumpApp(tester);
      final context = tester.element(find.byKey(const Key('payment-code-page')));
      final container = ProviderScope.containerOf(context);
      final theme = Theme.of(context);
      final root = Navigator.of(context, rootNavigator: true);
      final scanner = runtime.scanner as InMemoryScannerPort;

      final closed = openGpScanner(context);
      await tester.pumpAndSettle();
      final scannerContext = tester.element(find.byType(ScannerModal));
      expect(Navigator.of(scannerContext), same(root));
      expect(ProviderScope.containerOf(scannerContext), same(container));
      expect(Theme.of(scannerContext), theme);
      expect(scanner.running, isTrue);
      expect(
        tester.getRect(find.byType(ScannerModal)).contains(
          tester.getCenter(find.byType(CNTabBar)),
        ),
        isTrue,
      );

      tester.widget<ScannerModal>(find.byType(ScannerModal)).onClose();
      await tester.pumpAndSettle();
      await closed;
      expect(scanner.running, isFalse);
      expect(root.canPop(), isFalse);
      expect(find.byType(CNTabBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a campus-card inner sheet activates and releases native modal protection',
    (tester) async {
      appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;
      await pumpApp(tester);
      final context = tester.element(find.byKey(const Key('payment-code-page')));
      final navigator = Navigator.of(context);
      expect(navigator, isNot(same(Navigator.of(context, rootNavigator: true))));
      final depth = CNTabBarRouteObserver.anyModalDepth.value;
      unawaited(
        CNBottomSheet.show<void>(
          context: context,
          useRootNavigator: false,
          builder: (_) => const SizedBox(height: 200),
        ),
      );
      await tester.pumpAndSettle();
      expect(CNTabBarRouteObserver.anyModalDepth.value, depth + 1);
      expect(CNTabBarRouteObserver.topModalRect.value, isNotNull);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(CNTabBarRouteObserver.anyModalDepth.value, depth);
      expect(CNTabBarRouteObserver.topModalRect.value, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a tap that arrives before the shell exists still opens the code',
    (
      tester,
    ) async {
      // The widget was tapped while TechPie was still starting: main can only
      // record the intent, and the shell has to honour it once it mounts.
      appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;

      await pumpApp(tester);

      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
      expect(find.byType(CampusCardPage), findsOneWidget);
      expect(find.byType(CNTabBar), findsOneWidget);
      expect(
        appShellPendingEcardEntry.value,
        isNull,
        reason: 'the intent is consumed once, not replayed on every rebuild',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a tap opens the code over the destination the user is on', (
    tester,
  ) async {
    // The wide window is the case with a stack per destination, and the settings
    // destination is where the widget's page is reachable from.
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.byType(CampusCardPage), findsNothing);

    appShellPendingEcardEntry.value = CampusCardEntry.paymentCode;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
    expect(find.byType(CampusCardPage), findsOneWidget);
    expect(appShellPendingEcardEntry.value, isNull);

    // Inside the shell the page fills its content area, sidebar included: the bar
    // spans the page rather than sitting in the middle of it.
    expect(
      tester.getSize(find.byType(BlurredAppBar)).width,
      tester.getSize(find.byKey(const Key('payment-code-page'))).width,
    );

    // It went onto the destination the user was on, so one back leaves the
    // feature instead of the app, and lands back where they were.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CampusCardPage), findsNothing);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets(
    'campus-card feature stays in its tab when switching away and back',
    (tester) async {
      await pumpApp(tester);
      featureEntries.singleWhere((feature) => feature.id == 'campus_card').nativeEntry!(
        tester.element(find.byType(HomePage)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
      expect(find.byType(CNTabBar), findsOneWidget);

      tester.widget<CNTabBar>(find.byType(CNTabBar)).onTap(3);
      await tester.pumpAndSettle();
      expect(find.byType(CampusCardPage), findsNothing);
      tester.widget<CNTabBar>(find.byType(CNTabBar)).onTap(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CampusCardPage), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'widget entry reveals code through tabs, scanner and root pages',
    (tester) async {
      const channel = MethodChannel('test/ecard_widget_tab_entry');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final nativeCalls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = EcardWidgetService(channel: channel);
      addTearDown(service.dispose);
      service.initialize();
      Future<void> openPayCode() async {
        final delivered = messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('openPayCode'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        await delivered;
      }

      await pumpApp(tester, ecardWidgets: service);
      featureEntries
          .singleWhere((feature) => feature.id == 'campus_card')
          .nativeEntry!(tester.element(find.byType(HomePage)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment-code-page')), findsOneWidget);
      tester.widget<CNTabBar>(find.byType(CNTabBar)).onTap(3);
      await tester.pumpAndSettle();
      expect(find.byType(CampusCardPage), findsNothing);
      await openPayCode();
      expect(nativeCalls, contains('acknowledgePendingRoute'));
      expect(
        find.byKey(const Key('payment-code-page')),
        findsOneWidget,
        reason:
            'A widget/shortcut entry must show the payment code, not only acknowledge a hidden route.',
      );
      final context = tester.element(
        find.byKey(const Key('payment-code-page')),
      );
      final scanner = runtime.scanner as InMemoryScannerPort;
      final scannerClosed = openGpScanner(context);
      await tester.pumpAndSettle();
      expect(scanner.running, isTrue);
      await openPayCode();
      expect(
        find.byType(ScannerModal),
        findsNothing,
        reason: 'The payment entry must dismiss the scanner covering the code.',
      );
      expect(scanner.running, isFalse);
      await scannerClosed;
      final root = Navigator.of(context, rootNavigator: true);
      final rootPage = root.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('root-entry-page')),
        ),
      );
      await tester.pumpAndSettle();
      await openPayCode();
      expect(
        find.byKey(const Key('payment-code-page')),
        findsOneWidget,
        reason:
            'The entry must show the code above a root page, not behind it.',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('root-entry-page'), findsOneWidget);
      root.pop();
      await tester.pumpAndSettle();
      await rootPage;
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
