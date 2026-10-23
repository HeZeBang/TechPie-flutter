import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_shell/app_shell_metrics.dart';

enum DesktopPopoverPlacement { rightTop, belowEnd }

typedef DesktopPopoverBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

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

  // MobileShell's floating bottom nav bar sits above the screen edge, and a
  // popover must not cover it. Read its height from the shell when the anchor
  // lives inside one; otherwise fall back to the safe-area inset alone.
  final metrics = anchorContext
      .getElementForInheritedWidgetOfExactType<AppShellMetrics>()
      ?.widget as AppShellMetrics?;
  final bottomObstruction = metrics?.bottomObstruction ??
      MediaQuery.viewPaddingOf(anchorContext).bottom;

  const margin = 16.0;
  // Lowest y a popover's top edge may take so its content stays above the bar.
  final bottomLimit = screenSize.height - bottomObstruction - margin;

  /// Where a popover of [size] belongs: the requested placement, flipped to
  /// the other side of the anchor when it does not fit there, and clamped as
  /// a last resort so it never leaves the screen.
  Offset positionFor(Size size) {
    var left = switch (placement) {
      DesktopPopoverPlacement.rightTop =>
        anchorOffset.dx + anchorSize.width + offset.dx,
      DesktopPopoverPlacement.belowEnd =>
        anchorOffset.dx + anchorSize.width - width + offset.dx,
    };
    var top = switch (placement) {
      DesktopPopoverPlacement.rightTop => anchorOffset.dy + offset.dy,
      DesktopPopoverPlacement.belowEnd =>
        anchorOffset.dy + anchorSize.height + offset.dy,
    };

    // Open above the anchor when there is no room below it.
    if (placement == DesktopPopoverPlacement.belowEnd &&
        top + size.height > bottomLimit) {
      final above = anchorOffset.dy - size.height - offset.dy;
      if (above >= margin || above > top) {
        top = above;
      }
    }

    left = left.clamp(
      margin,
      math.max(margin, screenSize.width - size.width - margin),
    ).toDouble();
    top = top.clamp(
      margin,
      math.max(margin, bottomLimit - size.height),
    ).toDouble();
    return Offset(left, top);
  }

  // The content's height is only known after it has been laid out once — the
  // callers build a variable number of rows. Render one invisible frame to
  // measure it, then rebuild at the final position. Guessing the height here
  // is what broke #139: the old code clamped against an assumed ~160px and
  // taller menus ran off the bottom of the screen over the nav bar.
  final contentKey = GlobalKey();
  Size? measuredSize;

  OverlayEntry? entry;
  void close() {
    entry?.remove();
    entry = null;
  }

  entry = OverlayEntry(
    builder: (context) {
      final position = measuredSize == null
          ? const Offset(margin, margin)
          : positionFor(measuredSize!);
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
            left: position.dx,
            top: position.dy,
            width: width,
            child: KeyedSubtree(
              key: contentKey,
              child: IgnorePointer(
                ignoring: measuredSize == null,
                child: Opacity(
                  opacity: measuredSize == null ? 0 : 1,
                  child: Theme(
                    data: theme,
                    child: Builder(
                      builder: (context) => builder(context, close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  overlay.insert(entry!);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final currentEntry = entry;
    if (currentEntry == null) return; // Closed before the first frame finished.
    final box = contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    measuredSize = box.size;
    currentEntry.markNeedsBuild();
  });
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
