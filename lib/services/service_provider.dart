import 'package:flutter/widgets.dart';

import 'assignment_service.dart';
import 'auth_service.dart';
import 'debug_logger.dart';
import 'oa_gym_service.dart';
import 'schedule_service.dart';
import 'storage_service.dart';
import 'theme_service.dart';
import 'third_party_auth_service.dart';
import 'uni_auth_service.dart';

class ServiceProvider extends InheritedWidget {
  final AuthService authService;
  final DebugLogger debugLogger;
  final StorageService storageService;
  final ThemeService themeService;
  final ScheduleService scheduleService;
  final AssignmentService assignmentService;
  final ThirdPartyAuthService thirdPartyAuthService;
  final OaGymService oaGymService;
  final UniAuthService uniAuthService;

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
    required this.uniAuthService,
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
      authService != oldWidget.authService ||
      debugLogger != oldWidget.debugLogger ||
      storageService != oldWidget.storageService ||
      themeService != oldWidget.themeService ||
      scheduleService != oldWidget.scheduleService ||
      assignmentService != oldWidget.assignmentService ||
      thirdPartyAuthService != oldWidget.thirdPartyAuthService ||
      oaGymService != oldWidget.oaGymService ||
      uniAuthService != oldWidget.uniAuthService;
}
