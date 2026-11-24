import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/island_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/island');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late DateTime now;
  late StorageService storage;
  late LoggingHttpClient http;
  late UniAuthService uniAuth;
  late AuthService auth;
  late ThirdPartyAuthService thirdParty;
  late ScheduleService schedule;
  late AssignmentService assignments;
  late IslandService island;
  late List<MethodCall> calls;

  Map<String, dynamic> lastPushedFrame() {
    final call = calls.lastWhere((c) => c.method == 'updateFrame');
    final args = call.arguments as Map<Object?, Object?>;
    return jsonDecode(args['frame'] as String) as Map<String, dynamic>;
  }

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    now = DateTime(2026, 11, 20, 9, 0);
    SharedPreferences.setMockInitialValues({'island_enabled': true});
    FlutterSecureStorage.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    http = LoggingHttpClient(DebugLogger());
    uniAuth = UniAuthService();
    auth = AuthService(storage, http, uniAuth);
    thirdParty = ThirdPartyAuthService(storage, http);
    schedule = ScheduleService(storage, http, auth, thirdParty);
    assignments = AssignmentService(storage, http, auth, thirdParty, schedule)
      ..loadCached();
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'probe') {
        return {
          'backend': 'hyper_island',
          'postNotifications': true,
          'islandGranted': true,
          'liveUpdateGranted': false,
        };
      }
      if (call.method == 'updateFrame') return 'hyper_island';
      if (call.method == 'scheduleFrames') return 1;
      return true;
    });
    island = IslandService(
      storage,
      schedule,
      assignments,
      channel: channel,
      now: () => now,
    );
    addTearDown(() {
      island.dispose();
      assignments.dispose();
      schedule.dispose();
      thirdParty.dispose();
      auth.dispose();
      uniAuth.dispose();
      http.close();
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  test('custom deadlines drive live island updates, completion, reopen, and deletion', () async {
    island.start();
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    // Create a custom deadline within 24h -> immediately shown on the island.
    await assignments.saveCustomDeadline(
      owner: null,
      title: '提交开题报告',
      course: '科研实践',
      location: '信息学院 101',
      notes: '内部备注',
      due: now.add(const Duration(hours: 3)),
    );
    await Future<void>.delayed(Duration.zero);

    final created = lastPushedFrame();
    expect(created['kind'], 'deadline');
    expect(created['title'], '提交开题报告');
    expect(created['statusLine'], '今天截止 12:00');
    expect(created['detail'], '科研实践 · 信息学院 101 · 自定义');
    expect(jsonEncode(created), isNot(contains('内部备注')));

    // Verify native alarm timeline also includes the custom deadline dismissal event.
    await island.scheduleTimeline();
    final scheduledArgs = calls
        .lastWhere((c) => c.method == 'scheduleFrames')
        .arguments as Map<Object?, Object?>;
    final scheduledItems =
        jsonDecode(scheduledArgs['frames'] as String) as List<dynamic>;
    final dueMs = now.add(const Duration(hours: 3)).millisecondsSinceEpoch;
    expect(
      scheduledItems.any(
        (item) =>
            (item as Map<Object?, Object?>)['at'] == dueMs &&
            item['frame'] == null,
      ),
      isTrue,
    );

    // Edit the custom deadline -> live frame updates.
    final custom = assignments.visibleAssignments.single as CustomDeadline;
    await assignments.saveCustomDeadline(
      owner: null,
      id: custom.id,
      title: '提交开题报告（终稿）',
      course: '',
      location: '图书馆 301',
      due: now.add(const Duration(hours: 5)),
    );
    await Future<void>.delayed(Duration.zero);

    final updated = lastPushedFrame();
    expect(updated['title'], '提交开题报告（终稿）');
    expect(updated['statusLine'], '今天截止 14:00');
    expect(updated['detail'], '图书馆 301 · 自定义');

    // Mark completed -> island dismisses.
    calls.clear();
    await assignments.setCompleted(assignments.visibleAssignments.single, true);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), contains('dismiss'));
    expect(calls.where((c) => c.method == 'updateFrame'), isEmpty);

    // Reopen -> island restores the custom deadline.
    calls.clear();
    await assignments.setCompleted(assignments.visibleAssignments.single, false);
    await Future<void>.delayed(Duration.zero);
    expect(lastPushedFrame()['title'], '提交开题报告（终稿）');

    // Delete -> island dismisses.
    calls.clear();
    await assignments.deleteCustomDeadline(custom.id, owner: null);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), contains('dismiss'));
  });

  test('earlier custom deadline takes precedence over later remote assignment', () async {
    await storage.saveCachedAssignments([
      Assignment(
        id: 'remote-1',
        platform: 'blackboard',
        title: '远端作业',
        course: '离散数学',
        due: now.add(const Duration(hours: 8)),
      ).toJson(),
    ]);
    assignments.loadCached();

    island.start();
    await Future<void>.delayed(Duration.zero);
    expect(lastPushedFrame()['title'], '远端作业');

    await assignments.saveCustomDeadline(
      owner: null,
      title: '更早的自定义任务',
      due: now.add(const Duration(hours: 2)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(lastPushedFrame()['title'], '更早的自定义任务');
    expect(lastPushedFrame()['detail'], '自定义');
  });

  test('disabling island cancels native frames and ignores subsequent edits', () async {
    island.start();
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    await island.setEnabled(false);
    expect(calls.map((c) => c.method), containsAll(['dismiss', 'cancelFrames']));

    calls.clear();
    await assignments.saveCustomDeadline(
      owner: null,
      title: '关闭后新增任务',
      due: now.add(const Duration(hours: 2)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
  });
}
