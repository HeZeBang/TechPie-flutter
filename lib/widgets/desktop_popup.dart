import 'dart:math' as math;

import 'package:flutter/material.dart';

enum DesktopPopoverPlacement { rightTop, belowEnd }

typedef DesktopPopoverBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

// Matches AppShell._desktopShellEnabled being temporarily false: every
// window width now uses MobileShell, so this must report mobile too, or
// callers (e.g. SettingsPage's nested Navigator) would assume a DesktopShell
// content pane that no longer exists. Flip both back together.
bool isDesktopLayout(BuildContext context) {
  return false;
}

void showDesktopPopover({
  required BuildContext anchorContext,
  required DesktopPopoverBuilder builder,
  double width = 260,
  DesktopPopoverPlacement placement = DesktopPopoverPlacement.belowEnd,
  Offset offset = const Offset(8, 8),
}) {
  final overlay = Overlay.of(anchorContext, rootOverlay: true);
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  if (anchorBox == null || !anchorBox.attached) return;

  final anchorOffset = anchorBox.localToGlobal(Offset.zero);
  final anchorSize = anchorBox.size;
  final screenSize = MediaQuery.sizeOf(anchorContext);
  final theme = Theme.of(anchorContext);

  final rawLeft = switch (placement) {
    DesktopPopoverPlacement.rightTop =>
      anchorOffset.dx + anchorSize.width + offset.dx,
    DesktopPopoverPlacement.belowEnd =>
      anchorOffset.dx + anchorSize.width - width + offset.dx,
  };
  final rawTop = switch (placement) {
    DesktopPopoverPlacement.rightTop => anchorOffset.dy + offset.dy,
    DesktopPopoverPlacement.belowEnd =>
      anchorOffset.dy + anchorSize.height + offset.dy,
  };

  final left = rawLeft
      .clamp(16.0, math.max(16.0, screenSize.width - width - 24))
      .toDouble();
  final top =
      rawTop.clamp(16.0, math.max(16.0, screenSize.height - 160)).toDouble();

  OverlayEntry? entry;
  void close() {
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    builder: (context) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Theme(
              data: theme,
              child: Builder(builder: (context) => builder(context, close)),
            ),
          ),
        ],
      );
    },
  );

  overlay.insert(entry!);
}

class DesktopPopoverSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DesktopPopoverSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black.withAlpha(45),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class DesktopMenuRow extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final VoidCallback? onTap;

  const DesktopMenuRow({
    super.key,
    required this.leading,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(width: 40, child: Center(child: leading)),
            Expanded(child: title),
          ],
        ),
      ),
    );
  }
}
