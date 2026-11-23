import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/custom_deadline_editor_page.dart';
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
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/adaptive_navigation_scaffold.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';
import 'package:techpie/widgets/swipeable_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/deadline_reminders');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final firstDue = DateTime.utc(2027, 3, 1, 9, 30);
  late StorageService storage;
  late AuthService auth;
  late ThirdPartyAuthService thirdParty;
  late AssignmentService assignments;
  late DeadlineReminderService reminders;
  late List<Map<Object?, Object?>> exported;
  late List<String> removed;
  late Map<String, int> nativeCompletions;
  late Set<String> linkedKeys;
  late List<Map<String, String>> writes;
  late List<Map<String, Map<Object?, Object?>>> edits;
  late Future<void> Function()? beforeWrite;
  late bool denyEdits;
  late DateTime Function() now;
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
    FlutterSecureStorage.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    auth = AuthService(storage, http, uniAuth);
    thirdParty = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, thirdParty);
    now = DateTime.now;
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
    assignments = AssignmentService(
      storage,
      http,
      auth,
      thirdParty,
      schedule,
      syncReminders: true,
      now: () => now(),
    )..loadCached();
    exported = [];
    removed = [];
    nativeCompletions = {};
    linkedKeys = {};
    writes = [];
    edits = [];
    beforeWrite = null;
    denyEdits = false;
    blockedRead = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'linked') {
        return (call.arguments as List<Object?>).where(linkedKeys.contains).toList();
      }
      if (call.method == 'saveSelection') {
        final args = call.arguments as Map<Object?, Object?>;
        exported = (args['add'] as List<Object?>).cast<Map<Object?, Object?>>();
        removed = (args['remove'] as List<Object?>).cast<String>();
        final added = <String>[];
        final existing = <String>[];
        for (final item in exported) {
          final key = item['key'] as String;
          (linkedKeys.add(key) ? added : existing).add(key);
        }
        linkedKeys.removeAll(removed);
        for (final key in removed) {
          nativeCompletions.remove(key);
        }
        return {'added': added, 'existing': existing, 'removed': removed};
      }
      if (call.method == 'change') {
        final changes = (call.arguments as Map).cast<String, String>();
        writes.add(changes);
        await beforeWrite?.call();
        for (final entry in changes.entries) {
          if (!linkedKeys.contains(entry.key)) continue;
          switch (entry.value) {
            case 'complete':
              nativeCompletions[entry.key] = 250;
            case 'reopen':
              nativeCompletions.remove(entry.key);
            case 'remove':
              linkedKeys.remove(entry.key);
              nativeCompletions.remove(entry.key);
          }
        }
        return changes.keys.toList();
      }
      if (call.method == 'edit') {
        final details = (call.arguments as Map).cast<String, Map<Object?, Object?>>();
        edits.add(details);
        if (denyEdits) throw PlatformException(code: 'reminders_denied');
        return details.keys.toList();
      }
      expectSync(call.method, 'completed');
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
        child: MaterialApp(
          builder: (_, child) => AdaptiveFeedbackHost(
            key: adaptiveFeedbackHostKey,
            child: child!,
          ),
          home: const AssignmentsPage(),
        ),
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
    expect(await reminders.add(assignments.assignments), (added: 2, existing: 0, failed: 0));
    final keys = exported.map((item) => item['key']).toList();
    expect(keys.toSet(), hasLength(2));
    expect(exported.first['due'], firstDue.millisecondsSinceEpoch);
    expect(await reminders.add(assignments.assignments), (added: 0, existing: 2, failed: 0));
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
    expect(writes, [{firstKey: 'reopen'}]);
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

  test('writes the latest completion after an in-flight save', () async {
    final first = assignments.assignments.first;
    final second = assignments.assignments.last;
    await reminders.add([first]);
    final key = assignments.reminderKeyFor(first);
    final started = Completer<void>();
    final finishSave = Completer<void>();
    beforeWrite = () {
      beforeWrite = null;
      started.complete();
      return finishSave.future;
    };
    reminders.initialize();
    await assignments.setCompleted(first, true);
    await started.future;
    await assignments.setCompleted(first, false);
    await assignments.setCompleted(second, true);
    finishSave.complete();
    await flush();

    expect(writes, [
      {key: 'complete'},
      {key: 'reopen', assignments.reminderKeyFor(second): 'complete'},
    ]);
    expect(nativeCompletions, isEmpty);
    expect(linkedKeys, {key});
    expect(assignments.isCompleted(first), isFalse);
    expect(assignments.isCompleted(second), isTrue);
    expect(assignments.reminderSyncWork.changes, isEmpty);
  });

  test('retries deleting the last custom deadline in its original workspace', () async {
    await assignments.clearCache();
    await assignments.saveCustomDeadline(
      owner: null,
      title: 'Custom',
      due: firstDue,
    );
    final custom = assignments.assignments.single as CustomDeadline;
    await reminders.add([custom]);
    final key = assignments.reminderKeyFor(custom);
    beforeWrite = () async => throw PlatformException(code: 'reminders_denied');
    reminders.initialize();
    await flush();
    await assignments.deleteCustomDeadline(custom.id, owner: null);
    await flush();
    expect(linkedKeys, {key});
    expect(assignments.assignments, isEmpty);

    reminders.dispose();
    await storage.saveSession(
      UserSession(
        userId: 'account',
        userName: 'Test',
        schoolName: 'Test',
        createdAt: firstDue,
      ),
    );
    await auth.loadSession();
    assignments.loadCached();
    beforeWrite = null;
    reminders.initialize();
    await flush();
    expect(linkedKeys, {key});

    await auth.logout();
    await flush();
    expect(linkedKeys, isEmpty);
    expect(writes, [
      {key: 'remove'},
      {key: 'remove'},
    ]);
    expect(assignments.reminderSyncWork.changes, isEmpty);
  });

  test('retries writing completion after the assignment leaves the list', () async {
    final assignment = assignments.assignments.first;
    final key = assignments.reminderKeyFor(assignment);
    await reminders.add([assignment]);
    await assignments.setCompleted(assignment, true);
    await assignments.clearCache();
    assignments.loadCached();
    reminders.initialize();
    await flush();

    expect(writes, [{key: 'complete'}]);
    expect(nativeCompletions, contains(key));
    expect(assignments.reminderSyncWork.changes, isEmpty);
  });

  test('updates the existing custom reminder after a saved edit and retries after reload', () async {
    await assignments.saveCustomDeadline(
      owner: null,
      title: 'Original',
      due: firstDue,
      location: 'Room 101',
    );
    final custom = assignments.assignments.whereType<CustomDeadline>().single;
    await reminders.add([custom]);
    final key = exported.single['key'];
    expect(exported.single['location'], 'Room 101');
    reminders.initialize();
    await flush();
    denyEdits = true;
    final due = firstDue.add(const Duration(hours: 2));
    await assignments.saveCustomDeadline(
      owner: null,
      id: custom.id,
      title: 'Updated',
      course: 'Physics',
      due: due,
      location: 'Room 202',
      notes: 'Bring lab notes',
    );
    await flush();

    final expected = {
      key: {
        'title': 'Updated',
        'notes': 'Physics\n地点：Room 202\nBring lab notes',
        'location': 'Room 202',
        'due': due.millisecondsSinceEpoch,
      },
    };
    expect(edits, [expected]);
    reminders.dispose();
    denyEdits = false;
    assignments.loadCached();
    reminders.initialize();
    await flush();

    expect(edits, [expected, expected]);
    expect(linkedKeys, {key});
    expect(assignments.findCustomDeadline(custom.id)?.location, 'Room 202');
    expect(assignments.pendingReminderEdits, isEmpty);
  });

  test('restarts a remote reminder removal after the undo window', () async {
    final assignment = assignments.assignments.first;
    await reminders.add([assignment]);
    final key = assignments.reminderKeyFor(assignment);
    var time = firstDue;
    now = () => time;
    await assignments.hide(assignment, reminderUndoWindow: const Duration(seconds: 4));
    expect(assignments.isHidden(assignment), isTrue);
    expect(linkedKeys, {key});
    time = time.add(const Duration(seconds: 5));
    assignments.loadCached();
    reminders.initialize();
    await flush();

    expect(linkedKeys, isEmpty);
    expect(writes, [{key: 'remove'}]);
    expect(storage.loadAssignmentOverrides().reminderRemovals, isEmpty);
  });

  testWidgets(
    'rebinding clears normal selection and rejects the old reset callback',
    (tester) async {
      final assignment = assignments.assignments.first;
      Future<void> bindGradescope(String account) async {
        await thirdParty.replaceAll([
          ThirdPartyAccount(
            platform: ThirdPartyPlatform.gradescope,
            account: account,
            token: 'test-token',
            boundAt: firstDue,
          ),
        ]);
        await storage.saveCachedAssignments([assignment.toJson()]);
        assignments.loadCached();
      }

      IosNativeNavigationBar bar() => tester
          .widget<AdaptiveNavigationScaffold>(find.byType(AdaptiveNavigationScaffold))
          .appBar as IosNativeNavigationBar;

      await bindGradescope('old-account');
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await tester.longPress(find.text(assignment.title));
      await tester.pumpAndSettle();
      final oldBar = bar();
      expect(oldBar.selectionMode, isTrue);

      await bindGradescope('new-account');
      final replacement = assignments.assignments.single;
      final newKey = assignments.reminderKeyFor(replacement);
      await reminders.add([replacement]);
      nativeCompletions[newKey] = 100;
      reminders.initialize();
      await tester.pumpAndSettle();
      expect(bar().selectionMode, isFalse);
      expect(assignments.isCompleted(replacement), isTrue);

      await tester.tap(find.text('已完成 (1)'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text(replacement.title));
      await tester.pumpAndSettle();
      expect(bar().selectionMode, isTrue);

      oldBar.onMenuSelected!('selectionMore', 'resetSelected');
      await tester.pumpAndSettle();
      expect(assignments.isCompleted(replacement), isTrue);
      expect(writes, isEmpty);

      bar().onMenuSelected!('selectionMore', 'resetSelected');
      await tester.pumpAndSettle();
      expect(assignments.isCompleted(replacement), isFalse);
      expect(writes, [{newKey: 'reopen'}]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'removes the reminder only if a swipe is left without undo',
    (tester) async {
      now = tester.binding.clock.now;
      await assignments.saveCustomDeadline(owner: null, title: 'Custom', due: firstDue);
      final custom = assignments.assignments.whereType<CustomDeadline>().single;
      await reminders.add([custom]);
      final key = assignments.reminderKeyFor(custom);
      reminders.initialize();
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      final title = find.text('Custom');
      final card = find.ancestor(of: title, matching: find.byType(SwipeableCard));
      await tester.drag(card, Offset(-tester.getSize(card).width * 0.7, 0));
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(assignments.isHidden(custom), isTrue);
      expect(find.text('撤销'), findsOneWidget);
      expect(linkedKeys, {key});

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      expect(assignments.visibleAssignments, contains(same(custom)));
      await tester.pump(const Duration(seconds: 5));
      expect(linkedKeys, {key});
      expect(writes, isEmpty);
      expect(storage.loadAssignmentOverrides().reminderRemovals, isEmpty);

      await tester.drag(card, Offset(-tester.getSize(card).width * 0.7, 0));
      await tester.pumpAndSettle();
      expect(linkedKeys, {key});
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(linkedKeys, isEmpty);
      expect(writes, [{key: 'remove'}]);
      reminders.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );

  testWidgets(
    'saves and deletes the linked reminder from the custom deadline editor',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await assignments.saveCustomDeadline(
        owner: null,
        title: 'Custom',
        due: firstDue,
        location: 'Room 101',
      );
      final custom = assignments.assignments.whereType<CustomDeadline>().single;
      final key = assignments.reminderKeyFor(custom);
      await reminders.add([custom]);
      reminders.initialize();
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomDeadlineEditorPage), findsOneWidget);
      final location = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == 'Room 101',
      );
      await tester.enterText(location, 'Room 202');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(edits.single[key]?['location'], 'Room 202');

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除此 Deadline？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '删除').last);
      await tester.pumpAndSettle();
      expect(writes, [{key: 'remove'}]);
      expect(linkedKeys, isEmpty);
      expect(find.text('Custom'), findsNothing);
      reminders.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'manages linked reminders and saves removals with no remaining selection',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final firstKey = assignments.reminderKeyFor(assignments.assignments.first);
      final secondKey = assignments.reminderKeyFor(assignments.assignments.last);
      linkedKeys.addAll([firstKey, 'unrelated']);

      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      IosNativeNavigationBar bar() =>
          tester.widget<AdaptiveNavigationScaffold>(find.byType(AdaptiveNavigationScaffold)).appBar
              as IosNativeNavigationBar;

      Future<void> openSelection() async {
        if (isIos) {
          final more = bar().trailingItems.single;
          expect(
            more.menuItems.expand((item) => item.children).map((item) => item.title),
            contains('添加到提醒事项'),
          );
          bar().onMenuSelected!(more.id, 'manageReminders');
        } else {
          await tester.tap(find.byType(PopupMenuButton<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('添加到提醒事项'));
        }
        await tester.pumpAndSettle();
      }

      bool canSave() => isIos
          ? bar().trailingItems.singleWhere((item) => item.id == 'saveReminders').enabled
          : tester.widget<TextButton>(find.widgetWithText(TextButton, '保存')).onPressed != null;

      Future<void> save() async {
        expect(canSave(), isTrue);
        if (isIos) {
          bar().onItemPressed!('saveReminders');
        } else {
          await tester.tap(find.text('保存'));
        }
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await openSelection();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(canSave(), isFalse);
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();
      expect(canSave(), isTrue);
      if (isIos) {
        bar().onItemPressed!('cancelSelection');
      } else {
        await tester.tap(find.byTooltip('退出多选'));
      }
      await tester.pumpAndSettle();
      expect(linkedKeys, {firstKey, 'unrelated'});

      await openSelection();
      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check_circle).first);
      await tester.pumpAndSettle();
      await save();
      expect(exported.map((item) => item['key']), [secondKey]);
      expect(removed, [firstKey]);
      expect(linkedKeys, {secondKey, 'unrelated'});

      await openSelection();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await save();
      expect(exported, isEmpty);
      expect(removed, [secondKey]);
      expect(linkedKeys, {'unrelated'});
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.macOS}),
  );
}
