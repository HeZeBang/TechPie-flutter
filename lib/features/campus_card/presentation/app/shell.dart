import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../utils/adaptive_motion.dart';
import '../scanner/scanner_modal.dart';
import '../theme/tokens.dart';

/// Opens the scanner with one identical bottom-up transition on every OS.
Future<void> openGpScanner(BuildContext context) async {
  final reduceMotion = !appAnimationsEnabled(context);
  final container = ProviderScope.containerOf(context);
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  await showGeneralDialog<void>(
    context: context,
    // Scanning owns the whole screen: the user must close it before changing
    // tabs. Keep the feature's providers and theme on this root modal route.
    useRootNavigator: true,
    barrierLabel: '关闭',
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: GpTokens.scanModalDuration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        themes.wrap(
          UncontrolledProviderScope(
            container: container,
            child: ScannerModal(
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      return gpScannerEntranceTransition(
        animation,
        child,
        reduceMotion: reduceMotion,
      );
    },
  );
}
