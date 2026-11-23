import 'package:flutter/widgets.dart';

import 'assignment_service.dart';
import 'auth_service.dart';
import 'campus_card_service.dart';
import 'deadline_reminder_service.dart';
import 'deadline_widget_service.dart';
import 'debug_logger.dart';
import 'ecard_bind_service.dart';
import 'ecard_widget_service.dart';
import 'egate_app_service.dart';
import 'island_service.dart';
import 'oa_gym_service.dart';
import 'schedule_service.dart';
import 'spending_alert_service.dart';
import 'storage_service.dart';
import 'student_allowance_service.dart';
import 'sync_service.dart';
import 'theme_service.dart';
import 'third_party_auth_service.dart';
import 'uni_auth_service.dart';
import 'update_service.dart';

class ServiceProvider extends InheritedWidget {
  final AuthService authService;
  final DebugLogger debugLogger;
  final StorageService storageService;
  final ThemeService themeService;
  final ScheduleService scheduleService;
  final AssignmentService assignmentService;
  final ThirdPartyAuthService thirdPartyAuthService;
  final OaGymService oaGymService;
  final EgateAppService egateAppService;
  final StudentAllowanceService studentAllowanceService;
  final UniAuthService uniAuthService;
  final SyncService syncService;
  final UpdateService updateService;
  final CampusCardService campusCardService;
  final EcardBindService ecardBindService;
  final EcardWidgetService? ecardWidgetService;
  final DeadlineWidgetService? deadlineWidgetService;
  final DeadlineReminderService? deadlineReminderService;
  final SpendingAlertService? spendingAlertService;
  final IslandService? islandService;

  const ServiceProvider({
    super.key,
    required this.authService,
    required this.debugLogger,
    required this.storageService,
    required this.themeService,
    required this.scheduleService,
    required this.assignmentService,
    required this.thirdPartyAuthService,
    required this.oaGymService,
    required this.egateAppService,
    required this.studentAllowanceService,
    required this.uniAuthService,
    required this.syncService,
    required this.updateService,
    required this.campusCardService,
    required this.ecardBindService,
    this.ecardWidgetService,
    this.deadlineWidgetService,
    this.deadlineReminderService,
    this.spendingAlertService,
    this.islandService,
    required super.child,
  });

  static ServiceProvider of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<ServiceProvider>();
    assert(result != null, 'No ServiceProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ServiceProvider oldWidget) =>
      islandService != oldWidget.islandService ||
      authService != oldWidget.authService ||
      debugLogger != oldWidget.debugLogger ||
      storageService != oldWidget.storageService ||
      themeService != oldWidget.themeService ||
      scheduleService != oldWidget.scheduleService ||
      assignmentService != oldWidget.assignmentService ||
      thirdPartyAuthService != oldWidget.thirdPartyAuthService ||
      oaGymService != oldWidget.oaGymService ||
      egateAppService != oldWidget.egateAppService ||
      studentAllowanceService != oldWidget.studentAllowanceService ||
      uniAuthService != oldWidget.uniAuthService ||
      syncService != oldWidget.syncService ||
      updateService != oldWidget.updateService ||
      campusCardService != oldWidget.campusCardService ||
      ecardBindService != oldWidget.ecardBindService ||
      ecardWidgetService != oldWidget.ecardWidgetService ||
      deadlineWidgetService != oldWidget.deadlineWidgetService ||
      deadlineReminderService != oldWidget.deadlineReminderService ||
      spendingAlertService != oldWidget.spendingAlertService;
}
