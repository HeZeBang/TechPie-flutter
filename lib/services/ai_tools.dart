import 'package:flutter_ai_tools/flutter_ai_tools.dart';

import '../models/course_table.dart';
import 'assignment_service.dart';
import 'schedule_service.dart';
import 'third_party_auth_service.dart';

/// Builds the [ToolRegistry] of campus-service tools the AI assistant can call.
///
/// All four tools are read-only and safe to auto-execute (no confirmation
/// gate). Each executor returns a JSON-encodable Map (best for the model to
/// reason over) and never throws — failures become a `{'error': ...}` map so
/// the model can surface them to the user. eGate-gated tools return a friendly
/// "not bound" error when the user hasn't bound their campus account.
ToolRegistry buildAiTools({
  required ScheduleService scheduleService,
  required AssignmentService assignmentService,
  required ThirdPartyAuthService thirdPartyAuthService,
}) {
  return ToolRegistry([
    ToolSpec(
      name: 'get_current_time',
      description:
          'Get the current date, time, day of week, and the current academic '
          'week number (1-based, derived from the semester\'s term-begin date). '
          'Call this whenever the user asks what time/day/week it is, or when '
          'a relative date is needed.',
      parametersSchema: const {
        'type': 'object',
        'properties': {},
      },
      execute: (args) async {
        final now = DateTime.now();
        const weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        return {
          'now': now.toIso8601String(),
          'weekday': now.weekday,
          'weekdayName': weekdayNames[now.weekday],
          'currentWeek': scheduleService.currentWeek(),
        };
      },
    ),

    ToolSpec(
      name: 'get_semesters',
      description:
          'List the student\'s available semesters (e.g. "2024-2025 春学期") '
          'with their IDs, and which semester is currently selected. Requires '
          'the eGate campus binding. Call when the user asks about available '
          'terms or which semester is active.',
      parametersSchema: const {
        'type': 'object',
        'properties': {},
      },
      execute: (args) async {
        if (!thirdPartyAuthService.hasEgateBinding) {
          return {'error': '未绑定 eGate 校园账号，请在设置中绑定后再试。'};
        }
        await scheduleService.loadCachedData();
        var info = scheduleService.semesterInfo;
        if (info == null || info.allSemesters.isEmpty) {
          await scheduleService.fetchSemesters();
          info = scheduleService.semesterInfo;
        }
        if (info == null) {
          return {'error': scheduleService.error ?? '获取学期列表失败'};
        }
        return {
          'currentSemesterId': scheduleService.selectedSemesterId,
          'currentLabel':
              scheduleService.selectedSemesterId == null
                  ? null
                  : info.findSemesterLabel(scheduleService.selectedSemesterId!),
          'semesters': [
            for (final e in info.allSemesters)
              {'id': e.key, 'label': e.value},
          ],
        };
      },
    ),

    ToolSpec(
      name: 'get_week_schedule',
      description:
          'Get the course schedule for a specific semester and week. Returns '
          'courses grouped by weekday (周一~周日), each with name, location, '
          'period range, time range, teachers, and active weeks. Requires the '
          'eGate campus binding. If semesterId or week are omitted, defaults to '
          'the current semester and current week. Call when the user asks about '
          'their timetable / what classes they have.',
      parametersSchema: const {
        'type': 'object',
        'properties': {
          'semesterId': {
            'type': 'string',
            'description':
                'Semester ID (from get_semesters). Omit for the current '
                'semester.',
          },
          'week': {
            'type': 'integer',
            'description': 'Week number (1-based). Omit for the current week.',
            'minimum': 1,
            'maximum': 25,
          },
        },
      },
      execute: (args) async {
        if (!thirdPartyAuthService.hasEgateBinding) {
          return {'error': '未绑定 eGate 校园账号，请在设置中绑定后再试。'};
        }
        await scheduleService.loadCachedData();
        final semesterId =
            (args['semesterId'] as String?)?.isNotEmpty == true
                ? args['semesterId'] as String
                : scheduleService.selectedSemesterId;
        if (semesterId == null) {
          return {'error': '无法确定当前学期，请先调用 get_semesters。'};
        }
        // Fetch the course table for the requested semester if not cached.
        if (scheduleService.courseTable == null) {
          await scheduleService.fetchCourseTable(semesterId);
        }
        final table = scheduleService.courseTable;
        if (table == null) {
          return {'error': scheduleService.error ?? '获取课程表失败'};
        }
        final week =
            args['week'] is int
                ? args['week'] as int
                : scheduleService.currentWeek();
        final display = eamsToDisplayCourses(table.courses, week);
        // Period index → time range, from the table's period definitions.
        final periodTimes = <int, String>{};
        for (final p in table.periods) {
          periodTimes[p.index] = p.timeRange;
        }
        const dayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
        // Group by weekday.
        final byDay = <int, List<Map<String, Object?>>>{};
        for (final c in display) {
          byDay.putIfAbsent(c.dayOfWeek, () => []).add({
            'name': c.name,
            'location': c.location,
            'periods': '${c.startPeriod}-${c.endPeriod}',
            'time':
                '${periodTimes[c.startPeriod] ?? ''}~${periodTimes[c.endPeriod] ?? ''}',
            if (c.teachers != null && c.teachers!.isNotEmpty)
              'teachers': c.teachers,
            if (c.weeksText != null && c.weeksText!.isNotEmpty)
              'weeks': c.weeksText,
            if (c.isGhost) 'note': '本周无此课（仅供参考）',
          });
        }
        final days = <Map<String, Object?>>[];
        for (var d = 1; d <= 7; d++) {
          final courses = byDay[d];
          if (courses == null || courses.isEmpty) continue;
          days.add({'day': dayNames[d], 'courses': courses});
        }
        final info = scheduleService.semesterInfo;
        return {
          'semesterId': semesterId,
          'semesterLabel': info?.findSemesterLabel(semesterId),
          'week': week,
          'days': days,
          if (days.isEmpty) 'note': '本周没有课程',
        };
      },
    ),

    ToolSpec(
      name: 'get_assignments',
      description:
          'Get the student\'s upcoming assignments and exams (deadlines) across '
          'all platforms (Blackboard, exams, Gradescope, Hydro), sorted by due '
          'date. Each item has title, course, due date, platform, kind '
          '(作业/考试), and status. Optionally filter by platform or kind. Call '
          'when the user asks about homework, deadlines, or exams.',
      parametersSchema: const {
        'type': 'object',
        'properties': {
          'platform': {
            'type': 'string',
            'description':
                'Filter to one platform: blackboard, exam, gradescope, or hydro. '
                'Omit for all.',
            'enum': ['blackboard', 'exam', 'gradescope', 'hydro'],
          },
          'kind': {
            'type': 'string',
            'description': 'Filter to assignments or exams. Omit for both.',
            'enum': ['assignment', 'exam'],
          },
        },
      },
      execute: (args) async {
        assignmentService.loadCached();
        if (assignmentService.visibleAssignments.isEmpty) {
          await assignmentService.fetchAssignments();
        }
        var items = assignmentService.visibleAssignments;
        final platform = args['platform'] as String?;
        final kind = args['kind'] as String?;
        if (platform != null) {
          items = items.where((a) => a.platform == platform).toList();
        }
        if (kind != null) {
          items = items.where((a) => a.kind.id == kind).toList();
        }
        final errors = assignmentService.platformErrors;
        return {
          'assignments': [
            for (final a in items)
              {
                'title': a.title,
                'course': a.course,
                'due': a.due.toIso8601String(),
                if (a.lateDue != null) 'lateDue': a.lateDue!.toIso8601String(),
                'platform': a.platform,
                'kind': a.kind.label,
                if (a.status != null) 'status': a.status,
                'submitted': a.submitted,
                if (a.url != null) 'url': a.url,
              },
          ],
          if (assignmentService.error != null) 'error': assignmentService.error,
          if (errors.isNotEmpty) 'platformErrors': errors,
        };
      },
    ),
  ]);
}
