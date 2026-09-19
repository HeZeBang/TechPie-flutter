import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../utils/adaptive_motion.dart';
import '../../app/app_providers.dart';
import '../../core/config/scan_payment_preferences.dart';
import '../../domain/models/card_models.dart';
import '../../domain/models/scan_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../widgets/apple_wallet_components.dart';
import 'scan_result_content.dart';
import 'scanner_geometry.dart';
import 'scanner_viewport.dart';
import 'six_digit_password_panel.dart';

Widget gpScannerEntranceTransition(
  Animation<double> animation,
  Widget child, {
  required bool reduceMotion,
}) {
  final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
  if (reduceMotion) return FadeTransition(opacity: curved, child: child);
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curved),
    child: child,
  );
}

Widget gpScannerPopupTransition(
  Animation<double> animation,
  Widget child, {
  required bool reduceMotion,
}) {
  final curved = animation.drive(CurveTween(curve: Curves.easeOutCubic));
  if (reduceMotion) return FadeTransition(opacity: curved, child: child);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
        child: child,
      ),
    ),
  );
}

final class ScannerModal extends ConsumerStatefulWidget {
  const ScannerModal({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<ScannerModal> createState() => _ScannerModalState();
}

class _ScannerModalState extends ConsumerState<ScannerModal> {
  late final ScannerPort? _scanner;
  StreamSubscription<String>? _codeSub;
  StreamSubscription<AppLifecycleState>? _lifecycleSub;
  bool _scanning = false;
  bool _accepting = true;
  bool _torchOn = false;
  String? _lastCode;
  String? _pendingConfirmationCode;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanner = ref.read(appRuntimeProvider).scanner;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscribeLifecycle();
      unawaited(_startCamera());
    });
  }

  @override
  void dispose() {
    unawaited(_stopCamera());
    unawaited(_codeSub?.cancel());
    unawaited(_lifecycleSub?.cancel());
    super.dispose();
  }

  void _subscribeLifecycle() {
    final lifecycle = ref.read(appRuntimeProvider).lifecycle;
    _lifecycleSub = lifecycle.changes.listen((state) {
      if (!mounted) return;
      switch (state) {
        case AppLifecycleState.resumed:
          if (_pendingConfirmationCode == null &&
              ref.read(scanPaymentControllerProvider).phase ==
                  ScanFlowPhase.idle) {
            unawaited(_startCamera());
          }
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          unawaited(_stopCamera());
      }
    });
  }

  Future<void> _startCamera() async {
    if (!mounted || _scanning || _pendingConfirmationCode != null) return;
    final scanner = _scanner;
    if (scanner == null) return;
    _scanning = true;
    _codeSub ??= scanner.scannedCodes.listen(_handleCode);
    try {
      await scanner.start();
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = '相机不可用';
        });
      }
    }
  }

  Future<void> _stopCamera() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await _scanner?.stop();
    } catch (_) {
      // The modal is leaving; a stop failure cannot change account state.
    }
  }

  Future<void> _toggleTorch() async {
    final scanner = _scanner;
    if (scanner == null) return;
    final next = !_torchOn;
    try {
      await scanner.setTorch(next);
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.selection);
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {
      if (mounted) setState(() => _error = '手电筒');
    }
  }

  Future<void> _openGallery() async {
    final scanner = _scanner;
    if (scanner == null) return;
    try {
      final code = await scanner.scanImage();
      if (code != null && mounted) _handleCode(code);
    } catch (_) {
      if (mounted) setState(() => _error = '相册');
    }
  }

  void _handleCode(String code) {
    if (!mounted || code.isEmpty || !_accepting || code == _lastCode) return;
    _accepting = false;
    _lastCode = code;
    unawaited(() async {
      await ref
          .read(appRuntimeProvider)
          .feedback
          .play(FeedbackEvent.mediumImpact);
      await _stopCamera();
      if (!mounted) return;
      if (ref.read(skipScanConfirmationProvider)) {
        await ref.read(scanPaymentControllerProvider.notifier).submitCode(code);
      } else {
        setState(() => _pendingConfirmationCode = code);
      }
    }());
  }

  void _syncCamera(ScanFlowPhase phase) {
    if (phase == ScanFlowPhase.idle && _pendingConfirmationCode == null) {
      _lastCode = null;
      _accepting = true;
      unawaited(_startCamera());
    } else {
      unawaited(_stopCamera());
    }
  }

  Future<void> _rescan() async {
    _pendingConfirmationCode = null;
    _lastCode = null;
    _accepting = true;
    setState(() => _error = null);
    ref.read(scanPaymentControllerProvider.notifier).reset();
    await _startCamera();
  }

  Future<void> _confirmScan() async {
    final code = _pendingConfirmationCode;
    if (code == null) return;
    setState(() => _pendingConfirmationCode = null);
    await ref.read(scanPaymentControllerProvider.notifier).submitCode(code);
  }

  Future<void> _cancelScanConfirmation() async {
    await _rescan();
  }

  void _finish() {
    ref.read(scanPaymentControllerProvider.notifier).reset();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(scanPaymentControllerProvider, (previous, next) {
      _syncCamera(next.phase);
    });

    final runtime = ref.watch(appRuntimeProvider);
    final scan = ref.watch(scanPaymentControllerProvider);
    final card = ref.watch(cardControllerProvider).valueOrNull;
    final reduceMotion = !appAnimationsEnabled(context);
    final popupDuration = reduceMotion
        ? const Duration(milliseconds: 180)
        : GpTokens.scanModalDuration;
    Widget popupTransition(Widget child, Animation<double> animation) =>
        gpScannerPopupTransition(animation, child, reduceMotion: reduceMotion);

    final scanner = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: runtime.scanner == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        '相机不可用',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                : ScannerViewport(session: runtime.scanner!),
          ),
          const Positioned.fill(child: _ScannerMask()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      _ScannerCloseButton(
                        icon: GpPlatformIcons.close(context),
                        label: '关闭',
                        onPressed: widget.onClose,
                      ),
                      const Spacer(),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    '将二维码放入框内',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ScannerControl(
                        icon: _torchOn
                            ? GpPlatformIcons.flashOn(context)
                            : GpPlatformIcons.flashOff(context),
                        label: '手电筒',
                        active: _torchOn,
                        onTap: _toggleTorch,
                      ),
                      const SizedBox(width: 32),
                      _ScannerControl(
                        icon: GpPlatformIcons.photoLibrary(context),
                        label: '相册',
                        onTap: _openGallery,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: scan.phase != ScanFlowPhase.submitting,
              child: AnimatedSwitcher(
                duration: popupDuration,
                transitionBuilder: popupTransition,
                child: scan.phase == ScanFlowPhase.submitting
                    ? Center(
                        key: const ValueKey('scan-submitting-popup'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.70),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CupertinoActivityIndicator(
                                color: Colors.white,
                              ),
                              SizedBox(width: 10),
                              Text(
                                '正在加载',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.expand(
                        key: ValueKey('scan-submitting-none'),
                      ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? const Duration(milliseconds: 180)
                  : GpTokens.resultOverlayDuration,
              transitionBuilder: popupTransition,
              child: switch (scan.phase) {
                ScanFlowPhase.succeeded => _LightResultOverlay(
                    key: const ValueKey('success'),
                    child: ScanResultContent(
                      success: scan.success!,
                      onDone: _finish,
                      feedback: runtime.feedback,
                    ),
                  ),
                ScanFlowPhase.failed => _LightResultOverlay(
                    key: const ValueKey('failure'),
                    child: ScanFailureContent(
                      message:
                          scan.message ?? '付款码生成失败',
                      onRescan: _rescan,
                      feedback: runtime.feedback,
                    ),
                  ),
                _ => const SizedBox.shrink(key: ValueKey('none')),
              },
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: popupDuration,
              transitionBuilder: popupTransition,
              child: _pendingConfirmationCode != null
                  ? _ScanConfirmationOverlay(
                      key: const ValueKey('scan-confirmation-popup'),
                      card: card,
                      onContinue: _confirmScan,
                      onCancel: _cancelScanConfirmation,
                    )
                  : scan.phase == ScanFlowPhase.passwordRequired
                      ? _PayAuthorizationOverlay(
                          key: const ValueKey('scan-password-popup'),
                          card: card,
                          feedback: runtime.feedback,
                          onSubmit: (password) => unawaited(
                            ref
                                .read(scanPaymentControllerProvider.notifier)
                                .submitPassword(password),
                          ),
                          onCancel: () => ref
                              .read(scanPaymentControllerProvider.notifier)
                              .reset(),
                        )
                      : const SizedBox.expand(
                          key: ValueKey('scan-authorization-none'),
                        ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: popupDuration,
                transitionBuilder: popupTransition,
                child: _error == null
                    ? const SizedBox.expand(key: ValueKey('scan-error-none'))
                    : SafeArea(
                        key: const ValueKey('scan-error-popup'),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(
                              top: 72,
                              left: 20,
                              right: 20,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: scanner,
    );
  }
}

final class _ScannerCloseButton extends StatelessWidget {
  const _ScannerCloseButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: 52,
        child: CupertinoButton(
          key: const Key('scanner-close-button'),
          padding: EdgeInsets.zero,
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(26),
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white, size: 25),
        ),
      ),
    );
  }
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
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.52),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
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
                            '上海科技大学 eCard',
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
      ),
    );
  }
}

final class _ScannerControl extends StatelessWidget {
  const _ScannerControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: active ? Colors.white : Colors.black.withValues(alpha: 0.44),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 62,
              child: Icon(
                icon,
                color: active ? Colors.black : Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}

final class _ScannerMask extends StatelessWidget {
  const _ScannerMask();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('scanner-mask'),
      painter: _ScannerMaskPainter(),
    );
  }
}

final class _ScannerMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = scannerWindowForSize(size);
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(26)));
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );

    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const length = 34.0;
    final path = Path()
      ..moveTo(rect.left, rect.top + length)
      ..lineTo(rect.left, rect.top + 12)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + 12, rect.top)
      ..lineTo(rect.left + length, rect.top)
      ..moveTo(rect.right - length, rect.top)
      ..lineTo(rect.right - 12, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + 12)
      ..lineTo(rect.right, rect.top + length)
      ..moveTo(rect.left, rect.bottom - length)
      ..lineTo(rect.left, rect.bottom - 12)
      ..quadraticBezierTo(rect.left, rect.bottom, rect.left + 12, rect.bottom)
      ..lineTo(rect.left + length, rect.bottom)
      ..moveTo(rect.right - length, rect.bottom)
      ..lineTo(rect.right - 12, rect.bottom)
      ..quadraticBezierTo(rect.right, rect.bottom, rect.right, rect.bottom - 12)
      ..lineTo(rect.right, rect.bottom - length);
    canvas.drawPath(path, corner);
  }

  @override
  bool shouldRepaint(_ScannerMaskPainter old) => false;
}

final class _LightResultOverlay extends StatelessWidget {
  const _LightResultOverlay({required super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
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
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.50),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
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
                            '上海科技大学 eCard',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        MaskedCardNumberText(maskedNumber: card!.maskedNumber),
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
      ),
    );
  }
}
