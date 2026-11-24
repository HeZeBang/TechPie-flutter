import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../utils/glass.dart';
import '../utils/motion.dart';
import 'app_shell/app_shell_metrics.dart';

enum DesktopPopoverPlacement { rightTop, belowEnd }

typedef DesktopPopoverBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

/// Drives origin-anchored spring entrance and crisp exit animations for
/// desktop popovers.
class DesktopPopoverMotionController {
  Future<void> Function()? _dismiss;

  Future<void> dismiss() => _dismiss?.call() ?? Future<void>.value();
}

/// Origin-anchored Telegram-style spring reveal (`0.92 -> 1.0`, `opacity 0 -> 1`)
/// with fast shrink-out dismiss. Automatically degrades to an instant toggle
/// when reduced motion is enabled.
class DesktopPopoverMotion extends StatefulWidget {
  const DesktopPopoverMotion({
    super.key,
    required this.controller,
    required this.alignment,
    required this.child,
    this.visible = true,
  });

  final DesktopPopoverMotionController controller;
  final Alignment alignment;
  final Widget child;
  final bool visible;

  @override
  State<DesktopPopoverMotion> createState() => _DesktopPopoverMotionState();
}

class _DesktopPopoverMotionState extends State<DesktopPopoverMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );
  bool _entered = false;
  bool _closing = false;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    widget.controller._dismiss = _dismiss;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.visible && !_entered) {
      _playEnter();
    }
  }

  @override
  void didUpdateWidget(covariant DesktopPopoverMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._dismiss = null;
      widget.controller._dismiss = _dismiss;
    }
    if (widget.visible && !_entered) {
      _playEnter();
    }
  }

  void _playEnter() {
    _entered = true;
    if (_reduceMotion) {
      _t.value = 1;
      return;
    }
    unawaited(
      _t
          .animateWith(
            SpringSimulation(TgMotion.snappySpring, 0, 1, 0),
          )
          .whenComplete(() {
        if (mounted && !_closing) _t.value = 1;
      }),
    );
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    setState(() {});
    if (_reduceMotion || !_entered) {
      _t.value = 0;
      return;
    }
    await _t.animateTo(
      0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    if (widget.controller._dismiss == _dismiss) {
      widget.controller._dismiss = null;
    }
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible || _closing,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) {
          final value = widget.visible ? _t.value : 0.0;
          final settled = widget.visible && (value - 1.0).abs() < 1e-4;
          final opacity = !widget.visible
              ? 0.0
              : (settled ? 1.0 : value.clamp(0.0, 1.0));
          final scale = !widget.visible || settled ? 1.0 : 0.92 + 0.08 * value;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              alignment: widget.alignment,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

void showDesktopPopover({
  required BuildContext anchorContext,
  required DesktopPopoverBuilder builder,
  double width = 260,
  DesktopPopoverPlacement placement = DesktopPopoverPlacement.belowEnd,
  Offset offset = const Offset(8, 8),
  bool scrollable = false,
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
  final maxContentHeight = math.max(
    margin,
    screenSize.height - bottomObstruction - margin * 2,
  );

  /// Where a popover of [size] belongs: the requested placement, flipped to
  /// the other side of the anchor when it does not fit there, and clamped as
  /// a last resort so it never leaves the screen.
  ({Offset position, Alignment alignment}) positionFor(Size size) {
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

    var flippedAbove = false;
    // Open above the anchor when there is no room below it.
    if (placement == DesktopPopoverPlacement.belowEnd &&
        top + size.height > bottomLimit) {
      final above = anchorOffset.dy - size.height - offset.dy;
      if (above >= margin || above > top) {
        top = above;
        flippedAbove = true;
      }
    }

    left = left
        .clamp(
          margin,
          math.max(margin, screenSize.width - size.width - margin),
        )
        .toDouble();
    top = top
        .clamp(
          margin,
          math.max(margin, bottomLimit - size.height),
        )
        .toDouble();

    final Alignment alignment;
    if (placement == DesktopPopoverPlacement.rightTop) {
      alignment = left >= anchorOffset.dx
          ? Alignment.topLeft
          : Alignment.topRight;
    } else {
      alignment = flippedAbove ? Alignment.bottomRight : Alignment.topRight;
    }
    return (position: Offset(left, top), alignment: alignment);
  }

  // The content's height is only known after it has been laid out once — the
  // callers build a variable number of rows. Render one invisible frame to
  // measure it, then spring-reveal from the computed anchor alignment.
  final contentKey = GlobalKey();
  final motionController = DesktopPopoverMotionController();
  Size? measuredSize;

  OverlayEntry? entry;
  KeyEventCallback? keyHandler;
  var closing = false;

  void removeNow() {
    if (keyHandler != null) {
      HardwareKeyboard.instance.removeHandler(keyHandler!);
      keyHandler = null;
    }
    entry?.remove();
    entry = null;
  }

  void close() {
    if (closing) return;
    closing = true;
    if (keyHandler != null) {
      HardwareKeyboard.instance.removeHandler(keyHandler!);
      keyHandler = null;
    }
    if (measuredSize == null) {
      removeNow();
      return;
    }
    unawaited(motionController.dismiss().whenComplete(removeNow));
  }

  bool handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      close();
      return true;
    }
    return false;
  }

  keyHandler = handleKey;
  HardwareKeyboard.instance.addHandler(handleKey);

  entry = OverlayEntry(
    builder: (context) {
      final resolved = measuredSize == null
          ? (position: const Offset(margin, margin), alignment: Alignment.topRight)
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
            left: resolved.position.dx,
            top: resolved.position.dy,
            width: width,
            child: ConstrainedBox(
              constraints: scrollable
                  ? BoxConstraints(maxHeight: maxContentHeight)
                  : const BoxConstraints(),
              child: KeyedSubtree(
                key: contentKey,
                child: DesktopPopoverMotion(
                  controller: motionController,
                  alignment: resolved.alignment,
                  visible: measuredSize != null,
                  child: Theme(
                    data: theme,
                    child: Builder(
                      builder: (context) {
                        final content = builder(context, close);
                        return scrollable
                            ? SingleChildScrollView(child: content)
                            : content;
                      },
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

/// Frosted TgGlass popover container with high-contrast overlay alpha (~0.84
/// light / ~0.86 dark), crisp hairline stroke, and layered soft shadow.
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
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusM);
    final overlayColor = colors.surface.withValues(
      alpha: colors.isDark ? 0.86 : 0.84,
    );
    final borderColor = colors.isDark
        ? colors.border
        : Colors.black.withValues(alpha: 0.08);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.42 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.24 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: TgGlass.backdrop(sigma: 22),
          child: Material(
            color: overlayColor,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: borderColor, width: 0.75),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class DesktopMenuRow extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final VoidCallback? onTap;
  final bool selected;

  const DesktopMenuRow({
    super.key,
    required this.leading,
    required this.title,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    final enabled = onTap != null;

    final row = Material(
      color: selected ? colors.opaqueBrandContainer : Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        ),
        highlightColor: colors.textPrimary.withValues(alpha: 0.06),
        splashColor: colors.brand.withValues(alpha: 0.10),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(
                      color: selected ? colors.brandInk : colors.textMuted,
                    ),
                    child: leading,
                  ),
                ),
              ),
              Expanded(child: title),
              const SizedBox(width: TpTokens.space3),
            ],
          ),
        ),
      ),
    );

    if (enabled) return row;
    return Opacity(opacity: 0.42, child: row);
  }
}
