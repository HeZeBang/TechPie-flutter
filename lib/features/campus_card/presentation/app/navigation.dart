import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../widgets/adaptive_page_navigation.dart';
import '../../app/app_providers.dart';
import '../screens/payment_code_page.dart';

/// Pushes a campus-card screen onto the feature's page stack, with the route the
/// host would have given it ([adaptivePageRoute]): Cupertino geometry and the
/// interactive edge swipe on iOS, the platform's own route elsewhere. The feature
/// carries no router of its own — no paths, no route table, no redirect engine —
/// only pages, pushed the way TechPie pushes pages.
///
/// Pages are keyed to the account that owns them, exactly as the feature's router
/// used to key them: signing in as somebody else never reuses page-local state.
Future<T?> pushCampusCardPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) =>
    Navigator.of(context).push<T>(
      adaptivePageRoute<T>(
        settings: settings,
        builder: (pageContext) => _AccountScope(child: builder(pageContext)),
      ),
    );

/// Sends the feature to its payment code: back to it when the feature opened
/// there, otherwise pushed above the feature's first page (one back away).
Future<void> goToCampusCardPay(BuildContext context, WidgetRef ref) async {
  if (ref.read(campusCardEntryProvider) == CampusCardEntry.paymentCode) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    return;
  }
  await pushCampusCardPage<void>(
    context,
    builder: (_) => const PaymentCodePage(),
  );
}

/// The host navigator that is showing the feature, supplied by the page that
/// mounted it. The feature's own pages are pushed onto its own stack, so leaving
/// the feature is the one pop its stack cannot do itself.
class CampusCardHostScope extends InheritedWidget {
  const CampusCardHostScope({
    super.key,
    required this.navigator,
    required super.child,
  });

  final NavigatorState navigator;

  static NavigatorState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CampusCardHostScope>()
      ?.navigator;

  @override
  bool updateShouldNotify(CampusCardHostScope oldWidget) =>
      navigator != oldWidget.navigator;
}

/// The feature's back action: its own page first, and the page the host is
/// showing the feature on after that — the same order the system back takes.
void popCampusCard(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    unawaited(navigator.maybePop());
    return;
  }
  final host = CampusCardHostScope.maybeOf(context);
  if (host == null) return;
  unawaited(host.maybePop());
}

/// Clears page-local state, including offline QR codes, when the account changes.
class _AccountScope extends ConsumerWidget {
  const _AccountScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(
      authControllerProvider.select(
        (snapshot) => snapshot.valueOrNull?.session?.subjectId,
      ),
    );
    return KeyedSubtree(key: ValueKey(subject), child: child);
  }
}
