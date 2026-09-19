import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_providers.dart';
import '../../application/confirmed_disconnect_feedback.dart';
import '../../core/config/debug_mode_controller.dart';
import '../../core/config/debug_mode_features.dart';
import '../../core/config/offline_authorization_banner_controller.dart';
import '../../core/config/payment_code_preferences.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/models/card_models.dart';
import '../../domain/models/offline_models.dart';
import '../../domain/models/payment_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../app/navigation.dart';
import '../app/shell.dart';
import '../icons/geekpay_icons.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';
import 'bill_transaction_screen.dart';
import 'card_manage_screen.dart';
import 'offline_screen.dart';

/// Expanded pass surface from the supplied design: card header, online/offline
/// indicator, live QR or animated result, cardholder data, and recent activity.
final class PaymentCodePage extends ConsumerStatefulWidget {
  const PaymentCodePage({super.key});

  @override
  ConsumerState<PaymentCodePage> createState() => _PaymentCodePageState();
}

class _PaymentCodePageState extends ConsumerState<PaymentCodePage> {
  static const TransactionDateRange _allTransactions = (begin: null, end: null);

  PaymentCodeNotifier get _paymentCodes =>
      ref.read(paymentCodeControllerProvider.notifier);
  bool _offline = false;
  bool _offlineBusy = false;

  // Debug-only timeline in milliseconds, shown under the pass in debug mode:
  // how long the local code took to make, and how long the first frame showing
  // a freshly received code took to arrive. With the request's own time from
  // the controller these say where a slow pass actually spends its seconds.
  int? _offlineGeneratedMs;
  int? _codeShownAfterMs;
  String? _offlinePayload;
  String? _offlineError;
  int? _offlineRemaining;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  Timer? _onlineRetryTimer;
  Timer? _refreshWaitTimer;
  bool _refreshWaiting = false;
  bool _deferOfflineDuringRefresh = true;
  bool _refreshWaitExpired = false;
  PaymentCodeFrame? _refreshPreviousFrame;
  int _refreshWaitRevision = 0;

  bool _scannerOpen = false;
  /// Set once the online code has been ready during this visit: the head start
  /// is for the first code of a visit, not for every refresh.
  bool _onlineCodeWasReady = false;
  bool _visible = false;
  bool _foreground = false;
  bool _active = false;
  int _activityRevision = 0;
  late final ConfirmedDisconnectFeedback _disconnectFeedback;

  bool get _allowAutomaticOffline =>
      !_refreshWaiting || !_deferOfflineDuringRefresh || _refreshWaitExpired;

  void _beginRefreshWait({bool deferOffline = true}) {
    if (!mounted || !_active || _refreshWaiting) return;
    final revision = ++_refreshWaitRevision;
    _refreshWaitTimer?.cancel();
    setState(() {
      _refreshWaiting = true;
      _deferOfflineDuringRefresh = deferOffline;
      _refreshWaitExpired = false;
      _refreshPreviousFrame = ref.read(paymentCodeControllerProvider).frame;
      if (deferOffline) _offline = false;
    });
    _refreshWaitTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_active || revision != _refreshWaitRevision || !_refreshWaiting) return;
      setState(() => _refreshWaitExpired = true);
    });
  }

  void _endRefreshWait({bool rebuild = true}) {
    _refreshWaitTimer?.cancel();
    _refreshWaitTimer = null;
    ++_refreshWaitRevision;
    void clear() {
      _refreshWaiting = false;
      _refreshWaitExpired = false;
      _refreshPreviousFrame = null;
    }
    if (rebuild && mounted) {
      setState(clear);
    } else {
      clear();
    }
  }

  @override
  void initState() {
    super.initState();
    final runtime = ref.read(appRuntimeProvider);
    _foreground = runtime.lifecycle.current == AppLifecycleState.resumed;
    _lifecycleSubscription = runtime.lifecycle.changes.listen((state) {
      _foreground = state == AppLifecycleState.resumed;
      _updateActivity(defer: false);
    });
    _disconnectFeedback = ConfirmedDisconnectFeedback(
      connectivity: runtime.connectivity,
      lifecycle: runtime.lifecycle,
      feedback: runtime.feedback,
    );
    unawaited(_disconnectFeedback.start());
    _connectivitySubscription = ref
        .read(appRuntimeProvider)
        .connectivity
        .changes
        .listen(_handleConnectivity);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Navigator's Overlay disables this mode below opaque routes, including
    // routes in the host navigator. Non-opaque status sheets stay visible.
    _visible = TickerMode.of(context);
    _updateActivity(defer: true);
  }

  void _updateActivity({required bool defer}) {
    if (!mounted) return;
    final next = _visible && _foreground && !_scannerOpen;
    if (next == _active) return;
    if (defer) {
      _active = next;
    } else {
      setState(() => _active = next);
    }
    if (!next) {
      _onlineRetryTimer?.cancel();
      _endRefreshWait(rebuild: false);
    }
    final revision = ++_activityRevision;
    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_applyActivity(revision));
      });
    } else {
      // Backgrounding may stop frame delivery, so release resources now.
      unawaited(_applyActivity(revision));
    }
  }

  Future<void> _applyActivity(int revision) async {
    if (!mounted || revision != _activityRevision) return;
    if (_active) {
      await _paymentCodes.enter(online: !ref.read(manualOfflineModeProvider));
    } else {
      await _paymentCodes.leave();
    }
  }

  @override
  void dispose() {
    _endRefreshWait(rebuild: false);
    unawaited(_disconnectFeedback.dispose());
    unawaited(_lifecycleSubscription?.cancel());
    _onlineRetryTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  void _handleConnectivity(bool online) {
    if (!mounted || !_active) return;
    final card = ref.read(cardControllerProvider).valueOrNull;
    if (card == null) return;
    // Manual offline mode promises a local-only session: no renewal, no online
    // code. Only the switch ends it.
    if (ref.read(manualOfflineModeProvider)) return;
    if (online) {
      unawaited(
        ref
            .read(offlineAuthorizationProvider(card.id).notifier)
            .maintain(force: false),
      );
    }
    if (!online) {
      _paymentCodes.markDisconnected();
    } else {
      final payment = ref.read(paymentCodeControllerProvider);
      if (payment.phase == PaymentCodePhase.initializing ||
          payment.connectionState == PaymentConnectionState.online) {
        return;
      }
      unawaited(_paymentCodes.restart());
    }
  }

  Future<void> _refreshOnline() async {
    await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.selection);
    if (!mounted || !_active) return;
    _beginRefreshWait();
    await ref.read(paymentCodeControllerProvider.notifier).refresh();
  }

  Future<void> _setOfflineMode(CampusCard card, bool enabled) async {
    await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.selection);
    if (!mounted) return;
    _endRefreshWait();
    ref.read(manualOfflineModeProvider.notifier).setEnabled(enabled);
    if (!enabled) {
      // The local code stays on screen until a fresh online one is ready; only
      // the failure note goes away.
      setState(() {
        _offlineError = null;
      });
      if (_active) await _paymentCodes.restart();
      return;
    }
    if (_active) await _paymentCodes.enter(online: false);
    if (!mounted) return;
    await _generateOffline(card, switching: true);
    if (!mounted) return;
    final authorization = ref
        .read(offlineAuthorizationProvider(card.id))
        .valueOrNull
        ?.state;
    final usable = authorization == OfflineAuthorizationState.active ||
        authorization == OfflineAuthorizationState.renewalDue;
    if (_offlinePayload == null && !usable) {
      // Nothing to generate from — no offline authorization, or one that has
      // expired — so the mode cannot take effect: the pass goes back online and
      // the activation banner takes over. A code that failed for any other
      // reason keeps the offline surface and its retry.
      ref.read(manualOfflineModeProvider.notifier).setEnabled(false);
      setState(() {
        _offline = false;
        _offlinePayload = null;
        _offlineRemaining = null;
      });
      if (_active) await _paymentCodes.restart();
    }
  }

  Future<void> _generateOffline(
    CampusCard card, {
    bool switching = false,
    bool automatic = false,
  }) async {
    if (_offlineBusy || !mounted || !_active) return;
    if (automatic && (!_allowAutomaticOffline || _preferReadyOnlineCode())) return;
    final revision = _activityRevision;
    setState(() {
      _offlineBusy = true;
      _offlineError = null;
      if (switching) _offline = true;
    });
    try {
      final controller = ref.read(
        offlineAuthorizationProvider(card.id).notifier,
      );
      // generate() validates the grant itself and publishes the grant it
      // consumed, so neither a pre-check nor a post-check reads secure storage
      // here: the refresh stays one pass over the keystore.
      final localWatch = Stopwatch()..start();
      final code = await controller.generate();
      localWatch.stop();
      if (!mounted || !_active || revision != _activityRevision) return;
      // Online generation may finish while local signing/storage is pending.
      if (automatic && (!_allowAutomaticOffline || _preferReadyOnlineCode())) return;
      setState(() {
        _offline = true;
        _offlineGeneratedMs = localWatch.elapsedMilliseconds;
        _offlinePayload = code.payload;
        _offlineRemaining = ref
            .read(offlineAuthorizationProvider(card.id))
            .valueOrNull
            ?.authorization
            ?.remaining;
      });
    } catch (error) {
      if (!mounted || !_active || revision != _activityRevision) return;
      if (automatic && (!_allowAutomaticOffline || _preferReadyOnlineCode())) {
        return;
      }
      final authorizationRequired = _isAuthorizationUnusable(error);
      setState(() {
        _offlineError =
            authorizationRequired ? null : GpStateView.safeUiError(error);
        _offlinePayload = null;
        _offlineRemaining = null;
        // A failed local code keeps the surface the user asked for: only the
        // automatic fallback hands the pass back to the online code.
        _offline = ref.read(manualOfflineModeProvider);
      });
      if (authorizationRequired) {
        ref.invalidate(offlineAuthorizationProvider(card.id));
        // No usable grant and no renewal available locally: the mode cannot keep
        // its promise, so the pass returns to the online code.
        if (ref.read(manualOfflineModeProvider)) {
          await _setOfflineMode(card, false);
        }
      } else {
        await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _offlineBusy = false;
          if (_offlinePayload == null) {
            _offline = ref.read(manualOfflineModeProvider);
          }
        });
      }
    }
  }

  /// Whether the local code cannot be produced because the *grant* is unusable —
  /// absent, expired or spent — as opposed to a failure of this attempt. The
  /// service says which by the failure it raises.
  static bool _isAuthorizationUnusable(Object error) {
    if (error is! AppFailure) return false;
    return switch (error.kind) {
      FailureKind.credentialMissing ||
      FailureKind.offlineAuthorizationExpired ||
      FailureKind.offlineQuotaExhausted =>
        true,
      _ =>
        error.code == 'OFFLINE_DEVICE_CODE_MISSING' ||
            error.code == 'OFFLINE_CREDENTIAL_MISSING',
    };
  }

  bool _preferReadyOnlineCode() {
    if (ref.read(manualOfflineModeProvider)) return false;
    return _onlineCodeReady(ref.read(paymentCodeControllerProvider));
  }

  bool _onlineCodeReady(PaymentCodeViewState payment) =>
      payment.phase == PaymentCodePhase.succeeded ||
      (payment.frame != null &&
          (!_refreshWaiting || !identical(payment.frame, _refreshPreviousFrame)) &&
          payment.connectionState == PaymentConnectionState.online &&
          (payment.phase == PaymentCodePhase.displaying ||
              payment.phase == PaymentCodePhase.polling));

  /// Debug-only: how long the pass takes to paint a code it has just received.
  /// The frame after the state change is the first one that can show it, so it
  /// is measured from the callback rather than from the state itself.
  void _measureCodeShown() {
    if (!debugModeFeaturesAvailable || !ref.read(debugModeProvider)) return;
    final received = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(
        () => _codeShownAfterMs =
            DateTime.now().difference(received).inMilliseconds,
      );
    });
  }

  /// Whether an online attempt is still on its way — as opposed to having
  /// produced a code, failed, or been stopped by the account state.
  bool _onlineInFlight(PaymentCodeViewState payment) =>
      payment.phase == PaymentCodePhase.idle ||
      payment.phase == PaymentCodePhase.initializing ||
      payment.phase == PaymentCodePhase.refreshing ||
      payment.phase == PaymentCodePhase.stopped;

  Future<void>? _pageRefresh;

  Future<void> _refreshAll() {
    final active = _pageRefresh;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performPageRefresh().whenComplete(() {
      if (identical(_pageRefresh, operation)) _pageRefresh = null;
    });
    _pageRefresh = operation;
    return operation;
  }

  Future<void> _performPageRefresh() async {
    final history = ref.read(accountHistoryRefreshProvider);
    final cards = ref.read(cardControllerProvider.notifier);
    final codes = ref.read(paymentCodeControllerProvider.notifier);
    final before = ref.read(paymentCodeControllerProvider).frame;
    history.hold();
    try {
      if (!ref.read(manualOfflineModeProvider)) {
        _beginRefreshWait();
        await codes.refresh();
      }
      if (!mounted || history.isDisposed) return;
      final after = ref.read(paymentCodeControllerProvider).frame;
      if (identical(before, after) || after?.balance == null) {
        try { await cards.refresh(); } catch (_) { /* Keep the last balance. */ }
      }
    } finally {
      await history.releaseAndRefresh();
    }
  }

  Future<void> _refreshAfterPayment() async {
    final cardRefresh = ref.read(cardControllerProvider.notifier).refresh();
    final historyRefresh = ref.read(accountHistoryRefreshProvider).refresh(fresh: true);
    await Future.wait<void>([
      historyRefresh,
      cardRefresh.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardControllerProvider);
    final card = cardAsync.valueOrNull;
    // Starting/finishing a pending poll changes no visible content.
    ref.watch(
      paymentCodeControllerProvider.select(
        (value) => (
          value.phase == PaymentCodePhase.polling
              ? PaymentCodePhase.displaying
              : value.phase,
          value.generation,
          value.frame,
          value.result,
          value.message,
          value.connectionState,
          value.requestLatency,
        ),
      ),
    );
    final payment = ref.read(paymentCodeControllerProvider);
    // A same-account session renewal replaces the controller without changing
    // this page's visibility. Start the replacement after the build completes.
    if (_active && payment.phase == PaymentCodePhase.idle) {
      final revision = _activityRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _active &&
            revision == _activityRevision &&
            ref.read(paymentCodeControllerProvider).phase ==
                PaymentCodePhase.idle) {
          unawaited(_applyActivity(revision));
        }
      });
    }
    final transactions = ref.watch(transactionFeedProvider(_allTransactions));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final manualOffline = ref.watch(manualOfflineModeProvider);
    // Null while the stored preference is being read: the head start waits for
    // the answer rather than spending a grant the user turned off.
    final offlineCodeFirst =
        ref.watch(offlineCodeFirstProvider).valueOrNull;
    final debugMode =
        debugModeFeaturesAvailable && ref.watch(debugModeProvider);
    final offlineAuthorization =
        card == null ? null : ref.watch(offlineAuthorizationProvider(card.id));
    final bannerDismissed = ref.watch(
      offlineAuthorizationBannerDismissedProvider,
    );
    final authorizationState = offlineAuthorization?.valueOrNull?.state;
    final canGenerateOffline =
        authorizationState == OfflineAuthorizationState.active ||
            authorizationState == OfflineAuthorizationState.renewalDue;
    final showOfflineAuthorizationBanner = card != null &&
        bannerDismissed.valueOrNull == false &&
        (authorizationState == OfflineAuthorizationState.missingCredential ||
            authorizationState == OfflineAuthorizationState.unavailable);

    ref.listen(paymentCodeControllerProvider, (previous, next) {
      if (next.phase == PaymentCodePhase.initializing && !manualOffline) {
        // Startup and recovery keep the existing offline-first behavior, but
        // still report a delayed online response after the same threshold.
        _beginRefreshWait(deferOffline: false);
      }
      if (next.phase == PaymentCodePhase.refreshing && previous?.frame != null &&
          !_offline && !manualOffline) {
        _beginRefreshWait();
      }
      if (_refreshWaiting && (next.phase == PaymentCodePhase.idle ||
          next.phase == PaymentCodePhase.stopped ||
          next.phase == PaymentCodePhase.activationRequired ||
          next.phase == PaymentCodePhase.failed ||
          next.phase == PaymentCodePhase.switchingOffline ||
          next.phase == PaymentCodePhase.succeeded ||
          next.frame != null && !identical(next.frame, _refreshPreviousFrame))) {
        _endRefreshWait();
      }
      if (next.phase == PaymentCodePhase.initializing && _offlineError != null) {
        setState(() => _offlineError = null);
      }
      if (card == null) {
        return;
      }
      if (_onlineCodeReady(next) && !manualOffline) {
        _onlineRetryTimer?.cancel();
        if (_offline) setState(() => _offline = false);
        _measureCodeShown();
      }
      if (next.phase == PaymentCodePhase.succeeded &&
          previous?.phase != PaymentCodePhase.succeeded) {
        unawaited(_refreshAfterPayment());
      }
      final shouldFallback = next.phase == PaymentCodePhase.switchingOffline ||
          (next.phase == PaymentCodePhase.failed &&
              next.connectionState != PaymentConnectionState.online);
      if (shouldFallback) {
        if (_active && canGenerateOffline &&
            !_offline && !_offlineBusy && _offlineError == null) {
          unawaited(_generateOffline(card, switching: true, automatic: true));
        }
        _scheduleOnlineRetry();
      }
    });

    final onlineFailed = payment.phase == PaymentCodePhase.switchingOffline ||
        (payment.phase == PaymentCodePhase.failed &&
            payment.connectionState != PaymentConnectionState.online);
    if (onlineFailed && _onlineRetryTimer?.isActive != true) {
      _scheduleOnlineRetry();
    }
    if (_onlineCodeReady(payment)) _onlineCodeWasReady = true;
    // 离线码优先 turns the local code into a head start: it is produced while the
    // online code is on its way and handed over the moment that one is ready.
    // Off, the local code is only ever a fallback — it appears when the online
    // attempt failed, or when the user asked for offline. Either way a grant is
    // never spent twice for the same visit: once the online code has been ready,
    // a refresh does not start another local one.
    final offlineHeadStart = offlineCodeFirst == true &&
        !_onlineCodeWasReady &&
        !_onlineCodeReady(payment);
    // A slow online answer also lets the local code through once the grace
    // window has passed (`_refreshWaitExpired`), which is the degraded path the
    // pass and the status sheet label. Both ways of showing the local code early
    // are the same promise the user made when they turned 离线码优先 on, so off
    // means off: no head start, no degradation — failures and manual mode are
    // what is left.
    final offlineDegraded = offlineCodeFirst == true && _refreshWaitExpired;
    if (_active &&
        card != null &&
        canGenerateOffline &&
        (manualOffline ||
            _allowAutomaticOffline &&
                (onlineFailed || offlineHeadStart || offlineDegraded)) &&
        !_offline &&
        !_offlineBusy &&
        _offlineError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active) {
          unawaited(_generateOffline(card, switching: true, automatic: true));
        }
      });
    }

    final transactionPage = transactions.valueOrNull;
    final realTransactionCount = transactionPage?.items
        .where((record) => !record.id.startsWith('DEBUG-'))
        .length;
    if (_active &&
        transactionPage != null &&
        transactionPage.hasMore &&
        (realTransactionCount ?? 0) < 25) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_active) return;
        unawaited(
          ref
              .read(transactionFeedProvider(_allTransactions).notifier)
              .loadMore(),
        );
      });
    }

    final page = Scaffold(
      key: const Key('payment-code-page'),
      body: _scannerOpen
          ? const ColoredBox(color: Colors.black)
          : AppleWalletPage(
              child: ApplePinnedHeaderLayout(
                title: '付款码',
                leading: CampusCardHeaderAction(
                  id: 'back',
                  sfSymbol: 'chevron.left',
                  icon: GpPlatformIcons.back(context),
                  label: '返回',
                  onPressed: () => popCampusCard(context),
                ),
                actions: [
                  CampusCardHeaderAction(
                    id: 'scan',
                    sfSymbol: 'qrcode.viewfinder',
                    label: '扫一扫',
                    onPressed: _openScanner,
                    icon: GpPlatformIcons.scan(context),
                    iconSize: 25,
                  ),
                  CampusCardHeaderAction(
                    id: 'info',
                    sfSymbol: 'info.circle',
                    key: const Key('payment-header-info'),
                    label: '卡片信息',
                    onPressed: () => unawaited(pushCampusCardPage<void>(context, builder: (_) => const CardManageScreen())),
                    icon: GpPlatformIcons.info(context),
                  ),
                ],
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    EcardSliverRefreshControl(
                      onRefresh: _refreshAll,
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        18,
                        ApplePinnedHeaderLayout.contentTop,
                        18,
                        0,
                      ),
                      sliver: SliverList.list(
                        children: [
                          if (card != null)
                            _ExpandedPaymentPass(
                              card: card,
                              payment: payment,
                              // What the pass shows, and what a tap on the code
                              // means, follows the mode the user chose — not only
                              // the automatic fallback, or a failed local refresh
                              // would hand the surface back to the online code.
                              offline: manualOffline || _offline,
                              // Offline code on screen while the online one is
                              // still being fetched: the pass says so.
                              waitingForOnlineCode: _offline &&
                                  !manualOffline &&
                                  _onlineInFlight(payment),
                              refreshLoading: _refreshWaiting && _deferOfflineDuringRefresh && (!_refreshWaitExpired || !_offline),
                              refreshDegraded: _refreshWaiting && _refreshWaitExpired,
                              offlineBusy: _offlineBusy,
                              offlinePayload: _offlinePayload,
                              offlineRemaining: _offlineRemaining,
                              offlineError: _offlineError,
                              reduceMotion: reduceMotion,
                              active: _active,
                              debugMode: debugMode,
                              offlineGeneratedMs: _offlineGeneratedMs,
                              codeShownAfterMs: _codeShownAfterMs,
                              onShowStatus: () => unawaited(
                                _showStatusSheet(
                                  card: card,
                                  payment: payment,
                                  manualOffline: manualOffline,
                                  canToggleOffline: canGenerateOffline,
                                ),
                              ),
                              onRefreshOnline: _refreshOnline,
                              onRefreshOffline: () =>
                                  unawaited(_generateOffline(card)),
                              onActivateOnline: () => unawaited(
                                ref
                                    .read(
                                      paymentCodeControllerProvider.notifier,
                                    )
                                    .activateAndRestart(),
                              ),
                            )
                          else
                            switch (cardAsync) {
                              AsyncError(:final error) => GpStateView.error(
                                  error,
                                  onRetry: () => unawaited(
                                    ref
                                        .read(cardControllerProvider.notifier)
                                        .refresh(),
                                  ),
                                ),
                              AsyncData() => const GpStateView(
                                  icon: GpIcons.card,
                                  title: '绑定卡片',
                                  description: '当前卡片状态无法付款',
                                ),
                              _ => const _PaymentCardLoading(),
                            },
                          if (debugMode && card != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => ref
                                    .read(
                                      paymentCodeControllerProvider.notifier,
                                    )
                                    .debugComplete(),
                                icon: Icon(GpPlatformIcons.debug(context)),
                                label: const Text('调试：触发支付成功'),
                              ),
                            ),
                          ],
                          if (showOfflineAuthorizationBanner) ...[
                            const SizedBox(height: 12),
                            _OfflineAuthorizationBanner(
                              onActivate: () =>
                                  unawaited(pushCampusCardPage<void>(context, builder: (_) => const OfflineAuthorizationScreen())),
                              onDismiss: () async {
                                await ref
                                    .read(
                                      offlineAuthorizationBannerDismissedProvider
                                          .notifier,
                                    )
                                    .dismiss();
                              },
                            ),
                          ],
                          if (_offlineError != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.gpColors.danger.withValues(
                                  alpha: 0.09,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: Text(_offlineError!)),
                                  TextButton(
                                    onPressed: () => unawaited(
                                      pushCampusCardPage<void>(
                                        context,
                                        builder: (_) =>
                                            const OfflineAuthorizationScreen(),
                                      ),
                                    ),
                                    child: const Text('离线授权'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 30),
                          Text(
                            '最近使用',
                            style: TextStyle(
                              color: context.gpColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 52),
                      sliver: switch (transactions) {
                        AsyncData(:final value) => TransactionList(
                            items: value.items
                                .where(
                                  (record) => !record.id.startsWith('DEBUG-'),
                                )
                                .take(25)
                                .toList(),
                            onTap: (record) => unawaited(
                              pushCampusCardPage<void>(
                                context,
                                builder: (_) => BillTransactionScreen(
                                  transactionId: record.id,
                                ),
                              ),
                            ),
                          ),
                        AsyncError(:final error) => SliverToBoxAdapter(
                            child: GpStateView.error(
                              error,
                              onRetry: () => ref.invalidate(
                                transactionFeedProvider(_allTransactions),
                              ),
                            ),
                          ),
                        _ => SliverToBoxAdapter(
                            child: Container(
                              height: 128,
                              decoration: BoxDecoration(
                                color: context.gpColors.surface,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Center(
                                child: CupertinoActivityIndicator(
                                  color: context.gpColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
    return TickerMode(enabled: _active, child: page);
  }

  Future<void> _openScanner() async {
    if (_scannerOpen) return;
    setState(() => _scannerOpen = true);
    _updateActivity(defer: false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      await openGpScanner(context);
    } finally {
      if (mounted) {
        setState(() => _scannerOpen = false);
        _updateActivity(defer: false);
      }
    }
  }

  void _scheduleOnlineRetry() {
    if (!_active || ref.read(manualOfflineModeProvider)) return;
    _onlineRetryTimer?.cancel();
    _onlineRetryTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_active || ref.read(manualOfflineModeProvider)) return;
      unawaited(_paymentCodes.restart());
    });
  }

  Future<void> _showStatusSheet({
    required CampusCard card,
    required PaymentCodeViewState payment,
    required bool manualOffline,
    required bool canToggleOffline,
  }) async {
    final stateLabel = _refreshWaiting &&
            _refreshWaitExpired &&
            payment.connectionState != PaymentConnectionState.disconnected
        ? '在线码响应较慢，已降级'
        : switch (payment.connectionState) {
      PaymentConnectionState.online => '网络正常',
      PaymentConnectionState.disconnected => '网络已断开',
      PaymentConnectionState.apiError => '服务响应异常',
      PaymentConnectionState.unknown => '正在检测',
    };
    final latency = payment.requestLatency == null
        ? '--'
        : '${payment.requestLatency!.inMilliseconds} ms';
    final selected = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppleSection(
              children: [
                AppleListRow(label: '在线状态', value: stateLabel),
                AppleListRow(label: '当前延迟', value: latency),
                AppleListRow(
                  label: '离线付款码',
                  verticalPadding: 4,
                  trailing: Switch.adaptive(
                    // The switch is the user's mode, not "an offline code happens
                    // to be on screen": it moves only when the mode moves, and it
                    // is inert while there is no usable grant to generate from.
                    value: manualOffline,
                    onChanged: canToggleOffline
                        ? (value) => Navigator.pop(sheetContext, value)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              !canToggleOffline
                  ? '没有可用的离线授权：请先开通或联网续期，之后才能使用离线码。'
                  : manualOffline
                      ? '离线模式：只用本机生成的付款码，本地即时刷新，不发起网络请求。'
                      : '开启后只用本机生成的离线码（每次刷新消耗一次授权次数），直到关闭或退出 App。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.gpColors.textSecondary),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) await _setOfflineMode(card, selected);
  }
}

final class _PaymentCardLoading extends StatelessWidget {
  const _PaymentCardLoading();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 746 / 984,
      child: DecoratedBox(
        key: const Key('payment-card-loading'),
        decoration: BoxDecoration(
          color: context.gpColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(child: _PaymentCodeActivityIndicator()),
      ),
    );
  }
}

final class _PaymentCodeActivityIndicator extends StatelessWidget {
  const _PaymentCodeActivityIndicator({super.key, this.radius = 10});

  final double radius;

  @override
  Widget build(BuildContext context) => CupertinoActivityIndicator(
        color: GpTokens.campusRed,
        radius: radius,
      );
}

final class _OfflineAuthorizationBanner extends StatelessWidget {
  const _OfflineAuthorizationBanner({
    required this.onActivate,
    required this.onDismiss,
  });

  final VoidCallback onActivate;
  final Future<void> Function() onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '开通离线付款码，以便在网络不稳定时继续支付。',
      child: Container(
        key: const Key('offline-authorization-banner'),
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        decoration: BoxDecoration(
          color: context.gpColors.warning.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.gpColors.warning.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '开通离线付款码，以便在网络不稳定时继续支付。',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            TextButton(onPressed: onActivate, child: const Text('立即开通')),
            IconButton(
              key: const Key('offline-authorization-banner-close'),
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              onPressed: () => unawaited(onDismiss()),
              icon: Icon(GpPlatformIcons.close(context), size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ExpandedPaymentPass extends StatelessWidget {
  const _ExpandedPaymentPass({
    required this.card,
    required this.payment,
    required this.offline,
    required this.waitingForOnlineCode,
    required this.offlineBusy,
    required this.offlinePayload,
    required this.offlineRemaining,
    required this.offlineError,
    required this.reduceMotion,
    required this.active,
    this.debugMode = false,
    this.offlineGeneratedMs,
    this.codeShownAfterMs,
    required this.onShowStatus,
    required this.onRefreshOnline,
    required this.onRefreshOffline,
    required this.onActivateOnline,
    this.refreshLoading = false,
    this.refreshDegraded = false,
  });

  final bool refreshLoading;
  final bool refreshDegraded;
  final CampusCard card;
  final PaymentCodeViewState payment;
  final bool offline;
  final bool waitingForOnlineCode;
  final bool offlineBusy;
  final String? offlinePayload;
  final int? offlineRemaining;
  final String? offlineError;
  final bool reduceMotion;
  final bool active;

  /// Debug builds only: show where the last code's seconds went, so a slow pass
  /// is measured where it is felt instead of guessed at: the request, the local
  /// code that led it, and the frame that finally showed the result.
  final bool debugMode;
  final int? offlineGeneratedMs;
  final int? codeShownAfterMs;
  final VoidCallback onShowStatus;
  final VoidCallback onRefreshOnline;
  final VoidCallback onRefreshOffline;
  final VoidCallback onActivateOnline;

  @override
  Widget build(BuildContext context) {
    final succeeded = !offline && payment.phase == PaymentCodePhase.succeeded;
    final result = payment.result;
    final payload = offline ? offlinePayload : payment.frame?.qrPayload;
    final loading = refreshLoading || (offline
        ? offlineBusy
        : payment.phase == PaymentCodePhase.initializing ||
            payment.phase == PaymentCodePhase.refreshing ||
            payment.phase == PaymentCodePhase.stopped);
    final showCodeMetadata = !refreshLoading && (offline ||
        payment.phase == PaymentCodePhase.displaying ||
        payment.phase == PaymentCodePhase.refreshing ||
        payment.phase == PaymentCodePhase.polling);
    final degraded = refreshDegraded && payment.connectionState != PaymentConnectionState.disconnected;
    final ownerName = card.detailsAvailable
        // The feature's copy is Chinese, and the host resolves its own locale
        // (English by default) independently of the device: shorten the name to
        // the Chinese part the way the Chinese UI does.
        ? cardholderDisplayName(card.ownerName, languageCode: 'zh')
        : 'eCard';

    return Hero(
      tag: 'campus-card',
      child: Material(
        key: const Key('expanded-payment-pass'),
        color: GpTokens.cardCanvas,
        elevation: 5,
        shadowColor: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 746 / 984,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final headerHeight = width * 126 / 746;
              final statusSize = _scaled(width, 0.128, 47, 67);
              final qrSize = width * 0.668;
              final qrTop = width * 0.06;
              final metadataTop = width * 0.75;
              final horizontalPadding = width * 0.049;
              final detailsBottom = width * 0.055;
              final nameSize = _scaled(width, 0.05, 20, 27);
              final numberSize = _scaled(width, 0.034, 15, 19);
              final balanceSize = _scaled(width, 0.061, 22, 33);
              final metadataTitleSize = _scaled(width, 0.037, 15, 20);
              final metadataValueSize = _scaled(width, 0.032, 13, 17);

              return ColoredBox(
                color: GpTokens.cardCanvas,
                child: Column(
                  children: [
                    SizedBox(
                      height: headerHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            GeekPayAssets.cardTop,
                            gaplessPlayback: true,
                            key: const Key('payment-card-top-art'),
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                          Positioned(
                            right: width * 0.043,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Transform.translate(
                                key: const Key(
                                  'payment-online-status-indicator',
                                ),
                                offset: Offset(0, statusSize * 0.045),
                                child: Semantics(
                                  button: true,
                                  label: '在线状态',
                                  child: GestureDetector(
                                    onTap: onShowStatus,
                                    behavior: HitTestBehavior.opaque,
                                    child: SizedBox.square(
                                      dimension: statusSize,
                                      child: !degraded && payment.connectionState ==
                                              PaymentConnectionState.unknown
                                          ? const CupertinoActivityIndicator(
                                              color: Colors.white,
                                            )
                                          : Image.asset(
                                              degraded ? GeekPayAssets.warningOnline : switch (payment.connectionState) {
                                                PaymentConnectionState.online =>
                                                  GeekPayAssets.online,
                                                PaymentConnectionState
                                                      .disconnected =>
                                                  GeekPayAssets.offline,
                                                PaymentConnectionState
                                                      .apiError =>
                                                  GeekPayAssets.warningOnline,
                                                PaymentConnectionState
                                                      .unknown =>
                                                  GeekPayAssets.online,
                                              },
                                              width: statusSize,
                                              height: statusSize,
                                              filterQuality: FilterQuality.high,
                                              gaplessPlayback: true,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: width * 337 / 744,
                            child: Image.asset(
                              GeekPayAssets.cardBottom,
                              gaplessPlayback: true,
                              key: const Key('payment-card-bottom-art'),
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          Positioned(
                            top: qrTop,
                            left: (width - qrSize) / 2,
                            width: qrSize,
                            height: qrSize,
                            child: RepaintBoundary(
                              child: AnimatedSwitcher(
                                duration: reduceMotion || !active
                                    ? Duration.zero
                                    : const Duration(milliseconds: 320),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: succeeded
                                    ? _PaymentSuccess(
                                        key: const ValueKey('success'),
                                        result: result,
                                        reduceMotion: reduceMotion,
                                        onRefresh: onRefreshOnline,
                                      )
                                    : loading
                                        ? const _PaymentCodeActivityIndicator(
                                            key: ValueKey(
                                              'payment-code-refresh-spinner',
                                            ),
                                            radius: 15,
                                          )
                                        : payment.phase ==
                                                PaymentCodePhase
                                                    .activationRequired
                                            ? _ActivationRequired(
                                                key: const ValueKey('activate'),
                                                onActivate: onActivateOnline,
                                              )
                                            : (offline
                                                      ? offlineError != null
                                                      : payment.phase ==
                                                            PaymentCodePhase
                                                                .failed)
                                                ? _CodeFailure(
                                                    key: const ValueKey(
                                                      'failed',
                                                    ),
                                                    message: offline
                                                        ? offlineError
                                                        : payment.message,
                                                    onRetry: offline
                                                        ? onRefreshOffline
                                                        : onRefreshOnline,
                                                  )
                                                : payload == null
                                                    ? const _PaymentCodeActivityIndicator(
                                                        key: ValueKey(
                                                          'payment-code-pending-spinner',
                                                        ),
                                                      )
                                                    : _QrCode(
                                                        key: ValueKey(
                                                          offline
                                                              ? payload
                                                              : payment
                                                                  .generation,
                                                        ),
                                                        payload: payload,
                                                        binaryPayload:
                                                            offline ||
                                                                (payment.frame
                                                                        ?.rawQrCode
                                                                        .startsWith(
                                                                      '5638',
                                                                    ) ??
                                                                    false),
                                                        size: qrSize,
                                                        onTap: offline
                                                            ? onRefreshOffline
                                                            : onRefreshOnline,
                                                      ),
                              ),
                            ),
                          ),
                          if (!succeeded && showCodeMetadata)
                            Positioned(
                              top: metadataTop,
                              left: horizontalPadding,
                              right: horizontalPadding,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    offline
                                        ? '离线付款码'
                                        : '在线付款码',
                                    style: TextStyle(
                                      color: GpTokens.campusRed,
                                      fontSize: metadataTitleSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (!offline ||
                                      offlineRemaining != null ||
                                      waitingForOnlineCode) ...[
                                    SizedBox(height: width * 0.004),
                                    if (offline)
                                      Text(
                                        waitingForOnlineCode
                                            ? '在线码加载中'
                                            : '剩余次数: $offlineRemaining',
                                        style: TextStyle(
                                          color: GpTokens.campusRed
                                              .withValues(alpha: 0.62),
                                          fontSize: metadataValueSize,
                                        ),
                                      )
                                    else
                                      _CodeCountdown(
                                        generation: payment.generation,
                                        active: active,
                                        style: TextStyle(
                                          color: GpTokens.campusRed
                                              .withValues(alpha: 0.62),
                                          fontSize: metadataValueSize,
                                        ),
                                      ),
                                  ],
                                  if (debugMode &&
                                      !offline &&
                                      payment.requestLatency != null) ...[
                                    SizedBox(height: width * 0.004),
                                    Text(
                                      'request ${payment.requestLatency!.inMilliseconds}ms'
                                      '${offlineGeneratedMs == null ? '' : ' · local ${offlineGeneratedMs}ms'}'
                                      '${codeShownAfterMs == null ? '' : ' · frame ${codeShownAfterMs}ms'}',
                                      style: TextStyle(
                                        color: GpTokens.campusRed
                                            .withValues(alpha: 0.38),
                                        fontSize: metadataValueSize * 0.85,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          Positioned(
                            left: horizontalPadding,
                            right: horizontalPadding,
                            bottom: detailsBottom,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ownerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFF303034),
                                          fontSize: nameSize,
                                          fontWeight: FontWeight.w600,
                                          height: 1.1,
                                        ),
                                      ),
                                      SizedBox(height: width * 0.006),
                                      Text(
                                        'No. ${card.id}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFF303034),
                                          fontSize: numberSize,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: width * 0.025),
                                Text(
                                  card.detailsAvailable
                                      ? formatMoneyFen(
                                          card.balance.value,
                                        )
                                      : '--',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: const Color(0xFF303034),
                                    fontSize: balanceSize,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _CodeCountdown extends StatefulWidget {
  const _CodeCountdown({
    required this.generation,
    required this.active,
    required this.style,
  });
  final int generation;
  final bool active;
  final TextStyle style;

  @override
  State<_CodeCountdown> createState() => _CodeCountdownState();
}

class _CodeCountdownState extends State<_CodeCountdown> {
  Timer? _timer;
  int _remaining = 30;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(_CodeCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _remaining = 30;
      _startTimer();
    } else if (oldWidget.active != widget.active) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!widget.active || _remaining <= 1) return;
    final initial = _remaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = (initial - timer.tick).clamp(1, 30);
      setState(() => _remaining = next);
      if (_remaining == 1) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: RepaintBoundary(
          child: Text(
            '$_remaining秒后刷新',
            textAlign: TextAlign.center,
            style: widget.style,
          ),
        ),
      );
}

double _scaled(double width, double ratio, double minimum, double maximum) =>
    (width * ratio).clamp(minimum, maximum).toDouble();

final class _QrCode extends StatefulWidget {
  const _QrCode({
    super.key,
    required this.payload,
    required this.binaryPayload,
    required this.size,
    required this.onTap,
  });

  final String payload;
  final bool binaryPayload;
  final double size;
  final VoidCallback onTap;

  @override
  State<_QrCode> createState() => _QrCodeState();
}

class _QrCodeState extends State<_QrCode> {
  late Widget _image;

  @override
  void initState() {
    super.initState();
    _image = _createImage();
  }

  @override
  void didUpdateWidget(_QrCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload ||
        oldWidget.binaryPayload != widget.binaryPayload) {
      _image = _createImage();
    }
  }

  Widget _createImage() => widget.binaryPayload
      ? QrImageView.withQr(
          qr: QrCode.fromUint8List(
            data: Uint8List.fromList(latin1.encode(widget.payload)),
            errorCorrectLevel: QrErrorCorrectLevel.L,
          ),
          padding: EdgeInsets.zero,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: GpTokens.campusRed,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: GpTokens.campusRed,
          ),
          backgroundColor: GpTokens.cardCanvas,
        )
      : QrImageView(
          data: widget.payload,
          version: QrVersions.auto,
          padding: EdgeInsets.zero,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: GpTokens.campusRed,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: GpTokens.campusRed,
          ),
          backgroundColor: GpTokens.cardCanvas,
        );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '轻触二维码刷新',
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          key: const Key('payment-code-qr'),
          width: widget.size,
          height: widget.size,
          color: GpTokens.cardCanvas,
          padding: EdgeInsets.all(widget.size * 0.035),
          child: _image,
        ),
      ),
    );
  }
}

final class _PaymentSuccess extends ConsumerWidget {
  const _PaymentSuccess({
    super.key,
    required this.result,
    required this.reduceMotion,
    required this.onRefresh,
  });

  final TransactionResult? result;
  final bool reduceMotion;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: '轻触二维码刷新',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRefresh,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSuccessCheck(
              size: 88,
              color: GpTokens.campusRed,
              reduceMotion: reduceMotion,
              feedback: ref.read(appRuntimeProvider).feedback,
            ),
            const SizedBox(height: 16),
            Text(
              result == null
                  ? '支付成功'
                  : formatMoneyFen(result!.amount.value),
              style: const TextStyle(
                color: GpTokens.campusRed,
                fontSize: 35,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              result?.merchantName?.trim().isNotEmpty == true
                  ? result!.merchantName!
                  : '支付成功',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: GpTokens.campusRed.withValues(alpha: 0.62),
                fontSize: 14,
              ),
            ),
            if (result != null) ...[
              const SizedBox(height: 3),
              Text(
                DateFormat('yyyy-MM-dd HH:mm:ss').format(
                  (result!.tradeAt ?? result!.confirmedLocallyAt).toLocal(),
                ),
                style: TextStyle(
                  color: GpTokens.campusRed.withValues(alpha: 0.62),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _ActivationRequired extends StatelessWidget {
  const _ActivationRequired({super.key, required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          GpPlatformIcons.paymentCode(context),
          size: 68,
          color: context.gpColors.action,
        ),
        const SizedBox(height: 16),
        const Text('需要先开通付款码'),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: onActivate,
          style: FilledButton.styleFrom(
            backgroundColor: context.gpColors.action,
            shape: const StadiumBorder(),
          ),
          child: const Text('立即开通'),
        ),
      ],
    );
  }
}

final class _CodeFailure extends StatelessWidget {
  const _CodeFailure({super.key, this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message ?? '付款码生成失败'),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
