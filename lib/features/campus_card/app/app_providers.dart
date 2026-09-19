import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/account_history_refresh.dart';
import '../application/payment_code_controller.dart';
import '../application/scan_payment_controller.dart';
import '../core/config/debug_mode_controller.dart';
import '../core/config/debug_mode_features.dart';
import '../core/config/offline_authorization_banner_controller.dart';
import '../core/config/payment_code_preferences.dart';
import '../core/errors/app_failure.dart';
import '../data/mock/debug_transactions.dart';
import '../domain/models/auth_models.dart';
import '../domain/models/bill_models.dart';
import '../domain/models/card_models.dart';
import '../domain/models/offline_models.dart';
import '../domain/models/payment_models.dart';
import '../domain/models/profile_models.dart';
import '../domain/models/scan_models.dart';
import '../domain/models/security_models.dart';
import '../domain/money_fen.dart';
import '../domain/ports/auth_port.dart';
import '../domain/ports/bill_ports.dart';
import '../domain/ports/card_ports.dart';
import '../domain/ports/platform_ports.dart';
import 'app_runtime.dart';

final appRuntimeProvider = Provider<AppRuntime>(
  (ref) =>
      throw StateError('AppRuntime must be overridden at the application root'),
);

/// Supplied by TechPie so the feature can open TechPie's Account settings for
/// the campus-card OpenID, on the host navigator it is being shown on.
final campusCardAccountProvider = Provider<VoidCallback?>((ref) => null);

final homeWidgetPortProvider = Provider<HomeWidgetPort?>((ref) => null);

enum CampusCardEntry { paymentCode, cardManagement }

final campusCardEntryProvider = Provider<CampusCardEntry>(
  (ref) => CampusCardEntry.paymentCode,
);

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSnapshot>(AuthController.new);

final class AuthController extends AsyncNotifier<AuthSnapshot> {
  Future<void>? _backgroundRestore;
  int _authRevision = 0;
  int _buildGeneration = 0;

  @override
  Future<AuthSnapshot> build() async {
    final generation = ++_buildGeneration;
    ref.onDispose(() => _buildGeneration++);
    final runtime = ref.watch(appRuntimeProvider);
    final auth = runtime.auth;
    final subscription = auth.changes.listen((snapshot) {
      _authRevision++;
      if (snapshot.state == AuthState.signingIn) {
        _invalidateAccountProviders();
        return;
      }
      _applySnapshot(snapshot);
      if (snapshot.state == AuthState.authenticated) {
        unawaited(_startBackgroundRestore(auth));
      }
    });
    final connectivitySubscription = runtime.connectivity.changes.listen((
      online,
    ) {
      if (online && state.valueOrNull?.state == AuthState.authenticated) {
        unawaited(_startBackgroundRestore(auth));
      }
    });
    final lifecycleSubscription = runtime.lifecycle.changes.listen((value) {
      if (value != AppLifecycleState.resumed || generation != _buildGeneration) return;
      if (state.hasError) {
        // A local credential read may have failed while protected data was
        // locked. Rebuild the local binding before attempting network recovery.
        ref.invalidateSelf();
      } else if (!state.isLoading) {
        unawaited(_startBackgroundRestore(auth));
      }
    });
    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(connectivitySubscription.cancel());
      unawaited(lifecycleSubscription.cancel());
    });
    final revision = _authRevision;
    final AuthSnapshot initial;
    try {
      initial = await _restoreLocal(auth, runtime, generation);
    } catch (_) {
      if (revision != _authRevision && state.valueOrNull != null) return state.valueOrNull!;
      rethrow;
    }
    if (generation != _buildGeneration) return initial;
    if (revision != _authRevision && state.valueOrNull != null) return state.valueOrNull!;
    if (initial.state == AuthState.authenticated) {
      Future<void>.delayed(Duration.zero, () {
        if (generation == _buildGeneration) {
          unawaited(_startBackgroundRestore(auth));
        }
      });
    }
    return initial;
  }

  void _applySnapshot(AuthSnapshot snapshot) {
    final previous = state.valueOrNull;
    state = AsyncData(snapshot);
    if (previous != null &&
        (previous.session?.subjectId != snapshot.session?.subjectId ||
            previous.session?.generation != snapshot.session?.generation)) {
      _invalidateAccountProviders(
        resetOfflineMode:
            previous.session?.subjectId != snapshot.session?.subjectId,
      );
    }
  }

  Future<AuthSnapshot> _restoreLocal(AuthPort auth, AppRuntime runtime, int generation) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await auth.restoreLocal().timeout(const Duration(seconds: 10));
      } catch (error) {
        final temporary = error is TimeoutException ||
            error is AppFailure && error.code == 'SECURE_STORAGE_UNAVAILABLE';
        if (!temporary || attempt >= 2 || generation != _buildGeneration ||
            runtime.lifecycle.current != AppLifecycleState.resumed) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        if (generation != _buildGeneration) rethrow;
      }
    }
  }

  Future<void> refreshFromServer() =>
      _startBackgroundRestore(ref.read(appRuntimeProvider).auth);

  Future<void> _startBackgroundRestore(AuthPort auth) {
    final active = _backgroundRestore;
    if (active != null) return active;
    late final Future<void> operation;
    final generation = _buildGeneration;
    operation = Future<void>.microtask(() async {
      if (generation == _buildGeneration) await _refreshStoredSession(auth);
    }).whenComplete(() {
      if (identical(_backgroundRestore, operation)) _backgroundRestore = null;
    });
    _backgroundRestore = operation;
    return operation;
  }

  Future<void> _refreshStoredSession(AuthPort auth) async {
    final revision = _authRevision;
    final generation = _buildGeneration;
    try {
      final refreshed = await auth.restore();
      if (revision == _authRevision && generation == _buildGeneration) {
        _applySnapshot(refreshed);
      }
    } catch (_) {
      // The locally verified identity and offline code remain available.
    }
  }

  Future<void> signIn(AuthCredential credential) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(appRuntimeProvider).auth.signIn(credential),
    );
    if (!result.hasError) _invalidateAccountProviders();
    state = result;
    _throwAsyncError(result);
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    final auth = ref.read(appRuntimeProvider).auth;
    final result = await AsyncValue.guard(() async {
      await auth.signOut();
      await ref
          .read(offlineAuthorizationBannerDismissedProvider.notifier)
          .reset();
      _invalidateAccountProviders();
      return auth.restoreLocal();
    });
    state = result;
    _throwAsyncError(result);
  }

  void _invalidateAccountProviders({bool resetOfflineMode = true}) {
    ref.invalidate(accountHistoryRefreshProvider);
    ref.invalidate(cardControllerProvider);
    ref.invalidate(profileControllerProvider);
    ref.invalidate(transactionDetailProvider);
    ref.invalidate(transactionFeedProvider);
    ref.invalidate(offlineAuthorizationProvider);
    if (resetOfflineMode) ref.invalidate(manualOfflineModeProvider);
    ref.invalidate(paymentCodeControllerProvider);
    // A same-account cookie replacement must not reset an in-flight scan to
    // idle: that would restart the camera and could submit the code again.
    // Existing challenge contexts still fail the API client's generation check.
    if (resetOfflineMode) ref.invalidate(scanPaymentControllerProvider);
    ref.invalidate(spendingPasswordInitializationProvider);
    ref.invalidate(spendingLimitsControllerProvider);
  }
}

final cardControllerProvider =
    AsyncNotifierProvider<CardController, CampusCard?>(CardController.new);

final class CardController extends AsyncNotifier<CampusCard?> {
  int _generation = 0;
  int _snapshotRevision = 0;

  @override
  Future<CampusCard?> build() {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    final runtime = ref.watch(appRuntimeProvider);
    final cards = runtime.cards;
    if (cards is CardSnapshotSource) {
      final subscription = (cards as CardSnapshotSource).snapshots.listen((card) {
        _snapshotRevision++;
        state = AsyncData(card);
      });
      ref.onDispose(() => unawaited(subscription.cancel()));
    }
    return _loadCard(runtime, generation);
  }

  Future<CampusCard?> _loadCard(
    AppRuntime runtime,
    int generation,
  ) async {
    final repository = runtime.cards;
    final snapshotRevision = _snapshotRevision;
    final CampusCard? card;
    if (repository is CacheFirstCardRepository) {
      final cached = await repository.readCachedCard();
      if (cached != null) {
        card = cached;
        unawaited(
          _refreshCachedCard(repository, generation),
        );
      } else {
        OfflineAuthorization? authorization;
        try {
          authorization =
              await runtime.offlinePayments.mostRecentAuthorization();
        } catch (_) {
          // A damaged historical grant cannot block an online card refresh.
        }
        if (authorization != null) {
          card = _offlineFallbackCard(authorization.cardId);
          unawaited(_refreshCachedCard(repository, generation));
        } else {
          card = await repository.refreshCard();
        }
      }
    } else {
      card = await repository.currentCard();
    }
    if (generation != _generation) return state.valueOrNull;
    final latest = snapshotRevision == _snapshotRevision ? card : state.valueOrNull;
    if (latest == null) return null;
    unawaited(_maintainOfflineAuthorization(runtime, latest));
    return latest;
  }

  Future<void> _refreshCachedCard(
    CacheFirstCardRepository repository,
    int generation,
  ) async {
    final snapshotRevision = _snapshotRevision;
    try {
      final refreshed = await repository.refreshCard();
      if (generation == _generation && snapshotRevision == _snapshotRevision && refreshed != null) {
        state = AsyncData(refreshed);
      }
    } catch (_) {
      // Cached card data remains usable when its background refresh fails.
    }
  }

  Future<void> _maintainOfflineAuthorization(
    AppRuntime runtime,
    CampusCard card,
  ) async {
    try {
      final current = await runtime.offlinePayments.status(card.id);
      if (current.authorization != null) {
        await runtime.offlinePayments.renew(card.id, force: true);
      }
    } catch (_) {
      // A failed renewal must not replace a usable local authorization.
    }
  }

  CampusCard _offlineFallbackCard(String cardId) {
    final tail =
        cardId.length <= 4 ? cardId : cardId.substring(cardId.length - 4);
    return CampusCard(
      id: cardId,
      maskedNumber: '••••$tail',
      ownerName: '',
      balance: MoneyFen.zero,
      status: CampusCardStatus.normal,
      positionName: '',
      offlineCodeAllowed: true,
      detailsAvailable: false,
    );
  }

  Future<BindCardResult?> bind(BindCardCommand command) async {
    final generation = _generation;
    final repository = ref.read(appRuntimeProvider).cards;
    state = const AsyncLoading();
    BindCardResult? result;
    final next = await AsyncValue.guard(() async {
      result = await repository.bind(command);
      return repository.currentCard();
    });
    if (generation != _generation) return null;
    state = next;
    _throwAsyncError(state);
    return result;
  }

  Future<void> unbind(String cardPassword) async {
    final generation = _generation;
    final repository = ref.read(appRuntimeProvider).cards;
    state = const AsyncLoading();
    final next = await AsyncValue.guard<CampusCard?>(() async {
      await repository.unbind(cardPassword: cardPassword);
      return null;
    });
    if (generation != _generation) return;
    state = next;
    _throwAsyncError(state);
  }

  Future<void> refresh() async {
    // A post-payment refresh supersedes older startup/balance requests.
    final generation = ++_generation;
    final previous = state.valueOrNull;
    final snapshotRevision = _snapshotRevision;
    final runtime = ref.read(appRuntimeProvider);
    final repository = runtime.cards;
    final result = await AsyncValue.guard(
      () => repository is CacheFirstCardRepository
          ? repository.refreshCard()
          : repository.currentCard(),
    );
    if (generation != _generation) return;
    if (result.hasError && previous != null) {
      if (snapshotRevision == _snapshotRevision) state = AsyncData(previous);
      _throwAsyncError(result);
    }
    if (snapshotRevision == _snapshotRevision) state = result;
    _throwAsyncError(result);
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);

final class ProfileController extends AsyncNotifier<UserProfile> {
  int _generation = 0;

  @override
  Future<UserProfile> build() {
    _generation++;
    ref.onDispose(() => _generation++);
    return ref.watch(appRuntimeProvider).cards.profile();
  }

  Future<void> refresh() async {
    final generation = _generation;
    state = const AsyncLoading();
    final next =
        await AsyncValue.guard(ref.read(appRuntimeProvider).cards.profile);
    if (generation != _generation) return;
    state = next;
    _throwAsyncError(state);
  }
}

final transactionDetailProvider =
    FutureProvider.family<TransactionRecord, String>((ref, id) {
  if (debugModeFeaturesAvailable && ref.watch(debugModeProvider)) {
    for (final record in debugTransactionRecords(DateTime.now())) {
      if (record.id == id) return record;
    }
  }
  return ref.watch(appRuntimeProvider).transactions.detail(id);
});

typedef TransactionDateRange = ({DateTime? begin, DateTime? end});

final transactionFeedProvider = AsyncNotifierProvider.family<
    TransactionFeedController, TransactionPage, TransactionDateRange>(
  TransactionFeedController.new,
);

final class TransactionFeedController
    extends FamilyAsyncNotifier<TransactionPage, TransactionDateRange> {
  bool _loadingMore = false;
  int _generation = 0;
  @override
  Future<TransactionPage> build(TransactionDateRange arg) async {
    _generation++;
    _loadingMore = false;
    ref.onDispose(() => _generation++);
    final range = arg;
    final debug = debugModeFeaturesAvailable && ref.watch(debugModeProvider);
    final port = ref.watch(appRuntimeProvider).transactions;
    if (port is! DateRangeTransactionHistoryPort) {
      throw UnsupportedError('Date range transaction history is unavailable');
    }
    final datePort = port as DateRangeTransactionHistoryPort;
    final page = await datePort.timelineRange(
      begin: range.begin,
      end: range.end,
    );
    if (!debug) return page;
    return _withDebugTransactions(page);
  }

  Future<void> loadMore() async {
    final generation = _generation;
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    final port = ref.read(appRuntimeProvider).transactions;
    if (port is! DateRangeTransactionHistoryPort) {
      _loadingMore = false;
      return;
    }
    try {
      final next =
          await (port as DateRangeTransactionHistoryPort).timelineRange(
        begin: arg.begin,
        end: arg.end,
        cursor: current.nextCursor,
      );
      if (generation != _generation) return;
      final seen = current.items.map((record) => record.id).toSet();
      final debugItems = current.items
          .where((record) => record.id.startsWith('DEBUG-'))
          .toList();
      final currentRealItems = current.items
          .where((record) => !record.id.startsWith('DEBUG-'))
          .toList();
      final cursorAdvanced =
          next.nextCursor != null && next.nextCursor != current.nextCursor;
      state = AsyncData(
        TransactionPage(
          items: [
            ...currentRealItems,
            for (final record in next.items)
              if (seen.add(record.id)) record,
            ...debugItems,
          ],
          hasMore: next.hasMore && cursorAdvanced,
          nextCursor: cursorAdvanced ? next.nextCursor : null,
        ),
      );
    } catch (error, stackTrace) {
      if (generation == _generation) state = AsyncError(error, stackTrace);
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }
}

TransactionPage _withDebugTransactions(TransactionPage page) => TransactionPage(
      items: [...page.items, ...debugTransactionRecords(DateTime.now())],
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
    );

final manualOfflineModeProvider =
    NotifierProvider<ManualOfflineModeController, bool>(
  ManualOfflineModeController.new,
);

final class ManualOfflineModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) => state = enabled;
}

final offlineAuthorizationProvider = AsyncNotifierProvider.family<
    OfflineAuthorizationController, OfflineAuthorizationView, String>(
  OfflineAuthorizationController.new,
);

final class OfflineAuthorizationController
    extends FamilyAsyncNotifier<OfflineAuthorizationView, String> {
  static const _automaticRetryDelay = Duration(minutes: 15);
  Timer? _renewalTimer;
  int _generation = 0;

  @override
  Future<OfflineAuthorizationView> build(String arg) async {
    final generation = ++_generation;
    final cardId = arg;
    ref.onDispose(() {
      _generation++;
      _renewalTimer?.cancel();
    });
    final service = ref.watch(appRuntimeProvider).offlinePayments;
    final view = await service.status(cardId);
    if (generation != _generation) return view;
    _scheduleAutomaticRenewal(view);
    if (_shouldRenewAutomatically(view) && !_manualOffline) {
      // Publish the local grant before attempting network maintenance. A valid
      // renewal-due grant remains usable while the server is slow/unavailable.
      Future<void>.delayed(Duration.zero, () {
        if (generation == _generation) unawaited(maintain(force: true));
      });
    }
    return view;
  }

  Future<OfflineQrCode> generate() async {
    final generation = _generation;
    final service = ref.read(appRuntimeProvider).offlinePayments;
    // The service hands back the grant it just consumed, so the new remaining
    // count costs no extra keystore read.
    final result = await service.generateWithGrant(arg);
    if (generation == _generation) {
      state = AsyncData(
        service.viewOf(result.authorization, hasPrivateKey: true),
      );
    }
    return result.code;
  }

  Future<void> activate() async {
    final generation = _generation;
    final service = ref.read(appRuntimeProvider).offlinePayments;
    final previous = state.valueOrNull ??
        const OfflineAuthorizationView(
          state: OfflineAuthorizationState.missingCredential,
        );
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await service.activate(cardId: arg);
      return service.status(arg);
    });
    if (generation != _generation) return;
    if (result.hasError) {
      state = AsyncData(previous);
      _throwAsyncError(result);
    }
    state = result;
    final view = result.valueOrNull;
    if (view != null) _scheduleAutomaticRenewal(view);
  }

  Future<void> renew({bool force = true}) async {
    final generation = _generation;
    final service = ref.read(appRuntimeProvider).offlinePayments;
    final previous = state.valueOrNull;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await service.renew(arg, force: force);
      return service.status(arg);
    });
    if (generation != _generation) return;
    if (result.hasError) {
      state = previous == null ? result : AsyncData(previous);
      _throwAsyncError(result);
    }
    state = result;
    final view = result.valueOrNull;
    if (view != null) _scheduleAutomaticRenewal(view);
  }

  Future<void> maintain({bool force = true}) async {
    final generation = _generation;
    final service = ref.read(appRuntimeProvider).offlinePayments;
    try {
      await service.renew(arg, force: force);
      final view = await service.status(arg);
      if (generation != _generation) return;
      state = AsyncData(view);
      _scheduleAutomaticRenewal(view);
    } catch (_) {
      if (generation != _generation) return;
      try {
        final view = await service.status(arg);
        if (generation != _generation) return;
        state = AsyncData(view);
        _scheduleAutomaticRenewal(view, retrySoon: true);
      } catch (_) {
        if (generation != _generation) return;
        _renewalTimer?.cancel();
        _renewalTimer = Timer(
          _automaticRetryDelay,
          () => unawaited(maintain(force: true)),
        );
      }
    }
  }

  Future<void> removeFromDevice() async {
    final generation = ++_generation;
    final service = ref.read(appRuntimeProvider).offlinePayments;
    final banner = ref.read(offlineAuthorizationBannerDismissedProvider.notifier);
    _renewalTimer?.cancel();
    await service.removeFromThisDevice(arg);
    if (generation != _generation) return;
    await banner.reset();
    if (generation != _generation) return;
    state = const AsyncData(
      OfflineAuthorizationView(
        state: OfflineAuthorizationState.missingCredential,
      ),
    );
  }

  bool _shouldRenewAutomatically(OfflineAuthorizationView view) =>
      view.authorization != null &&
      (view.state == OfflineAuthorizationState.renewalDue ||
          view.state == OfflineAuthorizationState.expired);

  void _scheduleAutomaticRenewal(
    OfflineAuthorizationView view, {
    bool retrySoon = false,
  }) {
    _renewalTimer?.cancel();
    // Manual offline mode is a promise of no network: nothing here renews until
    // the switch is turned off again.
    if (_manualOffline) return;
    final authorization = view.authorization;
    if (authorization == null) return;
    final expiresOn = authorization.expiresOn;
    var delay = _automaticRetryDelay;
    if (!retrySoon &&
        expiresOn != null &&
        view.state == OfflineAuthorizationState.active) {
      final renewalAt = DateTime.utc(
        expiresOn.year,
        expiresOn.month,
        expiresOn.day,
      ).subtract(const Duration(days: 4));
      final untilRenewal = renewalAt.difference(DateTime.now().toUtc());
      if (untilRenewal > Duration.zero) delay = untilRenewal;
    }
    _renewalTimer = Timer(delay, () {
      if (_manualOffline) return;
      unawaited(maintain(force: true));
    });
  }

  bool get _manualOffline => ref.read(manualOfflineModeProvider);
}

final accountHistoryRefreshProvider = Provider<AccountHistoryRefresh>((ref) {
  ref.watch(appRuntimeProvider);
  final coordinator = AccountHistoryRefresh(loadHistory: () async {
    const range = (begin: null, end: null);
    final provider = transactionFeedProvider(range);
    final exists = ref.exists(provider);
    final previous = exists ? ref.read(provider).valueOrNull?.items.map((item) => item.id).toSet() : null;
    ref.invalidate(transactionFeedProvider);
    final page = await ref.read(provider.future);
    return previous != null && page.items.any((item) => !previous.contains(item.id));
  },);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final paymentCodeControllerProvider =
    NotifierProvider.autoDispose<PaymentCodeNotifier, PaymentCodeViewState>(
  PaymentCodeNotifier.new,
);

final class PaymentCodeNotifier
    extends AutoDisposeNotifier<PaymentCodeViewState> {
  late PaymentCodeExperienceController _controller;
  int _generation = 0;

  @override
  PaymentCodeViewState build() {
    _generation++;
    final controller =
        ref.watch(appRuntimeProvider).createPaymentCodeController();
    final history = ref.read(accountHistoryRefreshProvider);
    final subscription = controller.states.listen((value) {
      final nextFrame = value.frame;
      final generated = nextFrame != null && !identical(nextFrame, state.frame);
      state = value;
      if (generated) {
        unawaited(history.codeGenerated(balanceChanged: nextFrame.balanceChanged));
      }
    });
    _controller = controller;
    ref.listen(
      maximizePaymentCodeBrightnessProvider,
      (_, next) {
        unawaited(controller.setMaximizeBrightness(next.valueOrNull ?? false));
      },
      fireImmediately: true,
    );
    ref.onDispose(() {
      _generation++;
      unawaited(subscription.cancel());
      unawaited(controller.dispose());
    });
    return controller.state;
  }

  Future<void> enter({bool online = true}) =>
      _guardPaymentAction(() => _controller.enter(online: online));
  Future<void> restart() => _guardPaymentAction(_controller.restart);
  Future<void> refresh() => _guardPaymentAction(_controller.refresh);
  Future<void> activateAndRestart() =>
      _guardPaymentAction(_controller.activateAndRestart);
  Future<void> leave() => _guardPaymentAction(_controller.leave);

  void debugComplete() {
    if (!debugModeFeaturesAvailable || !ref.read(debugModeProvider)) return;
    _controller.debugComplete();
  }

  void markDisconnected() => _controller.markDisconnected();

  Future<void> _guardPaymentAction(Future<void> Function() action) async {
    final generation = _generation;
    try {
      await action();
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(
        phase: PaymentCodePhase.failed,
        message: '付款码加载失败，请重试。',
        connectionState: PaymentConnectionState.apiError,
      );
    }
  }
}

final scanPaymentControllerProvider =
    NotifierProvider.autoDispose<ScanPaymentNotifier, ScanFlowState>(
  ScanPaymentNotifier.new,
);

final class ScanPaymentNotifier extends AutoDisposeNotifier<ScanFlowState> {
  late ScanPaymentController _controller;

  @override
  ScanFlowState build() {
    final controller =
        ref.watch(appRuntimeProvider).createScanPaymentController();
    final subscription = controller.states.listen((value) {
      final completed = value.phase == ScanFlowPhase.succeeded &&
          state.phase != ScanFlowPhase.succeeded &&
          value.success?.kind == ScanSuccessKind.payment;
      state = value;
      if (completed && !(debugModeFeaturesAvailable && ref.read(debugModeProvider))) {
        unawaited(_refreshAccountAfterPayment());
      }
    });
    _controller = controller;
    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(controller.dispose());
    });
    return controller.state;
  }

  Future<void> _refreshAccountAfterPayment() async {
    // Start while success is displayed; closing the scanner does not cancel
    // account refreshes or turn a confirmed payment into a failure.
    final cardRefresh = ref.read(cardControllerProvider.notifier).refresh();
    ref.invalidate(profileControllerProvider);
    ref.invalidate(transactionDetailProvider);
    final historyRefresh = ref.read(accountHistoryRefreshProvider).refresh(fresh: true);
    await Future.wait<void>([
      cardRefresh.then<void>((_) {}, onError: (Object _) {}),
      historyRefresh.then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

  Future<void> submitCode(String code) =>
      debugModeFeaturesAvailable && ref.read(debugModeProvider)
          ? _controller.debugSubmitCode(code)
          : _controller.submitCode(code);
  Future<void> submitPassword(String password) =>
      debugModeFeaturesAvailable && ref.read(debugModeProvider)
          ? _controller.debugSubmitPassword(password)
          : _controller.submitPassword(password);
  void reset() => _controller.reset();
}

final spendingPasswordInitializationProvider =
    FutureProvider<SpendingPasswordInitialization>(
  (ref) =>
      ref.watch(appRuntimeProvider).securitySettings.initializePasswordChange(),
);

final spendingLimitsControllerProvider =
    AsyncNotifierProvider.autoDispose<SpendingLimitsController, SpendingLimits>(
  SpendingLimitsController.new,
);

final class SpendingLimitsController
    extends AutoDisposeAsyncNotifier<SpendingLimits> {
  int _generation = 0;

  @override
  Future<SpendingLimits> build() {
    _generation++;
    ref.onDispose(() => _generation++);
    return ref.watch(appRuntimeProvider).securitySettings.readLimits();
  }

  Future<void> saveCardLimits(SpendingLimits limits) async {
    final previous = state.valueOrNull;
    if (previous == null) return;
    final generation = _generation;
    final service = ref.read(appRuntimeProvider).securitySettings;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await service.updateCardLimits(limits);
      if (generation != _generation) return previous;
      return service.readLimits();
    });
    if (generation != _generation) return;
    if (result.hasError) {
      state = AsyncData(previous);
      _throwAsyncError(result);
    }
    state = result;
  }

  Future<void> saveQrLimits(
    SpendingLimits limits, {
    required String transactionPassword,
  }) async {
    final previous = state.valueOrNull;
    if (previous == null) return;
    final generation = _generation;
    final service = ref.read(appRuntimeProvider).securitySettings;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await service.updateQrLimits(limits, transactionPassword: transactionPassword);
      if (generation != _generation) return previous;
      return service.readLimits();
    });
    if (generation != _generation) return;
    if (result.hasError) {
      state = AsyncData(previous);
      _throwAsyncError(result);
    }
    state = result;
  }

  Future<void> changePassword({
    required String accountKey,
    required String oldPassword,
    required String newPassword,
  }) =>
      ref.read(appRuntimeProvider).securitySettings.changeSpendingPassword(
            accountKey: accountKey,
            oldPassword: oldPassword,
            newPassword: newPassword,
          );
}

void _throwAsyncError(AsyncValue<Object?> value) {
  if (!value.hasError) return;
  Error.throwWithStackTrace(value.error!, value.stackTrace!);
}
