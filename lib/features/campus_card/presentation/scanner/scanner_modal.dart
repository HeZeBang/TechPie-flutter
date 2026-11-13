import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../utils/adaptive_motion.dart';
import '../../../../widgets/scanner/scan_page.dart';
import '../../app/app_providers.dart';
import '../../core/config/scan_payment_preferences.dart';
import '../../domain/models/card_models.dart';
import '../../domain/models/scan_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../widgets/apple_wallet_components.dart';
import 'scan_result_content.dart';
import 'six_digit_password_panel.dart';

Widget gpScannerEntranceTransition(
  Animation<double> animation,
  Widget child, {
  required bool reduceMotion,
}) =>
    scannerEntranceTransition(
      animation,
      child,
      reduceMotion: reduceMotion,
    );

Widget gpScannerPopupTransition(
  Animation<double> animation,
  Widget child, {
  required bool reduceMotion,
}) =>
    scannerPopupTransition(
      animation,
      child,
      reduceMotion: reduceMotion,
    );

/// Payment-specific adapter around the app-wide [ScannerPage].
///
/// This widget owns only payment confirmation and result content. Camera state,
/// duplicate handling, lifecycle, viewfinder geometry, and controls belong to
/// the common scanner library.
final class ScannerModal extends ConsumerStatefulWidget {
  const ScannerModal({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<ScannerModal> createState() => _ScannerModalState();
}

final class _ScannerModalState extends ConsumerState<ScannerModal> {
  String? _pendingConfirmationCode;

  Future<void> _rescan(ScannerPageController controller) async {
    _pendingConfirmationCode = null;
    ref.read(scanPaymentControllerProvider.notifier).reset();
    await controller.rescan();
  }

  Future<void> _confirm(
    ScannerPageController controller,
    String code,
  ) async {
    setState(() => _pendingConfirmationCode = null);
    await ref.read(scanPaymentControllerProvider.notifier).submitCode(code);
  }

  void _finish() {
    ref.read(scanPaymentControllerProvider.notifier).reset();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(appRuntimeProvider);
    final scan = ref.watch(scanPaymentControllerProvider);
    final card = ref.watch(cardControllerProvider).valueOrNull;
    final reduceMotion = !appAnimationsEnabled(context);

    return ScannerPage(
      scanner: runtime.scanner,
      lifecycle: runtime.lifecycle,
      feedback: runtime.feedback,
      title: '扫描消费码',
      hint: '将二维码放入框内',
      onClose: _finish,
      onCode: (controller, reading) async {
        if (ref.read(skipScanConfirmationProvider)) {
          await ref.read(scanPaymentControllerProvider.notifier).submitCode(
                reading.value,
              );
        } else {
          setState(() => _pendingConfirmationCode = reading.value);
        }
      },
      overlayBuilder: (context, controller) => _PaymentScannerOverlays(
        scan: scan,
        card: card,
        pendingCode: _pendingConfirmationCode,
        feedback: runtime.feedback,
        reduceMotion: reduceMotion,
        onConfirm: () {
          final code = _pendingConfirmationCode;
          if (code != null) unawaited(_confirm(controller, code));
        },
        onCancelConfirmation: () => unawaited(_rescan(controller)),
        onPassword: (password) => unawaited(
          ref.read(scanPaymentControllerProvider.notifier).submitPassword(
                password,
              ),
        ),
        onCancelPassword: () {
          ref.read(scanPaymentControllerProvider.notifier).reset();
          unawaited(controller.rescan());
        },
        onDone: _finish,
        onRescan: () => unawaited(_rescan(controller)),
      ),
    );
  }
}

final class _PaymentScannerOverlays extends StatelessWidget {
  const _PaymentScannerOverlays({
    required this.scan,
    required this.card,
    required this.pendingCode,
    required this.feedback,
    required this.reduceMotion,
    required this.onConfirm,
    required this.onCancelConfirmation,
    required this.onPassword,
    required this.onCancelPassword,
    required this.onDone,
    required this.onRescan,
  });

  final ScanFlowState scan;
  final CampusCard? card;
  final String? pendingCode;
  final FeedbackPort feedback;
  final bool reduceMotion;
  final VoidCallback onConfirm;
  final VoidCallback onCancelConfirmation;
  final ValueChanged<String> onPassword;
  final VoidCallback onCancelPassword;
  final VoidCallback onDone;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final popupDuration = reduceMotion
        ? const Duration(milliseconds: 180)
        : GpTokens.scanModalDuration;
    Widget transition(Widget child, Animation<double> animation) =>
        gpScannerPopupTransition(animation, child, reduceMotion: reduceMotion);

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: scan.phase != ScanFlowPhase.submitting,
          child: AnimatedSwitcher(
            duration: popupDuration,
            transitionBuilder: transition,
            child: scan.phase == ScanFlowPhase.submitting
                ? const Center(
                    key: ValueKey('scan-submitting-popup'),
                    child: _SubmittingPopup(),
                  )
                : const SizedBox.expand(
                    key: ValueKey('scan-submitting-none'),
                  ),
          ),
        ),
        AnimatedSwitcher(
          duration: reduceMotion
              ? const Duration(milliseconds: 180)
              : GpTokens.resultOverlayDuration,
          transitionBuilder: transition,
          child: switch (scan.phase) {
            ScanFlowPhase.succeeded => _LightResultOverlay(
                key: const ValueKey('success'),
                child: ScanResultContent(
                  success: scan.success!,
                  onDone: onDone,
                  feedback: feedback,
                ),
              ),
            ScanFlowPhase.failed => _LightResultOverlay(
                key: const ValueKey('failure'),
                child: ScanFailureContent(
                  message: scan.message ?? '扫码消费失败',
                  onRescan: onRescan,
                  feedback: feedback,
                ),
              ),
            _ => const SizedBox.shrink(key: ValueKey('none')),
          },
        ),
        AnimatedSwitcher(
          duration: popupDuration,
          transitionBuilder: transition,
          child: pendingCode != null
              ? _ScanConfirmationOverlay(
                  key: const ValueKey('scan-confirmation-popup'),
                  card: card,
                  onContinue: onConfirm,
                  onCancel: onCancelConfirmation,
                )
              : scan.phase == ScanFlowPhase.passwordRequired
                  ? _PayAuthorizationOverlay(
                      key: const ValueKey('scan-password-popup'),
                      card: card,
                      feedback: feedback,
                      onSubmit: onPassword,
                      onCancel: onCancelPassword,
                    )
                  : const SizedBox.expand(
                      key: ValueKey('scan-authorization-none'),
                    ),
        ),
      ],
    );
  }
}

final class _SubmittingPopup extends StatelessWidget {
  const _SubmittingPopup();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(color: Colors.white),
            SizedBox(width: 10),
            Text('正在加载', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
}

final class _ScanConfirmationOverlay extends StatelessWidget {
  const _ScanConfirmationOverlay({
    super.key,
    required this.card,
    required this.onContinue,
    required this.onCancel,
  });

  final CampusCard? card;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // The system bar's inset becomes part of the sheet's own padding rather than
    // lifting the sheet: a lifted surface leaves a strip of camera preview
    // showing under it, right where the bar is.
    final systemBar = MediaQuery.viewPaddingOf(context).bottom;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 560),
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + systemBar),
          decoration: BoxDecoration(
            color: context.gpColors.surfaceDisabled,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(32),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: context.gpColors.textDisabled,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '是否继续扫码交易？',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '继续后才会向校园支付服务提交二维码。',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.gpColors.textSecondary),
              ),
              if (card != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.gpColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: CampusWalletCard(
                          card: card!,
                          compact: true,
                          heroTag: 'scan-confirmation-card',
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '校园卡',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      MaskedCardNumberText(maskedNumber: card!.maskedNumber),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: context.gpColors.surface,
                      onPressed: onCancel,
                      child: Text(
                        '取消',
                        style: TextStyle(color: context.gpColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      color: context.gpColors.action,
                      onPressed: onContinue,
                      child: const Text(
                        '继续',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _LightResultOverlay extends StatelessWidget {
  const _LightResultOverlay({required super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.gpColors.bg,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: child,
              ),
            ),
          ),
        ),
      );
}

final class _PayAuthorizationOverlay extends StatelessWidget {
  const _PayAuthorizationOverlay({
    super.key,
    required this.card,
    required this.feedback,
    required this.onSubmit,
    required this.onCancel,
  });

  final CampusCard? card;
  final FeedbackPort feedback;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => SafeArea(
        // As above: the surface reaches the screen edge, the content does not.
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 560),
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: context.gpColors.surfaceDisabled,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (card != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.gpColors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 58,
                          child: CampusWalletCard(
                            card: card!,
                            compact: true,
                            heroTag: 'scan-pay-card',
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            '校园卡',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        MaskedCardNumberText(
                          maskedNumber: card!.maskedNumber,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SixDigitPasswordPanel(
                  feedback: feedback,
                  onSubmit: onSubmit,
                  onCancel: onCancel,
                ),
              ],
            ),
          ),
        ),
      );
}
