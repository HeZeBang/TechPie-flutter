import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../utils/haptics.dart';

/// Purpose-built vertical reorderable column for the Home mobile dashboard.
///
/// Replaces `SliverReorderableList` for Home's 1–4 heterogeneous-height cards
/// so dragging a taller card (e.g. Today's Courses) past a much shorter compact
/// card (e.g. Campus Card) never snaps back or stalls when overshooting above
/// the top edge. Supports immediate vertical scroll outside/inside edit mode
/// via [HomeMobileDelayedDragStartListener] alongside instant (`0ms`) handles
/// via [HomeMobileDragStartListener].
class HomeMobileReorderList extends StatefulWidget {
  const HomeMobileReorderList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.proxyDecorator,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ReorderCallback onReorder;
  final void Function(int index)? onReorderStart;
  final void Function(int index)? onReorderEnd;
  final ReorderItemProxyDecorator? proxyDecorator;

  static HomeMobileReorderListState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<HomeMobileReorderListState>();
  }

  @override
  State<HomeMobileReorderList> createState() => HomeMobileReorderListState();
}

class HomeMobileReorderListState extends State<HomeMobileReorderList>
    with TickerProviderStateMixin {
  final List<GlobalKey> _itemKeys = [];

  ScrollableState? _scrollable;
  EdgeDraggingAutoScroller? _autoScroller;

  MultiDragGestureRecognizer? _recognizer;
  PointerDownEvent? _lastDownEvent;
  int? _pendingDragIndex;

  OverlayEntry? _overlayEntry;
  AnimationController? _proxyAnimation;
  int? _dragIndex;
  int? _targetIndex;
  List<double> _itemHeights = const [];
  Size _dragItemSize = Size.zero;
  BoxConstraints _dragItemConstraints = const BoxConstraints();
  double _dragItemLeft = 0;
  double _listTopAtStart = 0;
  double _scrollOffsetAtStart = 0;
  Offset _dragOffset = Offset.zero;
  Offset _dragPosition = Offset.zero;

  bool _isDropping = false;
  double _dropStartTop = 0;
  double _dropEndTop = 0;

  @override
  void initState() {
    super.initState();
    _syncItemKeys();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      _autoScroller?.stopAutoScroll();
      _scrollable = scrollable;
      _autoScroller = scrollable == null
          ? null
          : EdgeDraggingAutoScroller(
              scrollable,
              onScrollViewScrolled: _handleAutoScrolled,
              velocityScalar: 50,
            );
    }
  }

  @override
  void didUpdateWidget(covariant HomeMobileReorderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount) {
      cancelReorder();
      _syncItemKeys();
    }
  }

  @override
  void dispose() {
    _clearDragResources();
    _recognizer?.dispose();
    _recognizer = null;
    _lastDownEvent = null;
    super.dispose();
  }

  void _syncItemKeys() {
    while (_itemKeys.length < widget.itemCount) {
      _itemKeys.add(GlobalKey());
    }
    if (_itemKeys.length > widget.itemCount) {
      _itemKeys.removeRange(widget.itemCount, _itemKeys.length);
    }
  }

  /// Registers a drag recognizer for [index] from [event].
  ///
  /// When a pointer hits a nested inner drag listener first (such as the `0ms`
  /// corner handle inside a delayed-drag header), the outer listener for the
  /// same pointer yields cleanly without clobbering the inner recognizer.
  void startItemDragReorder({
    required int index,
    required PointerDownEvent event,
    required MultiDragGestureRecognizer recognizer,
  }) {
    if (index < 0 || index >= widget.itemCount) {
      recognizer.dispose();
      return;
    }
    if (identical(_lastDownEvent, event)) {
      recognizer.dispose();
      return;
    }
    if (_dragIndex != null) {
      cancelReorder();
    }
    if (_recognizer != null) {
      _recognizer!.dispose();
      _recognizer = null;
    }

    _lastDownEvent = event;
    _pendingDragIndex = index;
    _recognizer = recognizer
      ..onStart = _dragStart
      ..addPointer(event);
  }

  /// Cancels any active drag and restores list geometry without committing.
  void cancelReorder() {
    if (_dragIndex == null && _overlayEntry == null && _proxyAnimation == null) {
      return;
    }
    _clearDragResources();
    if (mounted) {
      setState(() {});
    }
  }

  void _clearDragResources() {
    _autoScroller?.stopAutoScroll();
    _dragIndex = null;
    _targetIndex = null;
    _pendingDragIndex = null;
    _itemHeights = const [];
    _isDropping = false;
    _proxyAnimation?.dispose();
    _proxyAnimation = null;
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  Drag? _dragStart(Offset initialPosition) {
    final index = _pendingDragIndex;
    if (!mounted || index == null || index < 0 || index >= widget.itemCount) {
      return null;
    }

    final listBox = context.findRenderObject();
    if (listBox is! RenderBox || !listBox.hasSize) return null;

    final heights = <double>[];
    for (var i = 0; i < widget.itemCount; i++) {
      final ro = _itemKeys[i].currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) return null;
      heights.add(ro.size.height);
    }

    final dragBox = _itemKeys[index].currentContext?.findRenderObject();
    if (dragBox is! RenderBox || !dragBox.hasSize) return null;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return null;

    final capturedThemes = InheritedTheme.capture(
      from: context,
      to: overlay.context,
    );
    final capturedChild = widget.itemBuilder(context, index);

    _dragIndex = index;
    _targetIndex = index;
    _itemHeights = heights;
    _dragItemSize = dragBox.size;
    _dragItemConstraints = dragBox.constraints;
    _dragItemLeft = dragBox.localToGlobal(Offset.zero).dx;
    _listTopAtStart = listBox.localToGlobal(Offset.zero).dy;
    _scrollOffsetAtStart = _scrollable?.position.pixels ?? 0.0;
    _dragOffset = dragBox.globalToLocal(initialPosition);
    _dragPosition = initialPosition;
    _isDropping = false;

    _proxyAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addStatusListener((status) {
        if (status.isDismissed && _isDropping) {
          _dropCompleted();
        }
      });
    unawaited(_proxyAnimation!.forward());

    widget.onReorderStart?.call(index);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => _buildProxyOverlay(
        overlayContext,
        index: index,
        capturedThemes: capturedThemes,
        child: capturedChild,
      ),
    );
    overlay.insert(_overlayEntry!);

    if (mounted) {
      setState(() {});
    }

    return _MobileItemDrag(
      onUpdate: _dragUpdate,
      onEnd: _dragEnd,
      onCancel: _dragCancel,
    );
  }

  double get _currentListTop {
    final currentScroll = _scrollable?.position.pixels ?? _scrollOffsetAtStart;
    return _listTopAtStart - (currentScroll - _scrollOffsetAtStart);
  }

  List<double> _otherHeightsForDrag() {
    return [
      for (var i = 0; i < _itemHeights.length; i++)
        if (i != _dragIndex) _itemHeights[i],
    ];
  }

  double _gapTopForTarget(int targetIndex, List<double> otherHeights) {
    var top = _currentListTop;
    for (var i = 0; i < targetIndex && i < otherHeights.length; i++) {
      top += otherHeights[i];
    }
    return top;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_dragIndex == null || _isDropping) return;
    _dragPosition += Offset(0, details.delta.dy);
    _recomputeTargetIndex();
    _overlayEntry?.markNeedsBuild();
    _autoScroller?.startAutoScrollIfNecessary(_dragTargetRect());
  }

  void _handleAutoScrolled() {
    if (_dragIndex == null || _isDropping) return;
    _recomputeTargetIndex();
    _overlayEntry?.markNeedsBuild();
    _autoScroller?.startAutoScrollIfNecessary(_dragTargetRect());
  }

  Rect _dragTargetRect() {
    return Rect.fromLTWH(
      _dragItemLeft,
      _dragPosition.dy - _dragOffset.dy,
      _dragItemSize.width,
      _dragItemSize.height,
    );
  }

  void _recomputeTargetIndex() {
    final dragIndex = _dragIndex;
    final initialTarget = _targetIndex;
    if (dragIndex == null || initialTarget == null || _itemHeights.isEmpty) {
      return;
    }

    var target = initialTarget;
    final dragH = _itemHeights[dragIndex];
    final proxyTop = _dragPosition.dy - _dragOffset.dy;
    final proxyBottom = proxyTop + dragH;
    final otherHeights = _otherHeightsForDrag();
    var gapTop = _gapTopForTarget(target, otherHeights);
    const hysteresis = 4.0;

    while (target > 0) {
      final hAbove = otherHeights[target - 1];
      if (proxyTop < gapTop - hAbove * 0.5 - hysteresis) {
        target -= 1;
        gapTop -= hAbove;
      } else {
        break;
      }
    }

    while (target < otherHeights.length) {
      final hBelow = otherHeights[target];
      if (proxyBottom > gapTop + dragH + hBelow * 0.5 + hysteresis) {
        target += 1;
        gapTop += hBelow;
      } else {
        break;
      }
    }

    if (target != _targetIndex) {
      _targetIndex = target;
      unawaited(AppHaptics.play(AppHaptics.selection));
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _dragEnd(DragEndDetails details) {
    final dragIndex = _dragIndex;
    final targetIndex = _targetIndex;
    if (dragIndex == null || targetIndex == null) return;

    _autoScroller?.stopAutoScroll();
    final otherHeights = _otherHeightsForDrag();
    _dropStartTop = _dragPosition.dy - _dragOffset.dy;
    _dropEndTop = _gapTopForTarget(targetIndex, otherHeights);
    _isDropping = true;

    final callbackNewIndex = targetIndex > dragIndex ? targetIndex + 1 : targetIndex;
    widget.onReorderEnd?.call(callbackNewIndex);

    final anim = _proxyAnimation;
    if (anim == null || anim.value == 0.0) {
      _dropCompleted();
    } else {
      unawaited(anim.reverse());
    }
  }

  void _dragCancel() {
    cancelReorder();
  }

  void _dropCompleted() {
    final fromIndex = _dragIndex;
    final toIndex = _targetIndex;
    _clearDragResources();
    _recognizer?.dispose();
    _recognizer = null;
    _lastDownEvent = null;

    if (fromIndex != null && toIndex != null && fromIndex != toIndex) {
      final callbackNewIndex = toIndex > fromIndex ? toIndex + 1 : toIndex;
      widget.onReorder(fromIndex, callbackNewIndex);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildProxyOverlay(
    BuildContext context, {
    required int index,
    required CapturedThemes capturedThemes,
    required Widget child,
  }) {
    final anim = _proxyAnimation;
    if (anim == null) return const SizedBox.shrink();

    final overlayBox = Overlay.of(
      this.context,
      debugRequiredFor: widget,
    ).context.findRenderObject();
    final overlayOrigin =
        overlayBox is RenderBox ? overlayBox.localToGlobal(Offset.zero) : Offset.zero;

    final decorated =
        widget.proxyDecorator?.call(child, index, anim.view) ?? child;

    return capturedThemes.wrap(
      MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: AnimatedBuilder(
          animation: anim,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(anim.value);
            final top = _isDropping
                ? lerpDouble(_dropEndTop, _dropStartTop, t)!
                : (_dragPosition.dy - _dragOffset.dy);
            return Positioned(
              left: _dragItemLeft - overlayOrigin.dx,
              top: top - overlayOrigin.dy,
              child: SizedBox(
                width: _dragItemSize.width,
                height: _dragItemSize.height,
                child: OverflowBox(
                  minWidth: _dragItemConstraints.minWidth,
                  minHeight: _dragItemConstraints.minHeight,
                  maxWidth: _dragItemConstraints.maxWidth,
                  maxHeight: _dragItemConstraints.maxHeight,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              ),
            );
          },
          child: decorated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDrag = _dragIndex != null;
    final dragIndex = _dragIndex;
    final targetIndex = _targetIndex;
    final dragHeight = activeDrag && dragIndex! < _itemHeights.length
        ? _itemHeights[dragIndex]
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.itemCount; i++)
          if (activeDrag && i == dragIndex)
            SizedBox(
              key: ValueKey('home.reorder-gap-$i'),
              height: dragHeight,
            )
          else
            _ReorderGapSlide(
              key: ValueKey('home.reorder-slot-$i'),
              active: activeDrag,
              targetOffset: !activeDrag
                  ? 0.0
                  : (targetIndex! < dragIndex! && i >= targetIndex && i < dragIndex)
                      ? dragHeight
                      : (targetIndex > dragIndex &&
                              i > dragIndex &&
                              i <= targetIndex)
                          ? -dragHeight
                          : 0.0,
              child: KeyedSubtree(
                key: _itemKeys[i],
                child: widget.itemBuilder(context, i),
              ),
            ),
      ],
    );
  }
}

class _ReorderGapSlide extends StatefulWidget {
  const _ReorderGapSlide({
    super.key,
    required this.active,
    required this.targetOffset,
    required this.child,
  });

  final bool active;
  final double targetOffset;
  final Widget child;

  @override
  State<_ReorderGapSlide> createState() => _ReorderGapSlideState();
}

class _ReorderGapSlideState extends State<_ReorderGapSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _startOffset = 0.0;
  double _currentTarget = 0.0;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() {}));
    _currentTarget = widget.active ? widget.targetOffset : 0.0;
    _startOffset = _currentTarget;
    if (_currentTarget != 0.0) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _ReorderGapSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _controller.stop();
      _controller.value = 0.0;
      _startOffset = 0.0;
      _currentTarget = 0.0;
      return;
    }
    if (widget.targetOffset != _currentTarget) {
      if (_reduceMotion) {
        _controller.stop();
        _controller.value = 1.0;
        _startOffset = widget.targetOffset;
        _currentTarget = widget.targetOffset;
        return;
      }
      _startOffset = _resolvedOffset;
      _currentTarget = widget.targetOffset;
      unawaited(_controller.forward(from: 0.0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _resolvedOffset {
    if (!widget.active) return 0.0;
    if (!_controller.isAnimating && _startOffset == _currentTarget) {
      return _currentTarget;
    }
    final t = Curves.easeOutCubic.transform(_controller.value);
    return lerpDouble(_startOffset, _currentTarget, t) ?? _currentTarget;
  }

  @override
  Widget build(BuildContext context) {
    final dy = _resolvedOffset;
    if (dy == 0.0) return widget.child;
    return Transform.translate(
      offset: Offset(0, dy),
      child: widget.child,
    );
  }
}

class _MobileItemDrag extends Drag {
  _MobileItemDrag({
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final void Function(DragUpdateDetails details) onUpdate;
  final void Function(DragEndDetails details) onEnd;
  final VoidCallback onCancel;

  @override
  void update(DragUpdateDetails details) => onUpdate(details);

  @override
  void end(DragEndDetails details) => onEnd(details);

  @override
  void cancel() => onCancel();
}

/// Initiates an immediate (`0ms`) reorder drag inside [HomeMobileReorderList].
class HomeMobileDragStartListener extends StatelessWidget {
  const HomeMobileDragStartListener({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final Widget child;
  final bool enabled;

  @protected
  MultiDragGestureRecognizer createRecognizer() {
    return ImmediateMultiDragGestureRecognizer(debugOwner: this);
  }

  void _startDragging(BuildContext context, PointerDownEvent event) {
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    HomeMobileReorderList.maybeOf(context)?.startItemDragReorder(
      index: index,
      event: event,
      recognizer: createRecognizer()..gestureSettings = gestureSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: enabled ? (event) => _startDragging(context, event) : null,
      child: child,
    );
  }
}

/// Initiates a reorder drag after [delay] so immediate vertical swipes scroll
/// the parent view cleanly without triggering reorder.
class HomeMobileDelayedDragStartListener extends HomeMobileDragStartListener {
  const HomeMobileDelayedDragStartListener({
    super.key,
    required super.index,
    required super.child,
    required this.delay,
    super.enabled,
  });

  final Duration delay;

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: delay,
      debugOwner: this,
    );
  }
}
