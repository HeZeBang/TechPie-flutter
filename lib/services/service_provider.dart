import 'package:flutter/widgets.dart';

import 'academic_certificate_service.dart';
import 'assignment_service.dart';
import 'auth_service.dart';
import 'campus/campus_clients.dart';
import 'campus_card_service.dart';
import 'course_catalog_service.dart';
import 'deadline_reminder_service.dart';
import 'deadline_widget_service.dart';
import 'debug_logger.dart';
import 'ecard_bind_service.dart';
import 'ecard_widget_service.dart';
import 'egate_app_service.dart';
import 'glance_settings_service.dart';
import 'grade_service.dart';
import 'holiday_travel_service.dart';
import 'island_service.dart';
import 'oa_gym_service.dart';
import 'pnp_minor_service.dart';
import 'schedule_service.dart';
import 'screen_form_factor_service.dart';
import 'spending_alert_service.dart';
import 'storage_service.dart';
import 'student_allowance_service.dart';
import 'student_leave_service.dart';
import 'study_plan_service.dart';
import 'sync_service.dart';
import 'theme_service.dart';
import 'third_party_auth_service.dart';
import 'uni_auth_service.dart';
import 'update_service.dart';
import 'usage_telemetry.dart';
import 'wear/wear_engine_service.dart';

class ServiceProvider extends InheritedWidget {
  final AuthService authService;
  final DebugLogger debugLogger;
  final StorageService storageService;
  final UsageTelemetry? telemetry;
  final StudyPlanService? studyPlanService;
  final ThemeService themeService;
  final ScheduleService scheduleService;
  final AssignmentService assignmentService;
  final ThirdPartyAuthService thirdPartyAuthService;
  final OaGymService oaGymService;
  final EgateAppService egateAppService;
  final StudentLeaveService? studentLeaveService;
  final StudentAllowanceService studentAllowanceService;
  final UniAuthService uniAuthService;
  final SyncService syncService;
  final UpdateService updateService;
  final AcademicCertificateService? certificates;
  final PnpMinorService? pnpMinor;
  final CourseCatalogService? courseCatalog;
  final GradeService? gradeService;
  final CampusClients? campusClients;
  final CampusCardService campusCardService;
  final EcardBindService ecardBindService;
  final EcardWidgetService? ecardWidgetService;
  final ScreenFormFactorService? screenFormFactorService;
  final GlanceSettings? glanceSettings;
  final WearEngineService? wearEngineService;
  final DeadlineWidgetService? deadlineWidgetService;
  final DeadlineReminderService? deadlineReminderService;
  final SpendingAlertService? spendingAlertService;
  final HolidayTravelService? holidayTravelService;
  final IslandService? islandService;

  const ServiceProvider({
    super.key,
    required this.authService,
    required this.debugLogger,
    required this.storageService,
    this.telemetry,
    this.studyPlanService,
    required this.themeService,
    required this.scheduleService,
    required this.assignmentService,
    required this.thirdPartyAuthService,
    required this.oaGymService,
    required this.egateAppService,
    this.studentLeaveService,
    required this.studentAllowanceService,
    required this.uniAuthService,
    required this.syncService,
    required this.updateService,
    this.campusClients,
    this.certificates,
    this.pnpMinor,
    this.courseCatalog,
    this.gradeService,
    required this.campusCardService,
    required this.ecardBindService,
    this.ecardWidgetService,
    this.screenFormFactorService,
    this.glanceSettings,
    this.wearEngineService,
    this.deadlineWidgetService,
    this.deadlineReminderService,
    this.spendingAlertService,
    this.holidayTravelService,
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
      screenFormFactorService != oldWidget.screenFormFactorService ||
      glanceSettings != oldWidget.glanceSettings ||
      holidayTravelService != oldWidget.holidayTravelService ||
      islandService != oldWidget.islandService ||
      authService != oldWidget.authService ||
      debugLogger != oldWidget.debugLogger ||
      storageService != oldWidget.storageService ||
      telemetry != oldWidget.telemetry ||
      studyPlanService != oldWidget.studyPlanService ||
      themeService != oldWidget.themeService ||
      scheduleService != oldWidget.scheduleService ||
      assignmentService != oldWidget.assignmentService ||
      thirdPartyAuthService != oldWidget.thirdPartyAuthService ||
      oaGymService != oldWidget.oaGymService ||
      egateAppService != oldWidget.egateAppService ||
      studentLeaveService != oldWidget.studentLeaveService ||
      studentAllowanceService != oldWidget.studentAllowanceService ||
      uniAuthService != oldWidget.uniAuthService ||
      syncService != oldWidget.syncService ||
      updateService != oldWidget.updateService ||
      certificates != oldWidget.certificates ||
      pnpMinor != oldWidget.pnpMinor ||
      courseCatalog != oldWidget.courseCatalog ||
      gradeService != oldWidget.gradeService ||
      campusClients != oldWidget.campusClients ||
      campusCardService != oldWidget.campusCardService ||
      ecardBindService != oldWidget.ecardBindService ||
      ecardWidgetService != oldWidget.ecardWidgetService ||
      wearEngineService != oldWidget.wearEngineService ||
      deadlineWidgetService != oldWidget.deadlineWidgetService ||
      deadlineReminderService != oldWidget.deadlineReminderService ||
      spendingAlertService != oldWidget.spendingAlertService;
}
