import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/deadline_widget_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 12);
  const channel = MethodChannel('test/deadline_widgets');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AssignmentService assignments;
  late DeadlineWidgetService service;
  late List<MethodCall> calls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = AuthService(storage, http, UniAuthService());
    final thirdParty = ThirdPartyAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, thirdParty);
    await storage.saveCachedAssignments([
      for (var i = 0; i < 10; i++)
        Assignment(
          id: '$i',
          platform: 'synthetic',
          title: 'Assignment $i',
          course: 'Course',
          due: now.add(Duration(hours: i + 1)),
          url: 'https://private.example/SECRET',
        ).toJson(),
      Assignment(
        id: 'past',
        platform: 'synthetic',
        title: 'Past',
        course: 'Course',
        due: now.subtract(const Duration(seconds: 1)),
      ).toJson(),
    ]);
    assignments = AssignmentService(storage, http, auth, thirdParty, schedule)
      ..loadCached();
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });
    service =
        DeadlineWidgetService(assignments, channel: channel, now: () => now);
    addTearDown(() {
      service.dispose();
      assignments.dispose();
      schedule.dispose();
      thirdParty.dispose();
      auth.dispose();
      http.close();
      messenger.setMockMethodCallHandler(channel, null);
    });
  });

  test('cached publication excludes private fields and past deadlines',
      () async {
    service.initialize();
    await service.flush();
    final payload = jsonDecode(
      calls.firstWhere((c) => c.method == 'publish').arguments as String,
    ) as Map<String, dynamic>;
    expect(payload['schemaVersion'], 1);
    final items = payload['items'] as List;
    expect(items, hasLength(10));
    expect(
      (items.first as Map).keys.toSet(),
      {'id', 'kind', 'title', 'course', 'dueAt'},
    );
    expect(jsonEncode(payload), isNot(contains('SECRET')));
    expect(jsonEncode(payload), isNot(contains('past')));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await service.flush();
    expect(calls.where((c) => c.method == 'publish'), hasLength(1));
  });

  test('completion and hidden overrides immediately update the snapshot',
      () async {
    service.initialize();
    await service.flush();
    await assignments.setCompleted(assignments.assignments[1], true);
    await service.flush();
    await assignments.hide(assignments.assignments[2]);
    await service.flush();
    final items =
        (jsonDecode(calls.last.arguments as String) as Map)['items'] as List;
    expect(items, hasLength(8));
    expect(items.map((e) => e['id']), isNot(contains('synthetic:0')));
    expect(items.map((e) => e['id']), isNot(contains('synthetic:1')));
  });

  test('clearing identity invalidates queued old publications', () async {
    final blocked = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'publish') await blocked.future;
      return false;
    });
    service.initialize();
    await Future<void>.delayed(Duration.zero);
    await assignments.hide(assignments.assignments.last);
    await assignments.clearCache();
    blocked.complete();
    await service.flush();
    expect(calls.where((c) => c.method == 'publish'), hasLength(1));
    expect(calls.last.method, 'clear');
  });

  testWidgets('cold and warm taps wait for navigation and reuse the handler',
      (tester) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'consumePendingRoute';
    });
    var opened = 0;
    service.initialize();
    await tester.pump();
    service.setOpenHandler(() async {
      opened++;
    });
    await tester.pump();
    expect(opened, 1);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('openDeadlines')),
      (_) {},
    );
    expect(opened, 2);
    expect(
      calls.where((c) => c.method == 'acknowledgePendingRoute'),
      hasLength(2),
    );
  });

  test('sorts exams with assignments and applies completion overrides', () {
    final exam = ExamAssignment(
      id: 'exam',
      title: 'Exam',
      course: 'Course',
      due: now.add(const Duration(hours: 1)),
      semesterId: '2026',
      location: '',
      batchName: '',
    );
    final items = DeadlineWidgetService.displayItems(
      [assignments.assignments.last, exam],
      (_) => false,
      now,
    );
    expect(items.first['kind'], 'exam');
    expect(items.first['dueAt'], exam.due.millisecondsSinceEpoch / 1000);
  });
}
