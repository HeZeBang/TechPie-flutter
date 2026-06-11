import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../models/course_table.dart';
import '../models/course.dart';
import '../models/assignment.dart';
import '../models/assignment_overrides.dart';

class WidgetSyncService {
  static const String _groupId = 'group.com.example.techpie'; 
  // IMPORTANT: Ensure this matches the App Group identifier configured in Xcode

  static Future<void> syncSchedule(CourseTable table, int currentWeek) async {
    final now = DateTime.now();
    final weekday = now.weekday; // 1 = Mon, 7 = Sun
    
    // Convert to display courses, filtering for current week
    final displayCourses = eamsToDisplayCourses(table.courses, currentWeek);
    
    // Get today's active courses, sorted by period
    final todayCourses = displayCourses
        .where((c) => c.dayOfWeek == weekday && !c.isGhost)
        .toList();
    todayCourses.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));

    final coursesJson = todayCourses.map((c) {
      final startTime = defaultPeriods.firstWhere((p) => p.number == c.startPeriod, orElse: () => const Period(number: 0, startTime: '', endTime: '')).startTime;
      final endTime = defaultPeriods.firstWhere((p) => p.number == c.endPeriod, orElse: () => const Period(number: 0, startTime: '', endTime: '')).endTime;
      return {
        'name': c.name,
        'location': c.location,
        'startTime': startTime,
        'endTime': endTime,
      };
    }).toList();

    await HomeWidget.setAppGroupId(_groupId);
    await HomeWidget.saveWidgetData('schedule_data', jsonEncode(coursesJson));
    await HomeWidget.updateWidget(name: 'TechPieWidget', iOSName: 'TechPieWidget');
  }

  static Future<void> syncAssignments(List<Assignment> assignments, AssignmentOverrides overrides) async {
    final now = DateTime.now();
    
    final pending = assignments.where((a) {
      if (overrides.isHidden(a)) return false;
      if (overrides.effectiveCompleted(a)) return false;
      return a.due.isAfter(now);
    }).toList();
    
    pending.sort((a, b) => a.due.compareTo(b.due));
    final topPending = pending.take(3).toList();

    final assignmentsJson = topPending.map((a) {
      return {
        'title': a.title,
        'course': a.course,
        'due': a.due.toIso8601String(),
      };
    }).toList();

    await HomeWidget.setAppGroupId(_groupId);
    await HomeWidget.saveWidgetData('assignment_data', jsonEncode(assignmentsJson));
    await HomeWidget.updateWidget(name: 'TechPieWidget', iOSName: 'TechPieWidget');
  }
}
