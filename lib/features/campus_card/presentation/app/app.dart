import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../widgets/adaptive_page_navigation.dart';
import '../../app/app_providers.dart';
import '../../domain/models/auth_models.dart';
import '../screens/card_manage_screen.dart';
import '../screens/login_screen.dart';
import '../screens/payment_code_page.dart';
import '../screens/session_restore_screen.dart';
import '../theme/theme.dart';

/// Campus-card feature root.
///
/// The host owns the app theme, locale, chrome and the page the feature is shown
/// on; this widget owns the feature's *page stack* and its colors. The stack is a
/// plain [Navigator] — no router, no route table — whose pages are pushed with
/// the host's own route policy ([adaptivePageRoute]), so a page inside the
/// feature moves, draws and pops like a page anywhere else in TechPie. Because
/// the stack lives inside the feature's `ProviderScope`, the pages and any sheet
/// or dialog they show read the feature's providers directly.
///
/// The first page is a gate rather than a redirect: while the local session is
/// being read there is nothing to decide (the old router waited on the same
/// future), a signed-in account gets the screen the host asked for, and anything
/// else gets the sign-in screen. Losing the account then drops the pages above
/// the gate, exactly as the old redirect did.
class CampusCardFeature extends ConsumerStatefulWidget {
  const CampusCardFeature({super.key});

  @override
  ConsumerState<CampusCardFeature> createState() => _CampusCardFeatureState();
}

class _CampusCardFeatureState extends ConsumerState<CampusCardFeature> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final hostTheme = Theme.of(context);
    final dark = hostTheme.brightness == Brightness.dark;

    return Theme(
      data: GeekPayTheme.inherit(hostTheme),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: hostTheme.scaffoldBackgroundColor,
          systemNavigationBarIconBrightness:
              dark ? Brightness.light : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        // A system back pops the feature's own pages while it has any, and only
        // then reaches the host — which is what pops the feature itself.
        child: NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _navigatorKey.currentState?.pop(),
          child: Navigator(
            key: _navigatorKey,
            onGenerateRoute: (settings) => adaptivePageRoute<Object?>(
              settings: settings,
              builder: (_) => const _EntryGate(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The feature's first page, and the only thing that depends on the account
/// state: it rebuilds in place, so the gate is never a route of its own.
final class _EntryGate extends ConsumerWidget {
  const _EntryGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final snapshot = auth.valueOrNull;
    final entry = ref.watch(campusCardEntryProvider);

    ref.listen(authControllerProvider, (previous, next) {
      if (next.valueOrNull?.state == AuthState.authenticated) return;
      // Everything the feature pushed above this page goes; the page itself stays
      // (it is the sign-in screen now). Matching this page's own route rather
      // than a route name keeps that right whether the host pushed the feature or
      // mounted it as a route of its own — and it can never pop the page under it.
      final here = ModalRoute.of(context);
      if (here == null) return;
      Navigator.of(context).popUntil((route) => identical(route, here));
    });

    // A credential that could not be read is not a missing one: the binding is
    // still saved, so this is the retry surface rather than the sign-in page.
    if (snapshot == null && auth.hasError) return const SessionRestoreScreen();

    return switch (snapshot?.state) {
      // Nothing read yet. Briefly true on every mount, and the old router waited
      // on the same future, so the gate waits too rather than flashing a screen.
      null => const SizedBox.shrink(),
      AuthState.authenticated =>
        entry == CampusCardEntry.cardManagement
            ? const CardManageScreen()
            : const PaymentCodePage(),
      // Only a genuinely missing account is a sign-in: an expired session (or one
      // that could not be read) means the saved binding is still there, so the
      // restore screen offers the retry that fixes it instead of asking for the
      // OPENID again.
      AuthState.signedOut ||
      AuthState.unconfigured ||
      AuthState.signingIn =>
        const LoginScreen(),
      _ => const SessionRestoreScreen(),
    };
  }
}
