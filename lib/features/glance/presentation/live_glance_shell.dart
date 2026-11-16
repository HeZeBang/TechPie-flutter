import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/custom_course.dart';
import '../../../models/screen_form_factor.dart';
import '../../../services/assignment_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/glance_settings_service.dart';
import '../../../services/schedule_service.dart';
import '../../../widgets/app_shell/app_entry_notifier.dart';
import '../application/glance_snapshot_builder.dart';
import 'glance_shell.dart';

/// Wires the live services into the presentation-only [GlanceShell].
class LiveGlanceShell extends StatefulWidget {
  const LiveGlanceShell({
    super.key,
    required this.surface,
    required this.settings,
    required this.scheduleService,
    required this.assignmentService,
    required this.authService,
    this.paymentBuilder,
    this.consumeEntry = true,
  });

  final GlanceSurface surface;
  final GlanceSettings settings;
  final ScheduleService scheduleService;
  final AssignmentService assignmentService;
  final AuthService authService;
  final WidgetBuilder? paymentBuilder;
  final bool consumeEntry;

  @override
  State<LiveGlanceShell> createState() => _LiveGlanceShellState();
}

class _LiveGlanceShellState extends State<LiveGlanceShell> {
  Timer? _ticker;
  bool _tickerEnabled = true;
  GlanceSection? _requested;
  int _requestRevision = 0;

  @override
  void initState() {
    super.initState();
    appShellPendingEcardEntry.addListener(_consumeEntry);
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeEntry());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    appShellPendingEcardEntry.removeListener(_consumeEntry);
    _ticker?.cancel();
    super.dispose();
  }

  void _consumeEntry() {
    if (!widget.consumeEntry || !mounted || !_tickerEnabled) return;
    final entry = appShellPendingEcardEntry.value;
    if (entry == null) return;
    appShellPendingEcardEntry.value = null;
    if (widget.paymentBuilder == null ||
        !widget.settings.isEnabled(GlanceSection.payment)) {
      return;
    }
    setState(() {
      _requested = GlanceSection.payment;
      _requestRevision++;
    });
  }

  void _refresh() {
    widget.scheduleService.requestFetch(force: true);
    unawaited(widget.assignmentService.fetchAssignments());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.scheduleService,
        widget.assignmentService,
        widget.authService,
      ]),
      builder: (context, _) {
        final schedule = widget.scheduleService;
        final assignments = widget.assignmentService;
        final now = DateTime.now();
        final week =
            teachingWeekOf(now, schedule.termBegin) ?? schedule.currentWeek();
        final pending = assignments.visibleAssignments
            .where((item) => !assignments.isCompleted(item) && item.due.isAfter(now))
            .toList();
        final snapshot = GlanceSnapshotBuilder.build(
          courseTable: schedule.courseTable,
          customCourses: schedule.customCourses,
          termBegin: schedule.termBegin,
          week: week,
          rawAssignments: assignments.assignments,
          pendingAssignments: pending,
          semesterId: schedule.selectedSemesterId,
          now: now,
          loggedIn: widget.authService.isLoggedIn,
          inTerm: schedule.isTodayInTerm,
          scheduleLoading: schedule.loading,
          scheduleError: schedule.error,
          assignmentsLoading: assignments.loading,
          assignmentsError: assignments.error,
        );
        return GlanceShell(
          surface: widget.surface,
          snapshot: snapshot,
          sections: widget.settings.sections,
          paymentBuilder: widget.paymentBuilder,
          requestedSection: _requested,
          requestRevision: _requestRevision,
          onRefresh: _refresh,
        );
      },
    );
  }
}
