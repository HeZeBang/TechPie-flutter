import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/campus_card/app/app_providers.dart';
import '../features/campus_card/app/app_runtime.dart';
import '../features/campus_card/presentation/app/app.dart';
import '../features/campus_card/presentation/app/navigation.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'campus_card_account_page.dart';

/// Presents the campus-card routes inside TechPie's theme and navigation.
///
/// The OpenID/JSESSIONID account remains independent from TechPie's primary
/// SSO and IDS sessions, while the feature runtime is owned by TechPie.
class CampusCardPage extends StatelessWidget {
  const CampusCardPage({
    super.key,
    this.runtime,
    this.entry = CampusCardEntry.paymentCode,
  });

  /// Test-only runtime override. Production uses TechPie's process runtime.
  final AppRuntime? runtime;
  final CampusCardEntry entry;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('[ecard] page opened');
    final services = runtime == null ? ServiceProvider.of(context) : null;
    final value = runtime ?? services!.campusCardService.runtime;
    return CampusCardHostScope(
      navigator: Navigator.of(context),
      child: ProviderScope(
        overrides: [
          appRuntimeProvider.overrideWithValue(value),
          campusCardAccountProvider.overrideWithValue(
            () => unawaited(
              pushAdaptivePage<void>(
                context,
                builder: (_) => const CampusCardAccountPage(),
              ),
            ),
          ),
          campusCardEntryProvider.overrideWithValue(entry),
          homeWidgetPortProvider.overrideWithValue(services?.ecardWidgetService),
        ],
        child: const CampusCardFeature(),
      ),
    );
  }
}
