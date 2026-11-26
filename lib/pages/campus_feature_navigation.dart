import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/feature.dart';
import '../services/service_provider.dart';
import '../utils/haptics.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/uni_auth_login.dart';
import 'generic_webview_page.dart';

void openCampusFeature(BuildContext context, Feature feature) {
  unawaited(AppHaptics.play(AppHaptics.selection));
  final services = ServiceProvider.of(context);
  if (!services.authService.isLoggedIn) {
    unawaited(startUniAuthLogin(context));
    return;
  }
  services.telemetry?.featureOpened(feature.id);
  switch (feature.mode) {
    case FeatureMode.native:
      feature.nativeEntry?.call(context);
      break;
    case FeatureMode.webviewWithCookie:
      if (feature.url != null) {
        unawaited(
          pushAdaptivePage<void>(
            context,
            builder: (_) => GenericWebViewPage(
              title: feature.description,
              url: feature.url!,
              cookieType: feature.cookieType,
            ),
          ),
        );
      }
      break;
  }
}
