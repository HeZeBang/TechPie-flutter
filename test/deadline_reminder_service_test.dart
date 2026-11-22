import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/deadline_reminder_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/adaptive_navigation_scaffold.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/deadline_reminders');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final firstDue = DateTime.utc(2027, 3, 1, 9, 30);
  late StorageService storage;
  late AssignmentService assignments;
  late DeadlineReminderService reminders;
  late List<Map<Object?, Object?>> exported;
  late Map<String, int> nativeCompletions;
  late Completer<Map<String, int>>? blockedRead;
  late Widget Function() buildPage;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Future<void> notifyRemindersChanged() => messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('remindersChanged')),
        (_) {},
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = AuthService(storage, http, uniAuth);
    final thirdParty = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, thirdParty);
    await storage.saveCachedAssignments([
      for (final (index, platform) in ['gradescope', 'blackboard'].indexed)
        Assignment(
          id: 'same-id',
          platform: platform,
          title: 'Two DDLs with the same title',
          course: 'Course',
          due: firstDue.add(Duration(days: index)),
          lateDue: firstDue.add(const Duration(days: 2)),
        ).toJson(),
    ]);
    assignments = AssignmentService(storage, http, auth, thirdParty, schedule)..loadCached();
    exported = [];
    nativeCompletions = {};
    blockedRead = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'add') {
        exported = (call.arguments as List).cast<Map<Object?, Object?>>();
        return {'added': 1, 'existing': 1, 'failed': 0};
      }
      expect(call.method, 'completed');
      return blockedRead?.future ?? nativeCompletions;
    });
    reminders = DeadlineReminderService(assignments, channel: channel);
    buildPage = () {
      final campusCard = CampusCardService();
      addTearDown(campusCard.dispose);
      return ServiceProvider(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: thirdParty,
        oaGymService: OaGymService(auth, storage, thirdParty),
        egateAppService: EgateAppService(auth, storage, thirdParty),
        uniAuthService: uniAuth,
        syncService: SyncService(auth, thirdParty, storage),
        updateService: UpdateService(),
        campusCardService: campusCard,
        ecardBindService: EcardBindService(),
        deadlineReminderService: reminders,
        child: const MaterialApp(home: AssignmentsPage()),
      );
    };
    addTearDown(() {
      reminders.dispose();
      assignments.dispose();
      schedule.dispose();
      thirdParty.dispose();
      auth.dispose();
      http.close();
      messenger.setMockMethodCallHandler(channel, null);
    });
  });

  test('exports a single batch with distinct stable keys and original due times', () async {
    expect(await reminders.add(assignments.assignments), (added: 1, existing: 1, failed: 0));
    final keys = exported.map((item) => item['key']).toList();
    expect(keys.toSet(), hasLength(2));
    expect(exported.first['due'], firstDue.millisecondsSinceEpoch);
    await reminders.add(assignments.assignments);
    expect(exported.map((item) => item['key']), keys);
  });

  test('records completion once, including after restoring local overrides', () async {
    await reminders.add(assignments.assignments);
    final firstKey = exported.first['key'] as String;
    final secondKey = exported.last['key'] as String;
    reminders.initialize();
    await flush();

    nativeCompletions = {firstKey: 100, 'unrelated': 100};
    await notifyRemindersChanged();
    expect(assignments.assignments.map(assignments.isCompleted), [true, false]);
    await assignments.setCompleted(assignments.assignments.first, false);
    expect(storage.loadAssignmentOverrides().reminderCompletions, {firstKey: 100});
    assignments.loadCached();
    await flush();

    nativeCompletions = {firstKey: 100, secondKey: 200};
    reminders.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush();
    expect(assignments.assignments.map(assignments.isCompleted), [false, true]);

    nativeCompletions[firstKey] = 300;
    await notifyRemindersChanged();
    expect(assignments.assignments.map(assignments.isCompleted), [true, true]);
  });

  test('discards a pending completion after the assignment identity resets', () async {
    await reminders.add(assignments.assignments);
    final key = exported.first['key'] as String;
    blockedRead = Completer<Map<String, int>>();
    reminders.initialize();
    await assignments.clearCache();
    blockedRead!.complete({key: 100});
    await flush();

    expect(storage.loadAssignmentOverrides().completed, isEmpty);
    expect(storage.loadAssignmentOverrides().reminderCompletions, isEmpty);
  });

  testWidgets(
    'adds selected deadlines from the overflow menu on both Apple platforms',
    (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        IosNativeNavigationBar bar() => tester
            .widget<AdaptiveNavigationScaffold>(
              find.byType(AdaptiveNavigationScaffold),
            )
            .appBar as IosNativeNavigationBar;
        final more = bar().trailingItems.single;
        expect(
          more.menuItems.expand((item) => item.children).map((item) => item.title),
          contains('添加到提醒事项'),
        );
        bar().onMenuSelected!(more.id, 'addReminders');
        await tester.pumpAndSettle();
        bar().onItemPressed!('toggleSelectAll');
        await tester.pumpAndSettle();
        bar().onItemPressed!('confirmAddReminders');
      } else {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('添加到提醒事项'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('全选'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('添加'));
      }
      await tester.pumpAndSettle();
      expect(exported, hasLength(2));
      expect(find.text('已选择 2 个'), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );
}
