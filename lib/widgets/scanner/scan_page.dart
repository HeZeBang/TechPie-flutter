import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/campus_card/domain/ports/platform_ports.dart';
import '../../utils/adaptive_motion.dart';
import '../../utils/haptics.dart';
import 'scan_overlay.dart';
import 'scanner_geometry.dart';
import 'scanner_viewport.dart';

typedef ScannerCodeHandler = Future<void> Function(
  ScannerPageController controller,
  ScannerReading reading,
);

typedef ScannerOverlayBuilder = Widget Function(
  BuildContext context,
  ScannerPageController controller,
);

/// Opens the one scanner used by every QR workflow in the app.
///
/// The page owns camera start/stop, lifecycle handling, duplicate suppression,
/// gallery input, torch state, and the Telegram-style viewfinder animation.
/// Callers only decide what a decoded value means.
Future<String?> showTechPieScanner(
  BuildContext context, {
  required ScannerPort? scanner,
  AppLifecyclePort? lifecycle,
  FeedbackPort? feedback,
  String title = '扫描二维码',
  String hint = '将二维码放入框内，即可自动扫描',
  bool torch = true,
  ScannerCodeHandler? onCode,
  ScannerOverlayBuilder? overlayBuilder,
  Duration settleBeforePop = const Duration(milliseconds: 220),
}) {
  return showGeneralDialog<String>(
    context: context,
    useRootNavigator: false,
    barrierLabel: '关闭',
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (dialogContext, animation, secondaryAnimation) => ScannerPage(
      scanner: scanner,
      lifecycle: lifecycle,
      feedback: feedback,
      title: title,
      hint: hint,
      torch: torch,
      onCode: onCode,
      overlayBuilder: overlayBuilder,
      settleBeforePop: settleBeforePop,
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
        scannerEntranceTransition(
      animation,
      child,
      reduceMotion: !appAnimationsEnabled(context),
    ),
  );
}

Widget scannerEntranceTransition(
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

Widget scannerPopupTransition(
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

/// The shared scanner surface. Business flows are supplied through [onCode]
/// and [overlayBuilder]; camera behavior must stay here.
final class ScannerPage extends StatefulWidget {
  const ScannerPage({
    super.key,
    required this.scanner,
    this.lifecycle,
    this.feedback,
    this.title = '扫描二维码',
    this.hint = '将二维码放入框内，即可自动扫描',
    this.torch = true,
    this.onCode,
    this.overlayBuilder,
    this.settleBeforePop = const Duration(milliseconds: 220),
    this.onClose,
  });

  final ScannerPort? scanner;
  final AppLifecyclePort? lifecycle;
  final FeedbackPort? feedback;
  final String title;
  final String hint;
  final bool torch;
  final ScannerCodeHandler? onCode;
  final ScannerOverlayBuilder? overlayBuilder;
  final Duration settleBeforePop;
  final VoidCallback? onClose;

  @override
  ScannerPageState createState() => ScannerPageState();
}

final class ScannerPageController {
  ScannerPageController(this._state);

  final ScannerPageState _state;

  Future<void> rescan() => _state.rescan();
  Future<void> complete(String value) => _state.complete(value);
  Future<void> stop() => _state.stopCamera();
}

final class ScannerPageState extends State<ScannerPage>
    with TickerProviderStateMixin {
  late final ScanOverlayController _overlay =
      ScanOverlayController(vsync: this);
  late final ScannerPageController pageController = ScannerPageController(this);
  StreamSubscription<ScannerReading>? _codeSubscription;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;

  /// Whether this page has a camera session it still has to release.
  bool _started = false;

  /// Whether a decode has been handed over; the preview is frozen on it now.
  bool _handled = false;
  bool _torchOn = false;
  List<Offset>? _foundCorners;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscribeLifecycle();
      unawaited(startCamera());
    });
  }

  @override
  void dispose() {
    _overlay.dispose();
    unawaited(stopCamera());
    unawaited(_codeSubscription?.cancel());
    unawaited(_lifecycleSubscription?.cancel());
    super.dispose();
  }

  void _subscribeLifecycle() {
    final lifecycle = widget.lifecycle;
    if (lifecycle == null) return;
    _lifecycleSubscription = lifecycle.changes.listen((state) {
      if (!mounted) return;
      switch (state) {
        case AppLifecycleState.resumed:
          if (!_handled) unawaited(startCamera());
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          // A frozen preview holds no camera — only its last frame, which is
          // what the result on top of it is being read against.
          if (!_handled) unawaited(stopCamera());
      }
    });
  }

  Future<void> startCamera() async {
    if (!mounted || _handled) return;
    final scanner = widget.scanner;
    _overlay.beginCameraStart();
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    if (scanner == null) {
      _overlay.startAppearing();
      await _overlay.finishCameraStart();
      return;
    }
    _started = true;
    _codeSubscription ??= scanner.scannedCodes.listen(_handleCode);
    try {
      await scanner.start();
      if (!mounted) return;
      setState(() => _error = null);
      // The camera is behind the startup cover now, so both animations begin
      // together and the preview is revealed underneath them.
      _overlay.startAppearing();
      unawaited(_overlay.finishCameraStart());
    } catch (_) {
      _started = false;
      if (mounted) {
        unawaited(_overlay.finishCameraStart());
        setState(() => _error = '相机不可用');
      }
    }
  }

  Future<void> stopCamera() async {
    if (!_started) return;
    _started = false;
    try {
      await widget.scanner?.stop();
    } catch (_) {
      // Leaving the route must not turn a camera cleanup failure into UI state.
    }
  }

  Future<void> _toggleTorch() async {
    final scanner = widget.scanner;
    if (scanner == null) return;
    final next = !_torchOn;
    try {
      await scanner.setTorch(next);
      await widget.feedback?.play(FeedbackEvent.selection);
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {
      if (mounted) setState(() => _error = '手电筒不可用');
    }
  }

  Future<void> _openGallery() async {
    final scanner = widget.scanner;
    if (scanner == null) return;
    try {
      final code = await scanner.scanImage();
      if (code != null) {
        if (mounted) _handleCode(ScannerReading(code));
        return;
      }
      // A picture whose code could not be read and a picker that was dismissed
      // are the same answer through here: both are "nothing came back
      // readable", and the tap says so instead of ending without a trace.
      if (mounted) setState(() => _error = '没有从相册图片里识别到二维码');
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取相册图片');
    }
  }

  void _handleCode(ScannerReading reading) {
    final code = reading.value.trim();
    if (!mounted || code.isEmpty || _handled) return;
    _handled = true;
    _overlay.revealCameraImmediately();
    setState(() => _foundCorners = reading.corners);
    _overlay.setFound(true);
    unawaited(AppHaptics.play(AppHaptics.mediumImpact));
    unawaited(_freezeAndHandOff(reading, code));
  }

  /// Freezes the preview on the frame the code was read from, then hands the
  /// code over. The camera stops behind that still frame, so the result — and
  /// the frame that lands on the code — is read against the picture the user
  /// just saw, without encoding, decoding or copying a frame to get there.
  Future<void> _freezeAndHandOff(ScannerReading reading, String code) async {
    await widget.scanner?.freeze();
    if (!mounted) return;
    final handler = widget.onCode;
    if (handler == null) {
      await complete(code);
      return;
    }
    await handler(pageController, reading);
  }

  Future<void> rescan() async {
    if (!mounted) return;
    _handled = false;
    _foundCorners = null;
    _overlay.resetFrame();
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    // Resumes the frozen preview: the camera session was never released.
    if (mounted) await startCamera();
  }

  Future<void> complete(String value) async {
    await Future<void>.delayed(widget.settleBeforePop);
    if (!mounted) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlayBuilder?.call(context, pageController);
    final content = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The scrim and the corner marks cover the preview only. The chrome
          // goes above them: underneath, the 50% scrim dims every label and
          // icon on the page to grey.
          ScanOverlay(
            painterKey: const Key('scanner-mask'),
            windowFor: scannerWindowForSize,
            appearing: _overlay.appearing,
            dismissed: _overlay.dismissed,
            absorbed: _overlay.absorbed,
            target: _foundCorners,
            child: ScannerViewport(session: widget.scanner),
          ),
          _buildChrome(context),
          // The startup cover is above the chrome as well, so a start hides
          // everything — the previous session's last frame included — until the
          // preview reports its first frame.
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _overlay.restarting,
              builder: (context, _) {
                final cover = _overlay.restarting.value.clamp(0.0, 1.0);
                if (cover <= 0) return const SizedBox.shrink();
                return ColoredBox(
                  color: Colors.black.withValues(alpha: cover),
                );
              },
            ),
          ),
          if (overlay != null) Positioned.fill(child: overlay),
        ],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: content,
    );
  }

  Widget _buildChrome(BuildContext context) {
    return AnimatedBuilder(
      animation: _overlay.dismissed,
      builder: (context, child) => Opacity(
        opacity: (1 - _overlay.dismissed.value).clamp(0.0, 1.0),
        child: child,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            children: [
              Row(
                children: [
                  _RoundScannerButton(
                    key: const Key('scanner-close-button'),
                    icon: Icons.close,
                    label: '关闭',
                    onPressed: () async {
                      if (widget.onClose != null) {
                        widget.onClose!();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const Spacer(),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                  const Spacer(),
                  const SizedBox.square(dimension: 52),
                ],
              ),
              const Spacer(),
              Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.torch)
                    _RoundScannerButton(
                      icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                      label: _torchOn ? '关闭手电筒' : '手电筒',
                      active: _torchOn,
                      onPressed: _toggleTorch,
                    ),
                  if (widget.torch) const SizedBox(width: 32),
                  _RoundScannerButton(
                    icon: Icons.photo_library_outlined,
                    label: '相册',
                    onPressed: _openGallery,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _RoundScannerButton extends StatelessWidget {
  const _RoundScannerButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? Colors.white : Colors.black.withValues(alpha: 0.44),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () => unawaited(onPressed()),
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
        // The caption is part of the button: it is what a user aims at, so a tap
        // on it does what a tap on the circle does.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(onPressed()),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
