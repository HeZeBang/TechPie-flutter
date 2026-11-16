import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/tokens.dart';

/// The campus payment QR, shared by the full pass and the glance surface.
///
/// [qrKey] defaults to the key the full pass has always exposed; the glance
/// passes its own key so a test can tell the two surfaces apart.
final class PaymentCodeQr extends StatefulWidget {
  const PaymentCodeQr({
    super.key,
    required this.payload,
    required this.binaryPayload,
    required this.size,
    required this.onTap,
    this.qrKey = const Key('payment-code-qr'),
  });

  final String payload;
  final bool binaryPayload;
  final double size;
  final VoidCallback onTap;
  final Key qrKey;

  @override
  State<PaymentCodeQr> createState() => _PaymentCodeQrState();
}

class _PaymentCodeQrState extends State<PaymentCodeQr> {
  late Widget _image;

  @override
  void initState() {
    super.initState();
    _image = _createImage();
  }

  @override
  void didUpdateWidget(PaymentCodeQr oldWidget) {
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
          key: widget.qrKey,
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

/// Thirty-second countdown shown under an online code.
final class PaymentCodeCountdown extends StatefulWidget {
  const PaymentCodeCountdown({
    super.key,
    required this.generation,
    required this.active,
    required this.style,
    this.seconds = 30,
  });

  final int generation;
  final bool active;
  final TextStyle style;
  final int seconds;

  @override
  State<PaymentCodeCountdown> createState() => _PaymentCodeCountdownState();
}

class _PaymentCodeCountdownState extends State<PaymentCodeCountdown> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _startTimer();
  }

  @override
  void didUpdateWidget(PaymentCodeCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation ||
        oldWidget.seconds != widget.seconds) {
      _remaining = widget.seconds;
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
      final next = (initial - timer.tick).clamp(1, widget.seconds);
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
