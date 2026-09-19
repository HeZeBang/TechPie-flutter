import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/campus_card/app/app_providers.dart';
import '../features/campus_card/app/app_runtime.dart';
import '../features/campus_card/presentation/app/app.dart';
import '../features/campus_card/presentation/app/navigation.dart';
import '../services/ecard_widget_service.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'campus_card_account_page.dart';

/// Presents the campus-card routes inside TechPie's theme and navigation.
///
/// The OpenID/JSESSIONID account remains independent from TechPie's primary
/// SSO and CpDaily sessions, while the feature runtime is owned by TechPie.
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
        child: _CampusCardWidgetTarget(widgets: services?.ecardWidgetService),
      ),
    );
  }
}

class _CampusCardWidgetTarget extends ConsumerStatefulWidget {
  const _CampusCardWidgetTarget({required this.widgets});

  final EcardWidgetService? widgets;

  @override
  ConsumerState<_CampusCardWidgetTarget> createState() =>
      _CampusCardWidgetTargetState();
}

class _CampusCardWidgetTargetState
    extends ConsumerState<_CampusCardWidgetTarget> {
  void Function()? _unregister;

  @override
  void initState() {
    super.initState();
    _unregister = widget.widgets?.registerPaymentTarget(_openPay);
  }

  @override
  void didUpdateWidget(covariant _CampusCardWidgetTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.widgets == widget.widgets) return;
    _unregister?.call();
    _unregister = widget.widgets?.registerPaymentTarget(_openPay);
  }

  Future<void> _openPay() async {
    if (!mounted) return;
    // A widget tap while the feature is open sends it to the pay page rather than
    // mounting a second copy of it: the pages above the feature's first one go,
    // and the pay page is either already there or pushed on top of it.
    await goToCampusCardPay(context, ref);
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const CampusCardFeature();
}
