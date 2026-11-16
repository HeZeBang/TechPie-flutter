import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campus_card/app/app_providers.dart';
import '../../campus_card/app/app_runtime.dart';
import '../../campus_card/core/config/payment_code_preferences.dart';
import '../../campus_card/domain/models/auth_models.dart';
import '../../campus_card/domain/models/card_models.dart';
import '../../campus_card/domain/models/payment_models.dart';
import '../../campus_card/presentation/theme/theme.dart';
import '../../campus_card/presentation/theme/tokens.dart';
import '../../campus_card/presentation/widgets/apple_wallet_components.dart';
import '../../campus_card/presentation/widgets/payment_code_qr.dart';
import 'glance_payment_card.dart';
import 'glance_widgets.dart';

/// Online payment code for the cover / rear screen.
///
/// This view deliberately watches only authentication, the card summary and
/// the online payment controller. Offline codes stay in the full campus-card
/// page so glancing at the small screen can never spend an offline use.
class GlancePaymentView extends StatelessWidget {
  const GlancePaymentView({super.key, required this.runtime});

  final AppRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appRuntimeProvider.overrideWithValue(runtime),
        maximizePaymentCodeBrightnessProvider.overrideWith(
          () => MaximizePaymentCodeBrightnessController.fixed(false),
        ),
      ],
      child: Builder(
        builder: (context) {
          final host = Theme.of(context);
          return Theme(
            data: GeekPayTheme.inherit(host),
            child: const _GlancePaymentBody(),
          );
        },
      ),
    );
  }
}

/// The small surface must never change the main display's brightness.
class _GlancePaymentBody extends ConsumerStatefulWidget {
  const _GlancePaymentBody();

  @override
  ConsumerState<_GlancePaymentBody> createState() =>
      _GlancePaymentBodyState();
}

class _GlancePaymentBodyState extends ConsumerState<_GlancePaymentBody>
    with WidgetsBindingObserver {
  bool _tickerEnabled = true;
  bool _foreground = true;
  bool _entered = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _scheduleSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scheduleSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleSync() {
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_applyActivity(revision));
    });
  }

  Future<void> _applyActivity(int revision) async {
    if (!mounted || revision != _revision) return;
    final auth = ref.read(authControllerProvider).valueOrNull;
    final authenticated = auth?.state == AuthState.authenticated;
    final shouldRun = _tickerEnabled && _foreground && authenticated;
    if (shouldRun == _entered) return;
    final notifier = ref.read(paymentCodeControllerProvider.notifier);
    if (shouldRun) {
      _entered = true;
      try {
        await notifier.enter(online: true);
      } catch (_) {
        _entered = false;
      }
    } else {
      _entered = false;
      await notifier.leave();
    }
    if (mounted && revision == _revision) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, __) => _scheduleSync());
    final auth = ref.watch(authControllerProvider);
    final card = ref.watch(cardControllerProvider);
    final payment = ref.watch(paymentCodeControllerProvider);

    final snapshot = auth.valueOrNull;
    if (snapshot == null) {
      if (auth.hasError) {
        return const GlanceMessage(
          icon: Icons.credit_card_off_outlined,
          title: '校园卡状态不可用',
          subtitle: '请展开手机重试',
        );
      }
      return const GlanceLoading(label: '正在读取校园卡…');
    }

    switch (snapshot.state) {
      case AuthState.signingIn:
        return const GlanceLoading(label: '正在登录校园卡…');
      case AuthState.authenticated:
        break;
      case AuthState.expired:
        return const GlanceMessage(
          icon: Icons.lock_clock_outlined,
          title: '校园卡登录已过期',
          subtitle: '请展开手机，在完整 App 中重新登录',
        );
      case AuthState.signedOut:
      case AuthState.unconfigured:
        return const GlanceMessage(
          icon: Icons.credit_card_outlined,
          title: '校园卡未登录',
          subtitle: '请展开手机，在完整 App 中登录',
        );
    }

    final cardValue = card.valueOrNull;
    final cardBlocked =
        cardValue != null && !cardValue.status.permitsPayment;
    final balance = cardValue != null && cardValue.detailsAvailable
        ? formatMoneyFen(cardValue.balance.value)
        : null;

    if (payment.phase == PaymentCodePhase.activationRequired) {
      return const GlanceMessage(
        icon: Icons.wifi_tethering_error_rounded,
        title: '付款码未开通',
        subtitle: '请在完整 App 中完成开通',
      );
    }

    if (payment.phase == PaymentCodePhase.succeeded && payment.result != null) {
      return _PaymentSuccess(result: payment.result!);
    }

    final frame = payment.frame;
    if (frame == null) {
      if (payment.phase == PaymentCodePhase.failed) {
        return GlanceMessage(
          icon: Icons.qr_code_2_outlined,
          title: '付款码加载失败',
          subtitle: payment.message,
          action: TextButton(
            onPressed: () => unawaited(_retry()),
            child: const Text('重试'),
          ),
        );
      }
      return const GlanceLoading(label: '正在生成付款码…');
    }

    final disconnected =
        payment.connectionState == PaymentConnectionState.disconnected;
    final hint = disconnected
        ? '网络已断开，轻触重试'
        : cardBlocked
            ? '校园卡状态异常'
            : payment.phase == PaymentCodePhase.refreshing
                ? '正在刷新…'
                : '轻触二维码刷新';

    return GlancePaymentCard(
      payload: frame.qrPayload,
      binaryPayload: frame.rawQrCode.startsWith('5638'),
      statusLabel: '在线付款码',
      balanceText: balance,
      hint: hint,
      countdown: PaymentCodeCountdown(
        generation: payment.generation,
        active: _entered,
        style: TextStyle(
          fontSize: 10,
          color: GpTokens.campusRed.withValues(alpha: 0.62),
        ),
      ),
      onTap: () => unawaited(_refresh()),
    );
  }

  Future<void> _retry() async {
    if (!_entered) {
      await ref
          .read(paymentCodeControllerProvider.notifier)
          .enter(online: true);
    } else {
      await ref.read(paymentCodeControllerProvider.notifier).refresh();
    }
  }

  Future<void> _refresh() async {
    if (!_entered) return;
    await ref.read(paymentCodeControllerProvider.notifier).refresh();
  }
}

class _PaymentSuccess extends StatelessWidget {
  const _PaymentSuccess({required this.result});

  final TransactionResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: GpTokens.cardCanvas,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 44, color: scheme.tertiary),
            const SizedBox(height: 8),
            const Text(
              '支付成功',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: GpTokens.campusRed,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatMoneyFen(result.amount.value, fixedDecimals: true),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: GpTokens.campusRed,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (result.merchantName != null) ...[
              const SizedBox(height: 3),
              Text(
                result.merchantName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: GpTokens.campusRed.withValues(alpha: 0.62),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
