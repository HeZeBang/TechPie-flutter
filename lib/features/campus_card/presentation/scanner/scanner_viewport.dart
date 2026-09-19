// The only presentation file that imports scanner plugins. Presentation pages
// consume ScannerPort for logic; this adapter only attaches the plugin
// controller to the preview surface.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:techpie/features/campus_card/domain/ports/platform_ports.dart';
import 'package:techpie/features/campus_card/platform/scanner/mobile_scanner_session.dart';
import 'scanner_geometry.dart';

/// Narrow scanner preview adapter. Casts the port to [MobileScannerSession]
/// only to attach `session.controller` to the plugin preview widget; every
/// start/stop/torch/gallery/scannedCodes operation flows through
/// [ScannerPort], never through the plugin here.
final class ScannerViewport extends StatelessWidget {
  const ScannerViewport({super.key, required this.session});

  final ScannerPort session;

  @override
  Widget build(BuildContext context) {
    if (session is MobileScannerSession) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final window = scannerWindowForSize(constraints.biggest);
          return MobileScanner(
            controller: (session as MobileScannerSession).controller,
            scanWindow: window.isEmpty ? null : window,
            errorBuilder: (context, error, _) => const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 42),
                  child: Text(
                    '当前设备没有可用相机，请从相册选择二维码图片。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // Platform-neutral fallback for tests and null adapter.
    return const SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black),
        child: Center(
          child: Text(
            '相机未启用',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
