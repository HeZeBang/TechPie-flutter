import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:flutter/widgets.dart';

import '../services/service_provider.dart';
import '../services/uni_auth_service.dart';
import 'adaptive_feedback.dart';

final _pendingLogins = Expando<Future<void>>();

/// Opens authentication directly and shares an in-flight login across entries.
Future<void> startUniAuthLogin(BuildContext context) {
  if (!context.mounted) return Future<void>.value();
  final services = ServiceProvider.of(context);
  final auth = services.uniAuthService;
  final pending = _pendingLogins[auth];
  if (pending != null) return pending;
  final operation = _login(context, services, auth).whenComplete(() {
    _pendingLogins[auth] = null;
  });
  _pendingLogins[auth] = operation;
  return operation;
}

Future<void> _login(BuildContext context, ServiceProvider services, UniAuthService auth) async {
  try {
    final tokens = await auth.login(context);
    await services.authService.geekpieLogin(tokens);
    services.scheduleService.requestFetch(force: true);
  } catch (error) {
    // The desktop SDK throws the exception Type; mobile throws an instance.
    if (error is CasdoorAuthCancelledException || error == CasdoorAuthCancelledException) return;
    showAdaptiveFeedback(message: '登录失败：$error', style: AdaptiveFeedbackStyle.error);
  }
}
