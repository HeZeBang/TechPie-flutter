import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../features/campus_card/domain/ports/platform_ports.dart';
import '../../features/campus_card/platform/scanner/mobile_scanner_session.dart';
import 'scanner_geometry.dart';

/// Attaches the platform camera preview to the shared scanner page.
final class ScannerViewport extends StatelessWidget {
  const ScannerViewport({super.key, required this.session});

  final ScannerPort? session;

  @override
  Widget build(BuildContext context) {
    if (session is MobileScannerSession) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final window = scannerWindowForSize(constraints.biggest);
          return MobileScanner(
            controller: (session! as MobileScannerSession).controller,
            scanWindow: window.isEmpty ? null : window,
            errorBuilder: (context, error) => const _CameraFallback(
              message: '当前设备没有可用相机，请从相册选择二维码图片。',
            ),
          );
        },
      );
    }
    return const _CameraFallback(message: '相机未启用');
  }
}

final class _CameraFallback extends StatelessWidget {
  const _CameraFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 42),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
}
