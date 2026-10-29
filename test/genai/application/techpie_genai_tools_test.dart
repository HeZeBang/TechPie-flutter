import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/techpie_genai_tools.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/course_table.dart';
import 'package:techpie/models/custom_course.dart';
import 'package:techpie/models/oa_gym.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

import '../support/workspace_server.dart';

void main() {
  late TestGenAiWorkspace demo;
  late _Schedule schedule;
  late _Assignments assignments;
  late _Gym gym;
  late _Auth auth;
  late _Bindings bindings;
  late GenAiAgentToolRegistry registry;
  late GenAiAgentToolContext context;
  late DateTime now;

  setUp(() async {
    demo = await TestGenAiWorkspace.create();
    await demo.workspace.reloadModels();
    schedule = _Schedule();
    assignments = _Assignments();
    gym = _Gym();
    auth = _Auth();
    bindings = _Bindings();
    now = DateTime.utc(2026, 10, 22, 3);
    context = GenAiAgentToolContext(
      cancellation: GenAiCancellation(),
      isCurrent: () => true,
    );
    registry = TechPieGenAiTools(
      schedule: schedule,
      assignments: assignments,
      gym: gym,
      workspace: demo.workspace,
      auth: auth,
      thirdPartyAuth: bindings,
      now: () => now,
    ).createRegistry();
  });
  tearDown(() => demo.dispose());

  Future<GenAiAgentPreparedTool> prepare(
    String name,
    Map<String, Object?> args,
  ) async {
    registry.validate(GenAiAgentToolCall(id: 'test', name: name, arguments: args));
    return registry[name]!.prepare(args, context);
  }

  Future<Map<String, Object?>> run(
    String name,
    Map<String, Object?> args,
  ) async =>
      (await (await prepare(name, args)).execute())! as Map<String, Object?>;

  test('tools reject unknown keys and invalid argument types', () {
    expect(
      () => registry.validate(
        GenAiAgentToolCall(
          id: 'x',
          name: 'generate_image',
          arguments: {'prompt': 'test', 'url': 'private'},
        ),
      ),
      throwsA(isA<GenAiAgentToolException>()),
    );
    expect(
      () => registry.validate(
        GenAiAgentToolCall(
          id: 'x',
          name: 'reserve_court',
          arguments: {
            'action': 'book',
            'sport': 'tennis',
            'date': '2026-10-23',
            'time_slot': '8',
          },
        ),
      ),
      throwsA(isA<GenAiAgentToolException>()),
    );
  });

  test('time and semester results omit internal table and account identifiers', () async {
    final time = await run('get_current_time', {});
    expect(time['campus_time'], '2026-10-22T11:00:00.000+08:00');
    final semesters = await run('get_semesters', {});
    expect(semesters['selected_semester_id'], 'term');
    expect(jsonEncode(semesters), isNot(contains('private-table')));
    expect(jsonEncode(semesters), isNot(contains('secret-token')));
    expect(schedule.fetches, 0);
  });

  test('weekly schedule includes custom courses and leaves semester unchanged', () async {
    final result = await run('get_week_schedule', {'semester_id': 'term', 'week': 2});
    final rows = result['courses']! as List;
    expect(rows, hasLength(2));
    expect(rows.last, containsPair('custom', true));
    expect(rows.last, containsPair('start_time', '19:00'));
    expect(schedule.selectedSemesterId, 'term');
    expect(schedule.fetches, 0);
    await expectLater(
      prepare('get_week_schedule', {'week': 60}).then((tool) => tool.execute()),
      throwsA(
        isA<GenAiAgentToolException>().having((error) => error.code, 'code', 'invalid_arguments'),
      ),
    );
  });

  test('other-semester disk cache cannot bypass current-account verification', () async {
    await expectLater(
      run('get_week_schedule', {'semester_id': 'old-term', 'week': 2}),
      throwsA(
        isA<GenAiAgentToolException>().having((error) => error.code, 'code', 'semester_not_loaded'),
      ),
    );
    expect(schedule.fetches, 0);
  });

  test('failed refresh does not export unverified cached course data', () async {
    schedule.verified = false;
    await expectLater(
      run('get_week_schedule', {'week': 2}),
      throwsA(
        isA<GenAiAgentToolException>().having((error) => error.code, 'code', 'data_unverified'),
      ),
    );
  });

  test('verified schedule avoids refresh; explicit refresh reports service failure', () async {
    schedule.refreshError = 'Network unavailable';
    expect((await run('get_week_schedule', {'week': 2}))['courses'], isNotEmpty);
    expect(schedule.fetches, 0);
    await expectLater(
      run('get_week_schedule', {'week': 2, 'refresh': true}),
      throwsA(
        isA<GenAiAgentToolException>().having((error) => error.code, 'code', 'service_unavailable'),
      ),
    );
    expect(schedule.fetches, 1);
  });

  test('first timetable fetch can establish the selected semester before reading it', () async {
    schedule.selected = null;
    schedule.verified = false;
    schedule.selectedAfterFetch = 'term';
    expect((await run('get_week_schedule', {'week': 2}))['courses'], isNotEmpty);
    expect(schedule.fetches, 1);
  });

  test('weekly pagination stays below the model result budget', () async {
    schedule.manyCourses = true;
    final result = await run('get_week_schedule', {'week': 2, 'limit': 40});
    expect(jsonEncode(result).length, lessThan(6000));
    expect(result['truncated'], true);
    final next = await run(
      'get_week_schedule',
      {'week': 2, 'offset': result['next_offset']},
    );
    expect(next['courses'], isNotEmpty);
  });

  test('missing calendar requires explicit week instead of inventing current week', () async {
    schedule.calendar = null;
    await expectLater(
      run('get_week_schedule', {}),
      throwsA(
        isA<GenAiAgentToolException>()
            .having((error) => error.code, 'code', 'calendar_unavailable'),
      ),
    );
    expect((await run('get_week_schedule', {'week': 2}))['week'], 2);
  });

  test('assignment tool returns verified results with unavailable platform metadata', () async {
    assignments.failures = {'gradescope': 'Unavailable'};
    final result = await run('get_assignments', {});
    expect(result['partial'], isTrue);
    expect(result['unavailable_platforms'], ['gradescope']);
    expect(result['assignments'], isNotEmpty);
  });

  test('assignments respect visible list completion override and inclusive campus date', () async {
    final result = await run('get_assignments', {'due_before': '2026-10-23'});
    final rows = result['assignments']! as List;
    expect(rows, hasLength(1));
    expect(rows.single, containsPair('id', 'todo'));
    expect(rows.single, containsPair('due', '2026-10-23T23:00:00.000+08:00'));
    expect(jsonEncode(result), isNot(contains('token=private')));
    expect(
      (await run(
        'get_assignments',
        {'include_completed': true},
      ))['assignments'],
      hasLength(2),
    );
    await expectLater(
      run('get_assignments', {'due_before': '2026-02-31'}),
      throwsA(isA<GenAiAgentToolException>()),
    );
  });

  test('binding change while refreshing prevents returning newly mixed data', () async {
    final gate = Completer<void>();
    assignments.refreshGate = gate.future;
    final future = run('get_assignments', {'refresh': true});
    await Future<void>.delayed(Duration.zero);
    bindings.values.add(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.gradescope,
        account: 'new',
        token: 'secret',
        boundAt: DateTime.utc(2026),
      ),
    );
    gate.complete();
    await expectLater(
      future,
      throwsA(
        isA<GenAiFailure>().having(
          (error) => error.kind,
          'kind',
          GenAiFailureKind.accountChanged,
        ),
      ),
    );
  });

  const book = <String, Object?>{
    'action': 'book',
    'sport': 'tennis',
    'date': '2026-10-23',
    'time_slot': 8,
    'court_number': 1,
    'players_count': 2,
  };

  test('court preparation reads availability and approval precedes recheck and booking', () async {
    final prepared = await prepare('reserve_court', book);
    expect(prepared.requiresApproval, isTrue);
    final equivalent = await prepare('reserve_court', {...book, 'end_slot': 8});
    expect(prepared.effectKey, equivalent.effectKey);
    expect(gym.checks, 2);
    expect(gym.bookings, 0);
    expect(jsonEncode(prepared.details), isNot(contains('13800000000')));
    final result = await prepared.execute();
    expect(result, containsPair('success', true));
    expect(gym.checks, 3);
    expect(gym.bookings, 1);
  });

  test('bulk ranges and model-supplied approvals cannot authorize a booking', () async {
    for (final args in [
      {...book, 'end_slot': 9},
      {
        ...book,
        'court_number': [1, 2, 3],
      },
      {...book, 'confirmed': true},
      {...book, 'action': 'book_all'},
    ]) {
      await expectLater(prepare('reserve_court', args), throwsA(isA<GenAiAgentToolException>()));
    }
    expect(gym.bookings, 0);
    expect(gym.checks, 0);
  });

  test('reservation approvals are single-use and expire before POST after renewal', () async {
    expect(registry['reserve_court']!.maxApprovalsPerRun, 1);
    final prepared = await prepare('reserve_court', book);
    final first = prepared.execute();
    await expectLater(
      prepared.execute(),
      throwsA(
        isA<GenAiAgentToolException>().having((e) => e.code, 'code', 'booking_already_attempted'),
      ),
    );
    await first;
    expect(gym.bookings, 1);
    final stale = await prepare('reserve_court', {...book, 'time_slot': 9});
    now = now.add(const Duration(minutes: 2));
    await expectLater(
      stale.execute(),
      throwsA(
        isA<GenAiAgentToolException>()
            .having((e) => e.code, 'code', 'approval_expired')
            .having((e) => e.effectNotDispatched, 'not dispatched', isTrue),
      ),
    );
    final renewed = await prepare('reserve_court', {...book, 'time_slot': 10});
    gym.beforePost = () => now = now.add(const Duration(minutes: 2));
    await expectLater(
      renewed.execute(),
      throwsA(
        isA<GenAiAgentToolException>()
            .having((e) => e.code, 'code', 'approval_expired')
            .having((e) => e.effectNotDispatched, 'not dispatched', isTrue),
      ),
    );
    expect(gym.bookings, 1);
  });

  test('shared physical court aliases have the same mutation identity', () async {
    gym.allCourts = true;
    final tennis = await prepare('reserve_court', {...book, 'court_number': 4});
    final pickleball = await prepare(
      'reserve_court',
      {...book, 'sport': 'pickleball', 'court_number': 1, 'players_count': 4},
    );
    expect(tennis.effectKey, pickleball.effectKey);
    expect(gym.bookings, 0);
  });

  test('court availability and contact changes after approval prevent submission', () async {
    final prepared = await prepare('reserve_court', book);
    gym.available = false;
    await expectLater(
      prepared.execute(),
      throwsA(
        isA<GenAiAgentToolException>()
            .having((error) => error.code, 'code', 'court_not_available')
            .having((error) => error.effectNotDispatched, 'not dispatched', isTrue),
      ),
    );
    expect(gym.bookings, 0);
    gym.available = true;
    final again = await prepare('reserve_court', book);
    gym.profile = gym.profile.copyWith(phone: '13900000000');
    await expectLater(
      again.execute(),
      throwsA(
        isA<GenAiAgentToolException>()
            .having((error) => error.code, 'code', 'profile_changed')
            .having((error) => error.effectNotDispatched, 'not dispatched', isTrue),
      ),
    );
    expect(gym.bookings, 0);
  });

  test('account or cancellation during booking session renewal prevents POST', () async {
    final prepared = await prepare('reserve_court', book);
    gym.beforePost = () {
      auth.loggedIn = false;
    };
    await expectLater(
      prepared.execute(),
      throwsA(
        isA<GenAiFailure>().having(
          (error) => error.kind,
          'kind',
          GenAiFailureKind.accountChanged,
        ),
      ),
    );
    expect(gym.bookings, 0);
    auth.loggedIn = true;
    context = GenAiAgentToolContext(
      cancellation: GenAiCancellation(),
      isCurrent: () => true,
    );
    final again = await prepare('reserve_court', book);
    gym.beforePost = () {
      context.cancellation.cancel();
    };
    await expectLater(again.execute(), throwsA(isA<GenAiFailure>()));
    expect(gym.bookings, 0);
  });

  test('image preparation validates current models size and requires approval', () async {
    await expectLater(
      prepare('generate_image', {'prompt': 'test', 'model': 'invented'}),
      throwsA(
        isA<GenAiAgentToolException>().having((error) => error.code, 'code', 'model_unavailable'),
      ),
    );
    await expectLater(
      prepare('generate_image', {'prompt': 'test', 'width': 1, 'height': 1}),
      throwsA(
        isA<GenAiAgentToolException>().having((error) => error.code, 'code', 'invalid_arguments'),
      ),
    );
    final prepared = await prepare(
      'generate_image',
      {'prompt': 'A red square', 'width': 1536, 'height': 1024},
    );
    expect(prepared.requiresApproval, isTrue);
    expect(prepared.details['size'], '1536x1024');
    final equivalent = await prepare('generate_image', {
      'prompt': 'A red square',
      'width': 1536,
      'height': 1024,
      'quality': 'low',
      'model': 'test-image',
    });
    expect(prepared.effectKey, equivalent.effectKey);
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
    final result = await prepared.execute();
    expect(result, containsPair('status', 'generated'));
    expect(result, containsPair('size', '1536x1024'));
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      hasLength(1),
    );
  });

  test('image quota refusal clears pending effect but generic errors remain uncertain', () async {
    for (final message in ['账户额度不足', '系统内部错误']) {
      demo.backend.imageRejection = message;
      final prepared = await prepare('generate_image', {'prompt': 'A red square'});
      final refused = message == '账户额度不足';
      await expectLater(
        prepared.execute(),
        throwsA(
          isA<GenAiAgentToolException>()
              .having((e) => e.code, 'code', refused ? 'rejected' : 'outcome_unknown')
              .having((e) => e.effectNotDispatched, 'not dispatched', refused),
        ),
      );
    }
  });

  test('afternoon availability accepts a whole-day query but past bookings are rejected', () async {
    now = DateTime.utc(2026, 10, 22, 6);
    final result = await run('reserve_court', {
      'action': 'availability',
      'sport': 'tennis',
      'date': '2026-10-22',
      'time_slot': 1,
      'end_slot': 11,
    });
    expect(result['status'], 'availability');
    expect(gym.checks, 1);
    await expectLater(
      prepare('reserve_court', {...book, 'date': '2026-10-22', 'time_slot': 1}),
      throwsA(isA<GenAiAgentToolException>().having((e) => e.code, 'code', 'invalid_arguments')),
    );
    expect(gym.bookings, 0);
  });

  test('cancelled image approval cannot dispatch generation', () async {
    final prepared = await prepare('generate_image', {'prompt': 'A red square'});
    context.cancellation.cancel();
    await expectLater(prepared.execute(), throwsA(isA<GenAiFailure>()));
    expect(
      (await demo.workspace.repository.listImages(GenAiCancellation())).records,
      isEmpty,
    );
  });
}

class _Auth implements AuthService {
  bool loggedIn = true;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  UserSession? get session => loggedIn
      ? UserSession(
          userId: 'user',
          userName: 'Test',
          schoolName: 'School',
          createdAt: DateTime.utc(2026),
        )
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bindings implements ThirdPartyAuthService {
  final values = [
    ThirdPartyAccount(
      platform: ThirdPartyPlatform.cpdaily,
      account: '20240001',
      sid: '20240001',
      token: 'secret-token',
      boundAt: DateTime.utc(2026),
    ),
  ];
  @override
  bool get hasCpdailyBinding => values.isNotEmpty;
  @override
  ThirdPartyAccount? get cpdailyBinding => values.firstOrNull;
  @override
  Iterable<ThirdPartyAccount> get accounts => values;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Schedule implements ScheduleService {
  @override
  bool get hasVerifiedAccountData => verified;
  bool verified = true;
  bool manyCourses = false;
  String? refreshError;
  String? selected = 'term';
  String? selectedAfterFetch;
  int fetches = 0;
  TermCalendar? calendar = TermCalendar(
    code: 200,
    schoolYearTerm: '2026',
    termBegin: DateTime(2026, 10, 12),
    snapshotDate: null,
    snapshotWeekOfTerm: null,
    allTeachWeeks: 16,
    allTermWeeks: 18,
    amClasses: 4,
    pmClasses: 4,
    eveClasses: 2,
  );
  @override
  SemesterInfo get semesterInfo => const SemesterInfo(
        semesters: {
          '2026': {'秋': 'term'},
        },
        defaultSemester: 'term',
        tableId: 'private-table',
      );
  @override
  String? get selectedSemesterId => selected;
  @override
  bool get loading => false;
  @override
  String? get error => refreshError;
  @override
  Future<void> fetchAll() async {
    fetches++;
    if (selectedAfterFetch != null) {
      selected = selectedAfterFetch;
      verified = true;
    }
  }

  @override
  CourseTable? courseTableFor(String? semesterId) => manyCourses
      ? CourseTable(
          periods: [],
          courses: [
            for (var i = 0; i < 60; i++)
              EamsCourse(
                name: 'Lecture $i ${'A' * 240}',
                classroom: 'Room ${'B' * 240}',
                teachers: 'Teacher',
                weeks: '011111',
                times: const {
                  1: [1, 2],
                },
              ),
          ],
        )
      : const CourseTable(
          periods: [],
          courses: [
            EamsCourse(
              name: 'Lecture',
              classroom: 'A101',
              teachers: 'Teacher',
              weeks: '011111',
              times: {
                1: [1, 2],
              },
            ),
          ],
        );

  @override
  TermCalendar? termCalendarFor(String? semesterId) => calendar;
  @override
  List<CustomCourse> customCoursesFor(String? semesterId) => [
        CustomCourse(
          id: 'custom',
          name: 'Tutorial',
          semesterId: semesterId!,
          weekdays: const [3],
          weeks: const [2],
          time: const ClockCourseTime(startTime: '19:00', endTime: '20:00'),
        ),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Assignments implements AssignmentService {
  @override
  bool get hasVerifiedAccountData => true;
  @override
  List<Assignment> get verifiedVisibleAssignments => visibleAssignments;
  Future<void>? refreshGate;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  Map<String, String> failures = {};
  @override
  Map<String, String> get platformErrors => failures;
  @override
  List<Assignment> get visibleAssignments => [
        Assignment(
          id: 'todo',
          platform: 'blackboard',
          title: 'Report',
          course: 'Course',
          due: DateTime.utc(2026, 10, 23, 15),
          url: 'https://example.com?token=private',
        ),
        Assignment(
          id: 'done',
          platform: 'blackboard',
          title: 'Done',
          course: 'Course',
          due: DateTime.utc(2026, 10, 23, 16),
        ),
      ];
  @override
  bool isCompleted(Assignment value) => value.id == 'done';
  @override
  Future<void> fetchAssignments() async {
    await refreshGate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gym implements OaGymService {
  int checks = 0;
  int bookings = 0;
  bool available = true;
  bool allCourts = false;
  void Function()? beforePost;
  OaBookingProfile profile = const OaBookingProfile(
    name: 'Private Name',
    phone: '13800000000',
    email: 'private@example.com',
  );
  @override
  OaBookingProfile bookingProfile() => profile;
  @override
  String get bookingStudentId => '20240001';
  @override
  Future<List<OaAvailability>> checkAvailability({
    required Set<OaSport> sports,
    required String date,
    required int startSlot,
    required int endSlot,
    void Function(List<OaAvailability>)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    shouldContinue?.call();
    checks++;
    return [
      OaAvailability(
        sport: sports.single,
        date: date,
        timeSlot: startSlot,
        availableCourts: available ? (allCourts ? [1, 2, 3, 4] : [1]) : [],
        totalCourts: 4,
      ),
    ];
  }

  @override
  Future<OaBookingResult> bookCourt({
    required OaSport sport,
    required String date,
    required int timeSlot,
    required int courtNumber,
    required int playersCount,
    bool Function()? shouldContinue,
  }) async {
    await Future<void>.delayed(Duration.zero);
    beforePost?.call();
    shouldContinue?.call();
    bookings++;
    return const OaBookingResult(success: true, message: 'done');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
