import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../models/home_layout.dart';
import '../../theme/theme.dart';
import '../../utils/adaptive_motion.dart';
import '../../utils/haptics.dart';
import '../../utils/motion.dart';
import '../adaptive_context_menu.dart';
import '../design_system/design_system.dart';
import 'home_mobile_reorder_list.dart';

IconData homeWidgetIcon(HomeWidgetId id) => switch (id) {
      HomeWidgetId.campusCard => TpIcons.campusCard,
      HomeWidgetId.todayCourses => TpIcons.course,
      HomeWidgetId.deadlines => TpIcons.deadlines,
      HomeWidgetId.quickActions => TpIcons.activities,
      HomeWidgetId.campusGrades => TpIcons.trophy,
      HomeWidgetId.campusStudyPlan => TpIcons.studyPlan,
      HomeWidgetId.campusBlackboard => TpIcons.graduation,
      HomeWidgetId.campusElrcRecordings => TpIcons.recordings,
      HomeWidgetId.campusEcourse => TpIcons.classroom,
      HomeWidgetId.campusCourseCatalog => TpIcons.course,
      HomeWidgetId.campusCertificates => TpIcons.document,
      HomeWidgetId.campusOaGym => TpIcons.gym,
      HomeWidgetId.campusStudentLeave => TpIcons.building,
      HomeWidgetId.campusHolidayTravel => TpIcons.luggage,
      HomeWidgetId.campusActivities => TpIcons.scan,
      HomeWidgetId.campusJobs => TpIcons.briefcase,
      HomeWidgetId.campusStudentAllowance => TpIcons.allowance,
      HomeWidgetId.campusPnpMinor => TpIcons.pnpMinor,
    };

/// Scope and lifecycle wrapper for the floating mobile drag-reorder proxy inside
/// [HomeMobileReorderList].
///
/// Exposes [animationOf] so [HomeEditableCardFrame] can render an iOS-style
/// lifted card directly around the card bounds (excluding outer list spacing),
/// and invokes [onDisposed] once the drop animation settles and the overlay
/// proxy unmounts cleanly.
class HomeMobileDragProxy extends StatefulWidget {
  const HomeMobileDragProxy({
    super.key,
    required this.animation,
    required this.child,
    this.onDisposed,
  });

  final Animation<double> animation;
  final Widget child;
  final VoidCallback? onDisposed;

  static Animation<double>? animationOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_HomeMobileDragProxyScope>()
        ?.animation;
  }

  @override
  State<HomeMobileDragProxy> createState() => _HomeMobileDragProxyState();
}

class _HomeMobileDragProxyState extends State<HomeMobileDragProxy> {
  @override
  void dispose() {
    widget.onDisposed?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HomeMobileDragProxyScope(
      animation: widget.animation,
      child: widget.child,
    );
  }
}

class _HomeMobileDragProxyScope extends InheritedWidget {
  const _HomeMobileDragProxyScope({
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  @override
  bool updateShouldNotify(covariant _HomeMobileDragProxyScope oldWidget) =>
      oldWidget.animation != animation;
}

/// Wraps a Home dashboard widget with adaptive customization chrome:
///
/// - Mobile (`isDesktopMode == false`): touching and holding a card charges a
///   subtle scale-down + haptic + perimeter halo (`home.hold-halo-*`) and lifts
///   into continuous drag-to-reorder without interrupting immediate vertical
///   scroll swipes. In edit mode, the header toolbar exposes remove/options/drag
///   handle (`0ms`) while holding anywhere on the card body also drags cleanly.
/// - Desktop (`isDesktopMode == true`): right-clicking opens a context menu and
///   pressing/holding lets the parent drag directly with a quiet press cue; in
///   edit mode an editorial toolbar exposes move/swap/style/remove controls.
class HomeEditableCardFrame extends StatefulWidget {
  const HomeEditableCardFrame({
    super.key,
    required this.id,
    required this.index,
    required this.itemCount,
    required this.isEditing,
    required this.child,
    this.isDesktopMode = false,
    this.enableReorderDragHandle = false,
    this.column,
    this.campusCardStyle,
    this.onCampusCardStyleChanged,
    this.onConfigureQuickActions,
    this.onEnterEditMode,
    this.onMoveUp,
    this.onMoveDown,
    this.onSwapColumn,
    this.onRemove,
  });

  final HomeWidgetId id;
  final int index;
  final int itemCount;
  final bool isEditing;
  final Widget child;
  final bool isDesktopMode;
  final bool enableReorderDragHandle;
  final HomeBentoColumn? column;
  final HomeCampusCardStyle? campusCardStyle;
  final ValueChanged<HomeCampusCardStyle>? onCampusCardStyleChanged;
  final VoidCallback? onConfigureQuickActions;
  final VoidCallback? onEnterEditMode;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onSwapColumn;
  final VoidCallback? onRemove;

  @override
  State<HomeEditableCardFrame> createState() => _HomeEditableCardFrameState();
}

class _HomeEditableCardFrameState extends State<HomeEditableCardFrame> {
  Future<void> _showDesktopContextMenu(TapDownDetails details) async {
    final meta = homeWidgetMetaFor(widget.id);

    final action = await showAdaptiveContextMenu<String>(
      context: context,
      globalPosition: details.globalPosition,
      items: [
        if (!widget.isEditing && widget.onEnterEditMode != null)
          const AdaptiveContextMenuItem<String>(
            value: 'edit',
            icon: TpIcons.dashboard,
            sfSymbol: 'square.grid.2x2',
            label: '编辑主页布局',
          ),
        if (widget.id == HomeWidgetId.campusCard &&
            widget.campusCardStyle != null &&
            widget.onCampusCardStyleChanged != null)
          AdaptiveContextMenuItem<String>(
            value: 'toggle_card_style',
            icon: TpIcons.campusCard,
            sfSymbol: 'creditcard',
            label: widget.campusCardStyle == HomeCampusCardStyle.full
                ? '切换为精简校园卡'
                : '切换为完整校园卡',
          ),
        if (widget.id == HomeWidgetId.quickActions &&
            widget.onConfigureQuickActions != null)
          AdaptiveContextMenuItem<String>(
            value: 'configure_quick_actions',
            icon: TpIcons.sliders,
            sfSymbol: 'slider.horizontal.3',
            label: '定制${meta.title}',
          ),
        if (widget.onSwapColumn != null)
          AdaptiveContextMenuItem<String>(
            value: 'swap_column',
            icon: TpIcons.swapColumns,
            sfSymbol: 'arrow.left.arrow.right',
            label: widget.column == HomeBentoColumn.primary
                ? '移至副栏'
                : '移至主栏',
          ),
        if (widget.onRemove != null)
          AdaptiveContextMenuItem<String>(
            value: 'remove',
            icon: TpIcons.minus,
            sfSymbol: 'eye.slash',
            label: '隐藏${meta.title}',
            destructive: true,
          ),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        widget.onEnterEditMode?.call();
      case 'toggle_card_style':
        final next = widget.campusCardStyle == HomeCampusCardStyle.full
            ? HomeCampusCardStyle.compact
            : HomeCampusCardStyle.full;
        widget.onCampusCardStyleChanged?.call(next);
      case 'configure_quick_actions':
        widget.onConfigureQuickActions?.call();
      case 'swap_column':
        widget.onSwapColumn?.call();
      case 'remove':
        widget.onRemove?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final duration = appAnimationDuration(
      context,
      const Duration(milliseconds: 180),
    );
    final canMoveUp = widget.index > 0 && widget.onMoveUp != null;
    final canMoveDown =
        widget.index < widget.itemCount - 1 && widget.onMoveDown != null;
    final proxyAnimation =
        widget.isDesktopMode ? null : HomeMobileDragProxy.animationOf(context);
    final isProxy = proxyAnimation != null;

    final content = AbsorbPointer(
      absorbing: widget.isEditing || isProxy,
      child: widget.child,
    );

    if (!widget.isEditing) {
      if (widget.isDesktopMode) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: _showDesktopContextMenu,
          child: _HomeHoldAffordance(
            id: widget.id,
            enabled: true,
            desktopMode: true,
            immediateScale: 1.0,
            chargedScale: 0.986,
            child: content,
          ),
        );
      }
      if (isProxy) {
        return _HomeDragProxyVisual(
          animation: proxyAnimation,
          borderRadius: BorderRadius.circular(TpTokens.radiusL),
          child: content,
        );
      }
      return HomeMobileDelayedDragStartListener(
        index: widget.index,
        delay: const Duration(milliseconds: 360),
        child: _HomeHoldAffordance(
          id: widget.id,
          enabled: true,
          desktopMode: false,
          immediateScale: widget.id == HomeWidgetId.campusCard ? 0.992 : 0.98,
          chargedScale: 0.968,
          child: content,
        ),
      );
    }

    final dragHandleIcon = Icon(
      TpIcons.dragHandle,
      key: ValueKey('home.drag-handle-${widget.id.key}'),
      size: TpTokens.iconS,
      color: colors.textMuted,
    );

    final dragHandle = widget.enableReorderDragHandle && !isProxy
        ? Semantics(
            label: '拖动调整${homeWidgetMetaFor(widget.id).title}顺序',
            child: HomeMobileDragStartListener(
              index: widget.index,
              child: ColoredBox(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TpTokens.space2 + 2,
                    vertical: TpTokens.space1 + 2,
                  ),
                  child: dragHandleIcon,
                ),
              ),
            ),
          )
        : Tooltip(
            message: '拖动调整位置',
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space1,
                  vertical: TpTokens.space1,
                ),
                child: dragHandleIcon,
              ),
            ),
          );

    final canDelayedBodyDrag =
        !widget.isDesktopMode && widget.enableReorderDragHandle && !isProxy;
    const editDragDelay = Duration(milliseconds: 220);

    final bodyContent = canDelayedBodyDrag
        ? HomeMobileDelayedDragStartListener(
            index: widget.index,
            delay: editDragDelay,
            child: _HomeHoldAffordance(
              id: widget.id,
              enabled: true,
              desktopMode: false,
              chargeDelay: const Duration(milliseconds: 80),
              chargeDuration: const Duration(milliseconds: 140),
              immediateScale: 0.992,
              chargedScale: 0.978,
              child: content,
            ),
          )
        : content;

    final frame = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: colors.surfaceSubtle.withValues(alpha: colors.isDark ? 0.55 : 0.72),
        borderRadius: BorderRadius.circular(TpTokens.radiusL + 2),
        border: Border.all(
          color: colors.brandInk.withValues(alpha: colors.isDark ? 0.45 : 0.30),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(TpTokens.space2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: TpTokens.space1,
              right: TpTokens.space1,
              bottom: TpTokens.space2,
            ),
            child: _EditHeaderRow(
              id: widget.id,
              isDesktopMode: widget.isDesktopMode,
              column: widget.column,
              canMoveUp: canMoveUp,
              canMoveDown: canMoveDown,
              campusCardStyle: widget.campusCardStyle,
              onCampusCardStyleChanged: widget.onCampusCardStyleChanged,
              onConfigureQuickActions: widget.onConfigureQuickActions,
              onMoveUp: widget.onMoveUp,
              onMoveDown: widget.onMoveDown,
              onSwapColumn: widget.onSwapColumn,
              onRemove: widget.onRemove,
              dragHandle: dragHandle,
              delayedDragIndex: canDelayedBodyDrag ? widget.index : null,
              delayedDragDelay: canDelayedBodyDrag ? editDragDelay : null,
            ),
          ),
          bodyContent,
        ],
      ),
    );

    if (isProxy) {
      return _HomeDragProxyVisual(
        animation: proxyAnimation,
        borderRadius: BorderRadius.circular(TpTokens.radiusL + 2),
        child: frame,
      );
    }
    return frame;
  }
}

class _HomeDragProxyVisual extends StatelessWidget {
  const _HomeDragProxyVisual({
    required this.animation,
    required this.borderRadius,
    required this.child,
  });

  final Animation<double> animation;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(animation.value);
            final scale = reduceMotion ? 1.0 : lerpDouble(1.0, 1.028, t)!;
            final opacity = lerpDouble(1.0, 0.92, t)!;

            return Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Opacity(
                opacity: opacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    boxShadow: [
                      if (t > 0.01)
                        BoxShadow(
                          color: colors.textPrimary.withValues(
                            alpha: (colors.isDark ? 0.34 : 0.16) * t,
                          ),
                          blurRadius: 22 * t,
                          offset: Offset(0, 10 * t),
                        ),
                    ],
                  ),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(
                        color: colors.brandInk.withValues(
                          alpha: (colors.isDark ? 0.55 : 0.44) * t,
                        ),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: borderRadius,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
          child: child,
        ),
      ),
    );
  }
}

/// Passive touch/hold tactile affordance for Home dashboard widgets outside edit
/// mode. Never competes in the gesture arena so clicks and scrolling behave
/// identically while stationary holds feel responsive and alive.
class _HomeHoldAffordance extends StatefulWidget {
  const _HomeHoldAffordance({
    required this.id,
    required this.enabled,
    required this.desktopMode,
    required this.immediateScale,
    required this.chargedScale,
    required this.child,
    this.chargeDelay = const Duration(milliseconds: 120),
    this.chargeDuration = const Duration(milliseconds: 220),
  });

  final HomeWidgetId id;
  final bool enabled;
  final bool desktopMode;
  final double immediateScale;
  final double chargedScale;
  final Duration chargeDelay;
  final Duration chargeDuration;
  final Widget child;

  @override
  State<_HomeHoldAffordance> createState() => _HomeHoldAffordanceState();
}

class _HomeHoldAffordanceState extends State<_HomeHoldAffordance>
    with TickerProviderStateMixin {
  late final AnimationController _scale;
  late final AnimationController _charge;

  Timer? _chargeTimer;
  int? _activePointer;
  Offset? _downPosition;
  bool _pressed = false;
  bool _charging = false;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController.unbounded(vsync: this, value: 1.0);
    _charge = AnimationController(
      vsync: this,
      duration: widget.chargeDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion && (_pressed || _charging)) {
      _resetImmediate();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeHoldAffordance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chargeDuration != widget.chargeDuration) {
      _charge.duration = widget.chargeDuration;
    }
    if (!widget.enabled) {
      _release();
    }
  }

  @override
  void dispose() {
    _chargeTimer?.cancel();
    _scale.dispose();
    _charge.dispose();
    super.dispose();
  }

  void _resetImmediate() {
    _chargeTimer?.cancel();
    _chargeTimer = null;
    _activePointer = null;
    _downPosition = null;
    _pressed = false;
    _charging = false;
    _scale.value = 1.0;
    _charge.value = 0.0;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _reduceMotion || _activePointer != null) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _activePointer = event.pointer;
    _downPosition = event.position;
    _pressed = true;
    _charging = false;

    if (!widget.desktopMode && widget.immediateScale < 1.0) {
      unawaited(
        _scale.animateTo(
          widget.immediateScale,
          duration: const Duration(milliseconds: 75),
          curve: Curves.easeOutCubic,
        ),
      );
    }

    _chargeTimer?.cancel();
    _chargeTimer = Timer(
      widget.desktopMode
          ? const Duration(milliseconds: 110)
          : widget.chargeDelay,
      _beginHoldCharge,
    );
  }

  void _beginHoldCharge() {
    if (!mounted || !_pressed) return;
    _charging = true;
    if (!widget.desktopMode) {
      unawaited(AppHaptics.play(AppHaptics.selection));
    }
    unawaited(
      _scale.animateTo(
        widget.chargedScale,
        duration: widget.chargeDuration,
        curve: Curves.easeOutCubic,
      ),
    );
    unawaited(_charge.forward(from: _charge.value));
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pressed || event.pointer != _activePointer || _downPosition == null) {
      return;
    }
    if ((event.position - _downPosition!).distance > kTouchSlop) {
      _release();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _release();
  }

  void _release() {
    _chargeTimer?.cancel();
    _chargeTimer = null;
    _activePointer = null;
    _downPosition = null;
    if (!_pressed && !_charging) return;
    _pressed = false;
    _charging = false;
    if (!mounted) return;
    if (_reduceMotion) {
      _scale.value = 1.0;
      _charge.value = 0.0;
      return;
    }
    unawaited(
      _charge.animateBack(
        0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      ),
    );
    unawaited(
      _scale
          .animateWith(
            SpringSimulation(TgMotion.tactileSpring, _scale.value, 1.0, 0),
          )
          .whenComplete(() {
        if (mounted && !_pressed) _scale.value = 1.0;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion) {
      return widget.child;
    }
    final colors = context.tpColors;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_scale, _charge]),
        builder: (context, child) {
          final rawScale = _scale.value;
          final scale = (rawScale - 1.0).abs() < 1e-4 ? 1.0 : rawScale;
          final progress = _charge.value;

          return Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                child!,
                if (progress > 0.01)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: ValueKey('home.hold-halo-${widget.id.key}'),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(TpTokens.radiusM),
                          color: colors.brandSoft
                              .withValues(alpha: 0.14 * progress),
                          border: Border.all(
                            color: colors.brandInk
                                .withValues(alpha: 0.45 * progress),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.brandInk
                                  .withValues(alpha: 0.12 * progress),
                              blurRadius: 10 * progress,
                              spreadRadius: 0.5 * progress,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _EditHeaderRow extends StatelessWidget {
  const _EditHeaderRow({
    required this.id,
    required this.isDesktopMode,
    required this.column,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.campusCardStyle,
    required this.onCampusCardStyleChanged,
    required this.onConfigureQuickActions,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onSwapColumn,
    required this.onRemove,
    required this.dragHandle,
    this.delayedDragIndex,
    this.delayedDragDelay,
  });

  final HomeWidgetId id;
  final bool isDesktopMode;
  final HomeBentoColumn? column;
  final bool canMoveUp;
  final bool canMoveDown;
  final HomeCampusCardStyle? campusCardStyle;
  final ValueChanged<HomeCampusCardStyle>? onCampusCardStyleChanged;
  final VoidCallback? onConfigureQuickActions;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onSwapColumn;
  final VoidCallback? onRemove;
  final Widget dragHandle;
  final int? delayedDragIndex;
  final Duration? delayedDragDelay;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final meta = homeWidgetMetaFor(id);

    Widget titleRegion = Row(
      children: [
        Icon(homeWidgetIcon(id), size: TpTokens.iconXs, color: colors.brandInk),
        const SizedBox(width: TpTokens.space1 + 2),
        Expanded(
          child: Text(
            meta.title,
            style: TpTypography.cardMeta(colors).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (delayedDragIndex != null && delayedDragDelay != null) {
      titleRegion = HomeMobileDelayedDragStartListener(
        index: delayedDragIndex!,
        delay: delayedDragDelay!,
        child: ColoredBox(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: titleRegion,
          ),
        ),
      );
    }

    return Row(
      children: [
        if (onRemove != null) ...[
          _RemoveWidgetButton(
            widgetId: id,
            title: meta.title,
            onPressed: onRemove!,
          ),
          const SizedBox(width: TpTokens.space1 + 2),
        ],
        Expanded(child: titleRegion),
        if (id == HomeWidgetId.campusCard &&
            campusCardStyle != null &&
            onCampusCardStyleChanged != null) ...[
          const SizedBox(width: TpTokens.space1),
          _CampusCardStyleSegmented(
            current: campusCardStyle!,
            onChanged: onCampusCardStyleChanged!,
          ),
        ],
        if (id == HomeWidgetId.quickActions &&
            onConfigureQuickActions != null) ...[
          const SizedBox(width: TpTokens.space1),
          _ToolbarChipButton(
            key: const ValueKey('home.configure-quick-actions'),
            icon: TpIcons.sliders,
            label: '定制',
            onTap: onConfigureQuickActions!,
          ),
        ],
        if (isDesktopMode) ...[
          _SmallIconAction(
            key: ValueKey('home.move-up-${id.key}'),
            icon: TpIcons.arrowUp,
            tooltip: '上移',
            onPressed: canMoveUp ? onMoveUp : null,
          ),
          _SmallIconAction(
            key: ValueKey('home.move-down-${id.key}'),
            icon: TpIcons.arrowDown,
            tooltip: '下移',
            onPressed: canMoveDown ? onMoveDown : null,
          ),
          if (onSwapColumn != null)
            _SmallIconAction(
              key: ValueKey('home.swap-column-${id.key}'),
              icon: TpIcons.swapColumns,
              tooltip:
                  column == HomeBentoColumn.primary ? '移至副栏' : '移至主栏',
              onPressed: onSwapColumn,
            ),
        ],
        dragHandle,
      ],
    );
  }
}

class _RemoveWidgetButton extends StatelessWidget {
  const _RemoveWidgetButton({
    required this.widgetId,
    required this.title,
    required this.onPressed,
  });

  final HomeWidgetId widgetId;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Semantics(
      button: true,
      label: '移除$title',
      child: Tooltip(
        message: '移除$title',
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: TpPressScale(
              pressedScale: 0.88,
              child: Material(
                color: colors.dangerRed
                    .withValues(alpha: colors.isDark ? 0.22 : 0.12),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: TpTapSurface(
                  key: ValueKey('home.remove-${widgetId.key}'),
                  style: TpTapFeedbackStyle.button,
                  customBorder: const CircleBorder(),
                  pressedColor: colors.dangerRed,
                  enablePressScale: false,
                  onTap: () {
                    unawaited(AppHaptics.play(AppHaptics.lightImpact));
                    onPressed();
                  },
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(
                      TpIcons.minus,
                      size: 14,
                      color: colors.dangerRed,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CampusCardStyleSegmented extends StatelessWidget {
  const _CampusCardStyleSegmented({
    required this.current,
    required this.onChanged,
  });

  final HomeCampusCardStyle current;
  final ValueChanged<HomeCampusCardStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TpTokens.radiusPill),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SegmentChoice(
            key: const ValueKey('home.campus-card-style-compact'),
            label: '精简',
            selected: current == HomeCampusCardStyle.compact,
            onTap: () {
              if (current == HomeCampusCardStyle.compact) return;
              unawaited(AppHaptics.play(AppHaptics.selection));
              onChanged(HomeCampusCardStyle.compact);
            },
          ),
          _SegmentChoice(
            key: const ValueKey('home.campus-card-style-full'),
            label: '完整',
            selected: current == HomeCampusCardStyle.full,
            onTap: () {
              if (current == HomeCampusCardStyle.full) return;
              unawaited(AppHaptics.play(AppHaptics.selection));
              onChanged(HomeCampusCardStyle.full);
            },
          ),
        ],
      ),
    );
  }
}

class _SegmentChoice extends StatelessWidget {
  const _SegmentChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusPill);
    final duration = appAnimationDuration(
      context,
      const Duration(milliseconds: 160),
    );
    return TpTapSurface(
      style: TpTapFeedbackStyle.button,
      borderRadius: radius,
      pressedColor: selected ? colors.onBrand : null,
      pressedScale: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.brandInk : Colors.transparent,
          borderRadius: radius,
        ),
        child: Text(
          label,
          style: TpTypography.badge(
            selected ? colors.onBrand : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ToolbarChipButton extends StatelessWidget {
  const _ToolbarChipButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Semantics(
      button: true,
      label: label,
      child: TpPressScale(
        pressedScale: 0.94,
        child: Material(
          color: colors.surface,
          shape: StadiumBorder(side: BorderSide(color: colors.divider)),
          clipBehavior: Clip.antiAlias,
          child: TpTapSurface(
            style: TpTapFeedbackStyle.button,
            customBorder: const StadiumBorder(),
            enablePressScale: false,
            onTap: () {
              unawaited(AppHaptics.play(AppHaptics.lightImpact));
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: colors.brandInk),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TpTypography.badge(colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallIconAction extends StatelessWidget {
  const _SmallIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: 13,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              icon,
              size: 14,
              color: enabled
                  ? colors.textSecondary
                  : colors.textMuted.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}
