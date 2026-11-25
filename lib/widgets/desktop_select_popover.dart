import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../utils/haptics.dart';
import 'desktop_popup.dart';

typedef DesktopSelectAnchorBuilder = Widget Function(
  BuildContext context,
  bool isOpen,
  VoidCallback toggle,
);

typedef DesktopSelectLabelBuilder<T> = String Function(T item);
typedef DesktopSelectLeadingBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  bool selected,
);

class DesktopSelectPopover<T> extends StatefulWidget {
  final List<T> items;
  final T value;
  final ValueChanged<T> onChanged;
  final DesktopSelectLabelBuilder<T> labelBuilder;
  final DesktopSelectAnchorBuilder anchorBuilder;
  final double width;
  final double itemHeight;
  final int visibleItemCount;
  final Offset offset;
  final DesktopSelectLeadingBuilder<T>? leadingBuilder;

  const DesktopSelectPopover({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.labelBuilder,
    required this.anchorBuilder,
    this.width = 200,
    this.itemHeight = 56,
    this.visibleItemCount = 5,
    this.offset = const Offset(12, 0),
    this.leadingBuilder,
  });

  @override
  State<DesktopSelectPopover<T>> createState() =>
      _DesktopSelectPopoverState<T>();
}

class _DesktopSelectPopoverState<T> extends State<DesktopSelectPopover<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;
  ScrollController? _scrollController;
  KeyEventCallback? _keyHandler;
  DesktopPopoverMotionController? _motionController;
  bool _closing = false;

  bool get _isOpen => _entry != null && !_closing;

  @override
  void didUpdateWidget(covariant DesktopSelectPopover<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entry != null &&
        (oldWidget.value != widget.value ||
            !listEquals(oldWidget.items, widget.items))) {
      _close(notify: false, immediate: true);
    }
  }

  @override
  void dispose() {
    _close(notify: false, immediate: true);
    super.dispose();
  }

  @override
  void reassemble() {
    _close(notify: false, immediate: true);
    super.reassemble();
  }

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (widget.items.isEmpty) return;
    if (_entry != null) {
      _close(notify: false, immediate: true);
    }

    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;

    final overlay = Overlay.of(anchorContext, rootOverlay: true);
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (anchorBox == null || !anchorBox.attached) return;

    final anchorOffset = anchorBox.localToGlobal(Offset.zero);
    final anchorSize = anchorBox.size;
    final screenSize = MediaQuery.sizeOf(anchorContext);
    final theme = Theme.of(anchorContext);
    final menuHeight = widget.itemHeight *
        math.min(widget.visibleItemCount, widget.items.length);

    final rawLeft = anchorOffset.dx + anchorSize.width + widget.offset.dx;
    final rawTop = anchorOffset.dy + widget.offset.dy;
    final left = rawLeft
        .clamp(16.0, math.max(16.0, screenSize.width - widget.width - 24))
        .toDouble();
    final top = rawTop
        .clamp(16.0, math.max(16.0, screenSize.height - menuHeight - 24))
        .toDouble();
    final alignment =
        left >= anchorOffset.dx ? Alignment.topLeft : Alignment.topRight;

    final selectedIndex = widget.items.indexOf(widget.value);
    final initialIndex = selectedIndex < 0
        ? 0
        : (selectedIndex - widget.visibleItemCount ~/ 2).clamp(
            0,
            math.max(0, widget.items.length - widget.visibleItemCount),
          );

    final scrollController = ScrollController(
      initialScrollOffset: initialIndex * widget.itemHeight,
    );
    final motionController = DesktopPopoverMotionController();
    _scrollController = scrollController;
    _motionController = motionController;
    _closing = false;

    _entry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: widget.width,
              child: DesktopPopoverMotion(
                controller: motionController,
                alignment: alignment,
                child: Theme(
                  data: theme,
                  child: _DesktopSelectMenu<T>(
                    items: widget.items,
                    value: widget.value,
                    controller: scrollController,
                    itemHeight: widget.itemHeight,
                    visibleItemCount: widget.visibleItemCount,
                    labelBuilder: widget.labelBuilder,
                    leadingBuilder: widget.leadingBuilder,
                    onSelected: (item) {
                      unawaited(AppHaptics.play(AppHaptics.selection));
                      _close();
                      widget.onChanged(item);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    _keyHandler = (event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _close();
        return true;
      }
      return false;
    };
    HardwareKeyboard.instance.addHandler(_keyHandler!);
    overlay.insert(_entry!);
    setState(() {});
  }

  void _removeOverlayNow({
    required OverlayEntry? entry,
    required ScrollController? scrollController,
    required bool notify,
  }) {
    if (_entry == entry) {
      _entry = null;
      _motionController = null;
      _closing = false;
    }
    entry?.remove();
    if (_scrollController == scrollController) {
      _scrollController = null;
    }
    scrollController?.dispose();
    if (notify && mounted) setState(() {});
  }

  void _close({bool notify = true, bool immediate = false}) {
    if (_keyHandler != null) {
      HardwareKeyboard.instance.removeHandler(_keyHandler!);
      _keyHandler = null;
    }
    final entry = _entry;
    final scrollController = _scrollController;
    final motion = _motionController;
    if (entry == null) return;

    if (immediate || motion == null) {
      _removeOverlayNow(
        entry: entry,
        scrollController: scrollController,
        notify: notify,
      );
      return;
    }

    if (_closing) return;
    _closing = true;
    if (notify && mounted) setState(() {});
    unawaited(
      motion.dismiss().whenComplete(
        () => _removeOverlayNow(
          entry: entry,
          scrollController: scrollController,
          notify: notify,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _anchorKey,
      child: widget.anchorBuilder(context, _isOpen, _toggle),
    );
  }
}

class _DesktopSelectMenu<T> extends StatelessWidget {
  final List<T> items;
  final T value;
  final ScrollController controller;
  final double itemHeight;
  final int visibleItemCount;
  final DesktopSelectLabelBuilder<T> labelBuilder;
  final DesktopSelectLeadingBuilder<T>? leadingBuilder;
  final ValueChanged<T> onSelected;

  const _DesktopSelectMenu({
    required this.items,
    required this.value,
    required this.controller,
    required this.itemHeight,
    required this.visibleItemCount,
    required this.labelBuilder,
    required this.leadingBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final visibleCount = math.min(visibleItemCount, items.length);

    return DesktopPopoverSurface(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: itemHeight * visibleCount,
        child: Scrollbar(
          controller: controller,
          thumbVisibility: items.length > visibleCount,
          child: ListView.builder(
            controller: controller,
            padding: EdgeInsets.zero,
            itemExtent: itemHeight,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _DesktopSelectMenuRow(
                label: labelBuilder(item),
                selected: item == value,
                leadingBuilder: leadingBuilder == null
                    ? null
                    : (context, selected) =>
                        leadingBuilder!(context, item, selected),
                onTap: () => onSelected(item),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DesktopSelectMenuRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget Function(BuildContext context, bool selected)? leadingBuilder;
  final VoidCallback onTap;

  const _DesktopSelectMenuRow({
    required this.label,
    required this.selected,
    required this.leadingBuilder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.tpColors;

    return Material(
      color: selected ? colors.opaqueBrandContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.textPrimary.withValues(
          alpha: colors.isDark ? 0.06 : 0.04,
        ),
        highlightColor: colors.textPrimary.withValues(alpha: 0.06),
        splashColor: colors.brand.withValues(alpha: 0.10),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Center(
                child: leadingBuilder?.call(context, selected) ??
                    (selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: colors.brandInk,
                          )
                        : const SizedBox.shrink()),
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
