import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/assignment_overrides.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/assignments_page.dart';
import 'package:techpie/pages/deadline_editor_page.dart';
import 'package:techpie/pages/hidden_assignments_page.dart';
import 'package:techpie/pages/home_page.dart';
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
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/adaptive_navigation_scaffold.dart';
import 'package:techpie/widgets/design_system/design_system.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';
import 'package:techpie/widgets/schedule_picker_sheet.dart';
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
  late Completer<Map<String, int?>>? blockedRead;
  late Widget Function({Widget home}) buildPage;

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
      expectSync(call.method, 'completionStates');
      return blockedRead?.future ?? {
        for (final key in linkedKeys) key: nativeCompletions[key],
        ...nativeCompletions,
      };
    });
    reminders = DeadlineReminderService(assignments, channel: channel);
    buildPage = ({Widget home = const AssignmentsPage()}) {
      final campusCard = CampusCardService();
      final studentAllowance = StudentAllowanceService(auth, thirdParty);
      addTearDown(campusCard.dispose);
      addTearDown(studentAllowance.dispose);
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
        studentAllowanceService: studentAllowance,
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
          home: home,
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

  test('reopens linked course and custom deadlines after reloading', () async {
    await assignments.saveCustomDeadline(owner: null, title: 'Custom', due: firstDue);
    final course = assignments.assignments.firstWhere((a) => a is! CustomDeadline);
    final custom = assignments.assignments.whereType<CustomDeadline>().single;
    final courseKey = assignments.reminderKeyFor(course);
    final customKey = assignments.reminderKeyFor(custom);
    await reminders.add([course, custom]);
    nativeCompletions = {courseKey: 100, customKey: 200};
    reminders.initialize();
    await flush();
    expect(assignments.isCompleted(course), isTrue);
    expect(assignments.findCustomDeadline(custom.id)?.completed, isTrue);

    reminders.dispose();
    nativeCompletions.clear();
    assignments.loadCached();
    reminders.initialize();
    await flush();
    expect(assignments.isCompleted(course), isFalse);
    expect(assignments.findCustomDeadline(custom.id)?.completed, isFalse);
    expect(
      storage.loadAssignmentOverrides().scopedCompleted,
      isNot(contains(courseKey)),
    );
    expect(storage.loadCustomDeadlines(null)?.deadlines[custom.id]?.completed, isFalse);
    expect(writes, isEmpty);

    nativeCompletions = {courseKey: 300, customKey: 400};
    await notifyRemindersChanged();
    expect(assignments.isCompleted(course), isTrue);
    expect(assignments.findCustomDeadline(custom.id)?.completed, isTrue);
  });

  test('keeps a reopened reminder open when its course platform shows submitted', () async {
    final submitted = Assignment(
      id: 'submitted',
      platform: 'blackboard',
      title: 'Submitted homework',
      course: 'Course',
      due: firstDue,
      status: 'Submitted',
    );
    await storage.saveCachedAssignments([submitted.toJson()]);
    assignments.loadCached();
    final assignment = assignments.assignments.single;
    await reminders.add([assignment]);
    final key = assignments.reminderKeyFor(assignment);
    nativeCompletions[key] = 100;
    reminders.initialize();
    await flush();
    expect(assignments.isCompleted(assignment), isTrue);

    nativeCompletions.remove(key);
    await notifyRemindersChanged();
    expect(assignments.isCompleted(assignment), isFalse);
    expect(storage.loadAssignmentOverrides().scopedCompleted[key], isFalse);
    expect(writes, isEmpty);
  });

  testWidgets(
    'shows the pencil only when the local status differs from the course platform',
    (tester) async {
      final [open, completed] = assignments.assignments;
      await storage.saveAssignmentOverrides(
        AssignmentOverrides(
          scopedCompleted: {
            assignments.reminderKeyFor(open): false,
            assignments.reminderKeyFor(completed): true,
          },
        ),
      );
      assignments.loadCached();

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text(open.title), findsOneWidget);
      expect(find.byTooltip('本地标记'), findsNothing);

      await tester.tap(find.text('已完成 (1)'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('本地标记'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  test('deleting reminders leaves their TechPie deadlines and completion intact', () async {
    await assignments.saveCustomDeadline(owner: null, title: 'Custom', due: firstDue);
    final course = assignments.assignments.firstWhere((a) => a is! CustomDeadline);
    final custom = assignments.assignments.whereType<CustomDeadline>().single;
    final open = assignments.assignments.last;
    final courseKey = assignments.reminderKeyFor(course);
    final customKey = assignments.reminderKeyFor(custom);
    await reminders.add(assignments.assignments);
    nativeCompletions = {courseKey: 100, customKey: 200};
    reminders.initialize();
    await flush();

    linkedKeys.clear();
    nativeCompletions.clear();
    await notifyRemindersChanged();
    assignments.loadCached();
    await flush();
    final expectedKeys = {courseKey, customKey, assignments.reminderKeyFor(open)};
    expect(assignments.visibleAssignments.map(assignments.reminderKeyFor).toSet(), expectedKeys);
    expect(assignments.isCompleted(course), isTrue);
    expect(assignments.findCustomDeadline(custom.id)?.completed, isTrue);
    expect(assignments.isCompleted(open), isFalse);
    expect(writes, isEmpty);
    expect(
      await reminders.linkedKeys(expectedKeys, epoch: assignments.identityEpoch),
      isEmpty,
    );
  });

  test('discards a pending completion after the assignment identity resets', () async {
    await reminders.add(assignments.assignments);
    final key = exported.first['key'] as String;
    blockedRead = Completer<Map<String, int?>>();
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

  test('syncs imported deadline edits and restoration to the existing reminder', () async {
    final imported = assignments.assignments.firstWhere((item) => item.platform == 'blackboard');
    final key = assignments.reminderKeyFor(imported);
    await reminders.add([imported]);
    reminders.initialize();
    await flush();
    denyEdits = true;
    final due = imported.due.add(const Duration(hours: 1));
    await assignments.saveImportedDeadlineEdit(
      imported,
      epoch: assignments.identityEpoch,
      title: 'Edited deadline',
      notes: 'Bring notes',
      due: due,
    );
    await flush();
    expect(assignments.pendingReminderEdits.keys, [key]);

    reminders.dispose();
    denyEdits = false;
    assignments.loadCached();
    reminders.initialize();
    await flush();
    expect(edits.last[key], {
      'title': 'Edited deadline',
      'notes': 'Course\nBring notes',
      'due': due.millisecondsSinceEpoch,
    });
    expect(assignments.pendingReminderEdits, isEmpty);

    await assignments.restoreImportedDeadline(imported, epoch: assignments.identityEpoch);
    await flush();
    expect(edits.last[key], {
      'title': imported.title,
      'notes': imported.course,
      'due': imported.due.millisecondsSinceEpoch,
    });
    expect(linkedKeys, {key});
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
      expect(find.byType(DeadlineEditorPage), findsNothing);
      final editAction = find.descendant(
        of: find.ancestor(of: find.text('Custom'), matching: find.byType(SwipeableCard)),
        matching: find.byTooltip('编辑 Deadline'),
      );
      await tester.tap(editAction);
      await tester.pumpAndSettle();
      expect(find.byType(DeadlineEditorPage), findsOneWidget);
      final location = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == 'Room 101',
      );
      await tester.enterText(location, 'Room 202');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(edits.single[key]?['location'], 'Room 202');

      await tester.tap(editAction);
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
    'edits imported deadlines in the list and displays the changes on Home',
    (tester) async {
      final desktop = defaultTargetPlatform == TargetPlatform.macOS;
      tester.view.physicalSize = Size(desktop ? 1100 : 400, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = assignments.assignments.first;
      final action = find.byTooltip(desktop ? '编辑 Deadline' : 'Deadline 操作');

      Future<void> openEditor(Finder button) async {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        if (!desktop) {
          await tester.tap(find.text('编辑'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(DeadlineEditorPage), findsOneWidget);
      }

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await openEditor(action.first);
      expect(find.text('迟交截止时间'), findsOneWidget);
      final title = find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.controller.text == original.title,
      );
      await tester.enterText(title, 'Edited deadline');
      final localDue = original.due.toLocal();
      final editedDue = DateTime(
        localDue.year,
        localDue.month,
        localDue.day,
        localDue.hour,
        (localDue.minute + 13) % 60,
      );
      await tester.tap(find.text('截止时间'));
      await tester.pumpAndSettle();
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(editedDue);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        tester.widget<IosSheetHeader>(find.byType(IosSheetHeader)).onConfirm!();
      } else {
        await tester.tap(find.text('确定'));
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('Edited deadline'), findsOneWidget);
      expect(assignments.findImportedDeadline(original)?.due, editedDue);

      await tester.pumpWidget(buildPage(home: const HomePage()));
      await tester.pumpAndSettle();
      expect(find.text('Edited deadline'), findsOneWidget);
      expect(find.byType(DeadlineEditButton), findsNothing);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      final editedRow = find.ancestor(
        of: find.text('Edited deadline'),
        matching: find.byType(SwipeableCard),
      );
      final editAction = find.descendant(of: editedRow, matching: action);
      if (!desktop) {
        final progressBar = find.descendant(of: editedRow, matching: find.byType(TpProgressBar));
        expect(tester.getTopRight(editAction).dx, greaterThan(tester.getTopRight(progressBar).dx));
      }
      await openEditor(editAction);
      await tester.ensureVisible(find.text('恢复来源信息'));
      await tester.tap(find.text('恢复来源信息'));
      await tester.pumpAndSettle();
      expect(assignments.findImportedDeadline(original)?.title, original.title);
      expect(assignments.findImportedDeadline(original)?.due, original.due);
    },
    variant: const TargetPlatformVariant(
      {TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.macOS},
    ),
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
          await tester.tap(find.byTooltip('更多操作'));
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

  testWidgets(
    'iOS swipe-to-restore removes dismissed rows synchronously and formats custom subtitles',
    (tester) async {
      await assignments.saveCustomDeadline(
        owner: null,
        title: 'Custom hidden',
        course: 'Physics',
        location: 'Room 101',
        due: firstDue,
      );
      final custom = assignments.assignments.whereType<CustomDeadline>().single;
      final remote = assignments.assignments.firstWhere((a) => a is! CustomDeadline);
      await assignments.hide(custom);
      await assignments.hide(remote);

      await tester.pumpWidget(buildPage(home: const HiddenAssignmentsPage()));
      await tester.pumpAndSettle();
      expect(find.text('自定义 · Physics · Room 101'), findsOneWidget);
      expect(find.textContaining('CUSTOM'), findsNothing);

      final firstRow = find.byType(Dismissible).first;
      await tester.drag(firstRow, Offset(-tester.getSize(firstRow).width * 0.7, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Dismissible), findsOneWidget);
      await tester.pumpAndSettle();

      final secondRow = find.byType(Dismissible);
      await tester.drag(secondRow, Offset(-tester.getSize(secondRow).width * 0.7, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(assignments.overrides.hidden, isEmpty);
      expect(find.text('没有被忽略的事项'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'completed remote assignments show Submitted while custom deadlines show details without it',
    (tester) async {
      tester.view.physicalSize = const Size(800, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await storage.saveCachedAssignments([
        Assignment(
          id: 'gs-1',
          platform: 'gradescope',
          title: 'Homework 1',
          course: 'CS101',
          due: firstDue,
          status: 'No Submission',
        ).toJson(),
      ]);
      assignments.loadCached();
      await assignments.saveCustomDeadline(
        owner: null,
        title: 'Lab report',
        course: 'Physics',
        location: 'Room 202',
        notes: 'Bring printed copy',
        due: firstDue.add(const Duration(hours: 2)),
      );
      for (final item in assignments.assignments) {
        await assignments.setCompleted(item, true);
      }

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('已完成 (2)'));
      await tester.pumpAndSettle();

      expect(find.text('No Submission'), findsNothing);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Physics · Room 202'), findsOneWidget);
      expect(find.text('Bring printed copy'), findsOneWidget);
    },
  );
}
