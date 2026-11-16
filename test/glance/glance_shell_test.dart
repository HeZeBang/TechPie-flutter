import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/glance/domain/glance_snapshot.dart';
import 'package:techpie/features/glance/presentation/glance_payment_card.dart';
import 'package:techpie/features/glance/presentation/glance_shell.dart';
import 'package:techpie/models/assignment.dart';
import 'package:techpie/models/course.dart';
import 'package:techpie/models/screen_form_factor.dart';
import 'package:techpie/services/glance_settings_service.dart';

final _now = DateTime(2026, 10, 26, 10, 0);

Course _course(
  String name,
  String start,
  String end,
  CourseColor color, {
  String location = 'A101',
}) {
  return Course(
    name: name,
    location: location,
    dayOfWeek: _now.weekday,
    color: color,
    placement: CoursePlacement(
      startPeriod: 1,
      endPeriod: 1,
      gridStart: 0,
      gridEnd: 1,
      usesCustomTime: true,
      startTime: start,
      endTime: end,
      label: '$start\n$end',
    ),
  );
}

GlanceSnapshot _snapshot({
  bool loggedIn = true,
  List<GlanceCourse>? courses,
  List<GlanceAssignment>? assignments,
}) {
  return GlanceSnapshot(
    now: _now,
    week: 9,
    inTerm: true,
    loggedIn: loggedIn,
    courses: courses ??
        [
          GlanceCourse(
            course: _course('高等数学', '10:00', '10:45', CourseColor.primary),
            state: GlanceCourseState.ongoing,
          ),
          GlanceCourse(
            course: _course('大学物理', '14:00', '14:45', CourseColor.secondary),
            state: GlanceCourseState.upcoming,
          ),
        ],
    pendingAssignments: assignments ??
        [
          GlanceAssignment(
            assignment: Assignment(
              id: 'a1',
              platform: 'test',
              title: '提交实验报告',
              course: '大学物理',
              due: _now.add(const Duration(days: 1)),
            ),
            dueLabel: '明天 23:59',
          ),
        ],
    scheduleLoading: false,
    scheduleError: null,
    assignmentsLoading: false,
    assignmentsError: null,
  );
}

GlanceSnapshot _denseSnapshot() {
  const names = [
    '高等数学（微积分）与线性代数综合',
    '大学物理实验',
    '线性代数',
    '体育',
    '马克思主义基本原理',
    '大学英语视听说',
    '程序设计基础',
  ];
  const locations = [
    '理科楼 A101 阶梯教室',
    '理科楼 B203',
    '教学楼 C302',
    '东操场',
    '文科楼 D401',
    '外语楼 E102',
    '机房 F501',
  ];
  const colors = [
    CourseColor.primary,
    CourseColor.secondary,
    CourseColor.tertiary,
    CourseColor.green,
    CourseColor.orange,
    CourseColor.pink,
    CourseColor.error,
  ];
  final courses = [
    for (var index = 0; index < names.length; index++)
      GlanceCourse(
        course: _course(
          names[index],
          '${(8 + index).toString().padLeft(2, '0')}:00',
          '${(9 + index).toString().padLeft(2, '0')}:35',
          colors[index],
          location: locations[index],
        ),
        state: index == 0
            ? GlanceCourseState.ongoing
            : GlanceCourseState.upcoming,
      ),
  ];
  final assignments = [
    for (var index = 0; index < 5; index++)
      GlanceAssignment(
        assignment: Assignment(
          id: 'dense-$index',
          platform: 'test',
          title: index == 0
              ? '完成大学物理实验报告并提交完整数据分析与误差讨论'
              : '第 ${index + 1} 章课后习题与在线测验',
          course: index == 0 ? '大学物理实验' : '高等数学',
          due: _now.add(Duration(days: index + 1)),
        ),
        dueLabel: index == 0 ? '明天 23:59' : '10/${28 + index} 23:59',
      ),
  ];
  return _snapshot(courses: courses, assignments: assignments);
}

Future<void> _pumpGlance(
  WidgetTester tester, {
  required Size size,
  required GlanceSurface surface,
  required GlanceSnapshot snapshot,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: GlanceShell(
        surface: surface,
        snapshot: snapshot,
        sections: GlanceSection.values,
        paymentBuilder: (_) => const GlancePaymentPreviewCard(),
        onRefresh: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cover layout renders course, deadlines and payment tabs', (
    tester,
  ) async {
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _snapshot(),
    );

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('正在上课'), findsOneWidget);
    expect(find.text('之后'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);
    expect(find.text('今天共 2 节课'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    expect(find.text('提交实验报告'), findsOneWidget);
    expect(find.text('明天 23:59'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('消费码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('glance-payment-qr')), findsOneWidget);
    expect(find.text('示例消费码'), findsOneWidget);
    expect(find.text('¥ 128.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover header and tabs stay inside the 439dp panel', (
    tester,
  ) async {
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _snapshot(),
    );

    final refresh = tester.getRect(find.byIcon(Icons.refresh));
    expect(refresh.top, greaterThanOrEqualTo(0));
    expect(refresh.right, lessThanOrEqualTo(506));

    for (final label in ['课程', '作业', '消费码']) {
      final tab = tester.getRect(find.text(label).last);
      expect(tab.bottom, lessThanOrEqualTo(439));
      expect(tab.top, greaterThan(0));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover layout survives 1.5x text scaling on every page', (
    tester,
  ) async {
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _snapshot(),
      textScale: 1.5,
    );

    expect(find.text('高等数学'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    expect(find.text('提交实验报告'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('消费码'));
    await tester.pumpAndSettle();
    expect(find.text('示例消费码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dense cover data fits 506x439 without overflow', (tester) async {
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _denseSnapshot(),
      textScale: 1.5,
    );

    expect(find.text('高等数学（微积分）与线性代数综合'), findsOneWidget);
    expect(find.text('今天共 7 节课'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    expect(
      find.text('完成大学物理实验报告并提交完整数据分析与误差讨论'),
      findsOneWidget,
    );
    expect(find.text('后续'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('消费码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('glance-payment-qr')), findsOneWidget);
    expect(find.text('示例消费码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rear layout is compact and fits its short panel', (tester) async {
    await _pumpGlance(
      tester,
      size: const Size(340, 210),
      surface: GlanceSurface.rear,
      snapshot: _snapshot(),
    );

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('之后 1 节'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    expect(find.text('提交实验报告'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('消费码'));
    await tester.pumpAndSettle();
    expect(find.text('示例消费码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rear layout survives 1.5x text scaling', (tester) async {
    await _pumpGlance(
      tester,
      size: const Size(340, 210),
      surface: GlanceSurface.rear,
      snapshot: _snapshot(),
      textScale: 1.5,
    );

    expect(find.text('高等数学'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and logged-out states are explicit', (tester) async {
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _snapshot(courses: const [], assignments: const []),
    );
    expect(find.text('今天没有课程'), findsOneWidget);

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    expect(find.text('没有待办事项'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _snapshot(
        loggedIn: false,
        courses: const [],
        assignments: const [],
      ),
    );
    expect(find.text('请先在完整 App 登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished day says so instead of showing an empty list', (
    tester,
  ) async {
    final past = GlanceCourse(
      course: _course('早课', '08:00', '08:45', CourseColor.primary),
      state: GlanceCourseState.past,
    );
    await _pumpGlance(
      tester,
      size: const Size(506, 439),
      surface: GlanceSurface.cover,
      snapshot: _snapshot(courses: [past], assignments: const []),
    );

    expect(find.text('今天的课已结束'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
