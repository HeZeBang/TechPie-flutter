import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/glance/presentation/glance_payment_view.dart';
import '../../features/glance/presentation/live_glance_shell.dart';
import '../../models/screen_form_factor.dart';
import '../../services/glance_settings_service.dart';
import '../../services/screen_form_factor_service.dart';
import '../../services/service_provider.dart';
import 'glance_active_scope.dart';

/// Chooses between the full app and the compact glance, keeping both alive.
///
/// Mounted from `MaterialApp.builder`, so it hides the whole navigator —
/// including routes, dialogs and snackbars — when the app is on a rear/cover
/// screen. The hidden navigator is not disposed, which is what makes fold and
/// unfold continuous.
class GlanceGate extends StatefulWidget {
  const GlanceGate({super.key, required this.child});

  final Widget child;

  @override
  State<GlanceGate> createState() => _GlanceGateState();
}

class _GlanceGateState extends State<GlanceGate> with WidgetsBindingObserver {
  ScreenFormFactorService? _service;
  Timer? _refreshDebounce;
  bool _glanceMounted = false;
  bool _wasActive = false;
  GlanceSurface? _lastSurface;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = ServiceProvider.of(context);
    _service = services.screenFormFactorService;
    final service = _service;
    if (service != null && service.info == null) {
      unawaited(service.initialize());
    }
  }

  @override
  void didChangeMetrics() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 100), () {
      final service = _service;
      if (service != null) unawaited(service.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = _service;
    if (state == AppLifecycleState.resumed && service != null) {
      unawaited(service.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ServiceProvider.of(context);
    final service = services.screenFormFactorService;
    final settings = services.glanceSettings;
    if (service == null || settings == null) return widget.child;

    return ListenableBuilder(
      listenable: Listenable.merge([service, settings]),
      builder: (context, _) {
        final size = MediaQuery.sizeOf(context);
        final surface = classifyGlanceSurface(
          logicalSize: size,
          info: service.info,
          enabled: settings.enabled,
        );
        final active = services.storageService.privacyAccepted &&
            surface != GlanceSurface.none && settings.hasSections;
        if (active) _glanceMounted = true;

        if (kDebugMode && surface != _lastSurface) {
          _lastSurface = surface;
          debugPrint('[glance] surface=$surface info=${service.info}');
        }
        if (active != _wasActive) {
          _wasActive = active;
          if (active) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FocusManager.instance.primaryFocus?.unfocus();
            });
          }
        }

        final full = ExcludeFocus(
          excluding: active,
          child: GlanceActiveScope(active: active, child: widget.child),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: active,
              child: TickerMode(enabled: !active, child: full),
            ),
            if (_glanceMounted)
              Offstage(
                offstage: !active,
                child: TickerMode(
                  enabled: active,
                  child: LiveGlanceShell(
                    surface: surface == GlanceSurface.none
                        ? GlanceSurface.cover
                        : surface,
                    settings: settings,
                    scheduleService: services.scheduleService,
                    assignmentService: services.assignmentService,
                    authService: services.authService,
                    paymentBuilder:
                        settings.isEnabled(GlanceSection.payment)
                            ? (context) => GlancePaymentView(
                                  runtime: services.campusCardService.runtime,
                                )
                            : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
