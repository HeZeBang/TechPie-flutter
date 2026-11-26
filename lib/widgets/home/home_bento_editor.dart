import 'package:flutter/material.dart';

import '../../models/home_layout.dart';
import '../../theme/theme.dart';
import '../../utils/adaptive_motion.dart';
import 'home_widget_chrome.dart';

/// Builds a rendered card widget for a given [HomeWidgetId] in Home.
typedef HomeWidgetCardBuilder = Widget Function(HomeWidgetId id);

/// Dual-column Bento workspace for wide/desktop viewports.
///
/// Renders a single tree-stable Bento structure across view, direct hold-drag,
/// and Edit Mode. Picking up a card automatically enters Edit Mode while
/// carrying a translucent scaled copy of the real card itself and snapping
/// smoothly onto upper/lower card halves or column drop slots.
class HomeBentoEditor extends StatefulWidget {
  const HomeBentoEditor({
    super.key,
    required this.layout,
    required this.isEditing,
    required this.cardBuilder,
    required this.onMoveToSlot,
    required this.onMoveBy,
    required this.onSwapColumn,
    required this.onRemove,
    required this.onEnterEditMode,
    this.onCampusCardStyleChanged,
    this.onConfigureQuickActions,
    this.footerWidget,
  });

  final HomeDesktopLayout layout;
  final bool isEditing;
  final HomeWidgetCardBuilder cardBuilder;
  final void Function(HomeWidgetId id, HomeBentoColumn column, int slotIndex)
      onMoveToSlot;
  final void Function(HomeWidgetId id, int delta) onMoveBy;
  final void Function(HomeWidgetId id) onSwapColumn;
  final void Function(HomeWidgetId id) onRemove;
  final VoidCallback onEnterEditMode;
  final ValueChanged<HomeCampusCardStyle>? onCampusCardStyleChanged;
  final VoidCallback? onConfigureQuickActions;
  final Widget? footerWidget;

  @override
  State<HomeBentoEditor> createState() => _HomeBentoEditorState();
}

typedef _BentoSlotTarget = ({HomeBentoColumn column, int slot});

class _HomeBentoEditorState extends State<HomeBentoEditor> {
  HomeWidgetId? _draggingId;
  _BentoSlotTarget? _hoveredSlot;

  void _setHoveredSlot(HomeBentoColumn column, int slot) {
    final target = (column: column, slot: slot);
    if (_hoveredSlot == target) return;
    setState(() => _hoveredSlot = target);
  }

  void _clearHoveredSlotIf(HomeBentoColumn column, int slot) {
    final target = (column: column, slot: slot);
    if (_hoveredSlot != target) return;
    setState(() => _hoveredSlot = null);
  }

  void _acceptSlot(HomeWidgetId id, HomeBentoColumn column, int slot) {
    setState(() {
      _draggingId = null;
      _hoveredSlot = null;
    });
    widget.onMoveToSlot(id, column, slot);
  }

  Widget _wrapCard(
    HomeWidgetId id,
    HomeBentoColumn column,
    int index,
    int count,
  ) {
    return KeyedSubtree(
      key: ValueKey('home.desktop-card-${id.key}'),
      child: HomeEditableCardFrame(
        id: id,
        index: index,
        itemCount: count,
        isEditing: widget.isEditing,
        isDesktopMode: true,
        column: column,
        campusCardStyle:
            id == HomeWidgetId.campusCard ? widget.layout.campusCardStyle : null,
        onCampusCardStyleChanged: widget.onCampusCardStyleChanged,
        onConfigureQuickActions: widget.onConfigureQuickActions,
        onEnterEditMode: widget.onEnterEditMode,
        onMoveUp: () => widget.onMoveBy(id, -1),
        onMoveDown: () => widget.onMoveBy(id, 1),
        onSwapColumn: () => widget.onSwapColumn(id),
        onRemove: () => widget.onRemove(id),
        child: widget.cardBuilder(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDragging = _draggingId != null;
    final showDropChrome = widget.isEditing || isDragging;
    final hasPrimaryContent =
        widget.layout.primary.isNotEmpty || widget.footerWidget != null;
    final hasSecondaryContent = widget.layout.secondary.isNotEmpty;

    if (!showDropChrome && !hasPrimaryContent && !hasSecondaryContent) {
      return const SizedBox.shrink();
    }

    final showPrimary = showDropChrome || hasPrimaryContent;
    final showSecondary = showDropChrome || hasSecondaryContent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPrimary)
              Expanded(
                key: const ValueKey('home.bento-flex-primary'),
                flex: showSecondary ? 55 : 100,
                child: _BentoColumn(
                  column: HomeBentoColumn.primary,
                  label: '主栏 · 课程与待办',
                  items: widget.layout.primary,
                  isEditing: widget.isEditing,
                  isDragging: isDragging,
                  draggingId: _draggingId,
                  hoveredSlot: _hoveredSlot,
                  buildCard: (id, index, count, columnWidth) =>
                      _buildDraggableCard(
                    id,
                    HomeBentoColumn.primary,
                    index,
                    count,
                    columnWidth,
                  ),
                  onHoverSlot: _setHoveredSlot,
                  onLeaveSlot: _clearHoveredSlotIf,
                  onAcceptSlot: (id, slot) =>
                      _acceptSlot(id, HomeBentoColumn.primary, slot),
                  footer: showDropChrome ? null : widget.footerWidget,
                ),
              ),
            if (showPrimary && showSecondary)
              const SizedBox(
                key: ValueKey('home.bento-column-gap'),
                width: TpTokens.space4,
              ),
            if (showSecondary)
              Expanded(
                key: const ValueKey('home.bento-flex-secondary'),
                flex: showPrimary ? 45 : 100,
                child: _BentoColumn(
                  column: HomeBentoColumn.secondary,
                  label: '副栏 · 卡片与快捷',
                  items: widget.layout.secondary,
                  isEditing: widget.isEditing,
                  isDragging: isDragging,
                  draggingId: _draggingId,
                  hoveredSlot: _hoveredSlot,
                  buildCard: (id, index, count, columnWidth) =>
                      _buildDraggableCard(
                    id,
                    HomeBentoColumn.secondary,
                    index,
                    count,
                    columnWidth,
                  ),
                  onHoverSlot: _setHoveredSlot,
                  onLeaveSlot: _clearHoveredSlotIf,
                  onAcceptSlot: (id, slot) =>
                      _acceptSlot(id, HomeBentoColumn.secondary, slot),
                ),
              ),
          ],
        ),
        if (showDropChrome && widget.footerWidget != null) ...[
          const SizedBox(height: TpTokens.sectionGap),
          widget.footerWidget!,
        ],
      ],
    );
  }

  Widget _buildDraggableCard(
    HomeWidgetId id,
    HomeBentoColumn column,
    int index,
    int count,
    double columnWidth,
  ) {
    final framed = _wrapCard(id, column, index, count);
    final isDragging = _draggingId != null;
    final isThisDragging = _draggingId == id;
    final surface = Opacity(
      opacity: isThisDragging ? 0.28 : 1.0,
      child: framed,
    );
    final feedback = _DesktopDragFeedbackCard(
      key: ValueKey('home.drag-feedback-${id.key}'),
      width: columnWidth,
      child: widget.cardBuilder(id),
    );

    void onDragStarted() {
      setState(() {
        _draggingId = id;
        _hoveredSlot = null;
      });
      if (!widget.isEditing) {
        widget.onEnterEditMode();
      }
    }

    void clearDrag() {
      if (mounted && _draggingId == id) {
        setState(() {
          _draggingId = null;
          _hoveredSlot = null;
        });
      }
    }

    final draggable = KeyedSubtree(
      key: ValueKey('home.bento-card-wrap-${id.key}'),
      child: widget.isEditing
          ? Draggable<HomeWidgetId>(
              key: ValueKey('home.draggable-${id.key}'),
              data: id,
              maxSimultaneousDrags: 1,
              dragAnchorStrategy: childDragAnchorStrategy,
              ignoringFeedbackPointer: true,
              onDragStarted: onDragStarted,
              onDragCompleted: clearDrag,
              onDragEnd: (_) => clearDrag(),
              onDraggableCanceled: (_, __) => clearDrag(),
              feedback: feedback,
              childWhenDragging: surface,
              child: surface,
            )
          : LongPressDraggable<HomeWidgetId>(
              key: ValueKey('home.draggable-${id.key}'),
              data: id,
              delay: const Duration(milliseconds: 260),
              maxSimultaneousDrags: 1,
              dragAnchorStrategy: childDragAnchorStrategy,
              ignoringFeedbackPointer: true,
              onDragStarted: onDragStarted,
              onDragCompleted: clearDrag,
              onDragEnd: (_) => clearDrag(),
              onDraggableCanceled: (_, __) => clearDrag(),
              feedback: feedback,
              childWhenDragging: surface,
              child: surface,
            ),
    );

    return Stack(
      children: [
        draggable,
        if (isDragging && !isThisDragging)
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _CardSnapHalfTarget(
                    key: ValueKey('home.snap-${id.key}-top'),
                    draggingSelfId: id,
                    onHover: () => _setHoveredSlot(column, index),
                    onLeave: () => _clearHoveredSlotIf(column, index),
                    onAccept: (dragged) => _acceptSlot(dragged, column, index),
                  ),
                ),
                Expanded(
                  child: _CardSnapHalfTarget(
                    key: ValueKey('home.snap-${id.key}-bottom'),
                    draggingSelfId: id,
                    onHover: () => _setHoveredSlot(column, index + 1),
                    onLeave: () => _clearHoveredSlotIf(column, index + 1),
                    onAccept: (dragged) =>
                        _acceptSlot(dragged, column, index + 1),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CardSnapHalfTarget extends StatelessWidget {
  const _CardSnapHalfTarget({
    super.key,
    required this.draggingSelfId,
    required this.onHover,
    required this.onLeave,
    required this.onAccept,
  });

  final HomeWidgetId draggingSelfId;
  final VoidCallback onHover;
  final VoidCallback onLeave;
  final ValueChanged<HomeWidgetId> onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<HomeWidgetId>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) => details.data != draggingSelfId,
      onMove: (_) => onHover(),
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (_, __, ___) => const SizedBox.expand(),
    );
  }
}

class _DesktopDragFeedbackCard extends StatelessWidget {
  const _DesktopDragFeedbackCard({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusL);
    final borderColor = colors.brandInk.withValues(
      alpha: colors.isDark ? 0.55 : 0.42,
    );

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: width,
          child: Transform.scale(
            scale: 0.86,
            alignment: Alignment.center,
            child: Opacity(
              opacity: 0.58,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: colors.textPrimary.withValues(
                        alpha: colors.isDark ? 0.34 : 0.18,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: child,
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

class _BentoColumn extends StatelessWidget {
  const _BentoColumn({
    required this.column,
    required this.label,
    required this.items,
    required this.isEditing,
    required this.isDragging,
    required this.draggingId,
    required this.hoveredSlot,
    required this.buildCard,
    required this.onHoverSlot,
    required this.onLeaveSlot,
    required this.onAcceptSlot,
    this.footer,
  });

  final HomeBentoColumn column;
  final String label;
  final List<HomeWidgetId> items;
  final bool isEditing;
  final bool isDragging;
  final HomeWidgetId? draggingId;
  final _BentoSlotTarget? hoveredSlot;
  final Widget Function(
    HomeWidgetId id,
    int index,
    int count,
    double columnWidth,
  ) buildCard;
  final void Function(HomeBentoColumn column, int slotIndex) onHoverSlot;
  final void Function(HomeBentoColumn column, int slotIndex) onLeaveSlot;
  final void Function(HomeWidgetId id, int slotIndex) onAcceptSlot;
  final Widget? footer;

  String get _colName =>
      column == HomeBentoColumn.primary ? 'primary' : 'secondary';

  bool _isSlotHighlighted(int slotIndex) =>
      hoveredSlot == (column: column, slot: slotIndex);

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final showDropChrome = isEditing || isDragging;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 460.0;
        return Column(
          key: ValueKey('home.bento-col-$_colName'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDropChrome)
              Padding(
                key: ValueKey('home.bento-header-$_colName'),
                padding: const EdgeInsets.only(
                  left: TpTokens.space1,
                  bottom: TpTokens.space2,
                ),
                child: Text(
                  label,
                  style: TpTypography.cardMeta(colors).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (items.isEmpty)
              if (showDropChrome)
                _EmptyColumnDropZone(
                  key: ValueKey('home.empty-column-$_colName'),
                  draggingId: draggingId,
                  onAccept: (id) => onAcceptSlot(id, 0),
                )
              else
                const SizedBox.shrink()
            else ...[
              _BentoDropSlot(
                key: ValueKey('home.drop-$_colName-0'),
                isEditing: isEditing,
                isDraggingAny: isDragging,
                draggingId: draggingId,
                isExternallyHighlighted: _isSlotHighlighted(0),
                isEdgeSlot: true,
                onHoverEnter: () => onHoverSlot(column, 0),
                onHoverLeave: () => onLeaveSlot(column, 0),
                onAccept: (id) => onAcceptSlot(id, 0),
              ),
              for (var i = 0; i < items.length; i++) ...[
                buildCard(items[i], i, items.length, columnWidth),
                _BentoDropSlot(
                  key: ValueKey('home.drop-$_colName-${i + 1}'),
                  isEditing: isEditing,
                  isDraggingAny: isDragging,
                  draggingId: draggingId,
                  isExternallyHighlighted: _isSlotHighlighted(i + 1),
                  isEdgeSlot: i == items.length - 1,
                  onHoverEnter: () => onHoverSlot(column, i + 1),
                  onHoverLeave: () => onLeaveSlot(column, i + 1),
                  onAccept: (id) => onAcceptSlot(id, i + 1),
                ),
              ],
            ],
            if (footer != null)
              KeyedSubtree(
                key: ValueKey('home.bento-footer-$_colName'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (items.isNotEmpty)
                      const SizedBox(height: TpTokens.sectionGap),
                    footer!,
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BentoDropSlot extends StatelessWidget {
  const _BentoDropSlot({
    super.key,
    required this.isEditing,
    required this.isDraggingAny,
    required this.draggingId,
    required this.isExternallyHighlighted,
    this.isEdgeSlot = false,
    required this.onHoverEnter,
    required this.onHoverLeave,
    required this.onAccept,
  });

  final bool isEditing;
  final bool isDraggingAny;
  final HomeWidgetId? draggingId;
  final bool isExternallyHighlighted;
  final bool isEdgeSlot;
  final VoidCallback onHoverEnter;
  final VoidCallback onHoverLeave;
  final ValueChanged<HomeWidgetId> onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final duration = appAnimationDuration(
      context,
      const Duration(milliseconds: 140),
    );
    final double idleHeight;
    if (!isEditing && !isDraggingAny) {
      idleHeight = isEdgeSlot ? 0 : TpTokens.sectionGap;
    } else if (isDraggingAny) {
      idleHeight = isEdgeSlot ? 40.0 : 28.0;
    } else {
      idleHeight = TpTokens.space3;
    }

    return DragTarget<HomeWidgetId>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (_) => onHoverEnter(),
      onLeave: (_) => onHoverLeave(),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty || isExternallyHighlighted;
        final candidateId = hovered
            ? (candidates.isNotEmpty ? (candidates.first ?? draggingId) : draggingId)
            : null;
        final label = candidateId != null
            ? '放置「${homeWidgetMetaFor(candidateId).title}」到此处'
            : '放置到此处';

        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          height: hovered ? 44 : idleHeight,
          margin: EdgeInsets.symmetric(vertical: hovered ? TpTokens.space1 : 0),
          decoration: hovered
              ? BoxDecoration(
                  color: colors.brandSoft,
                  borderRadius: BorderRadius.circular(TpTokens.radiusM),
                  border: Border.all(
                    color: colors.brandInk,
                    width: 1.5,
                  ),
                )
              : null,
          child: hovered
              ? Center(
                  child: Text(
                    label,
                    style: TpTypography.badge(colors.brandInk),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _EmptyColumnDropZone extends StatelessWidget {
  const _EmptyColumnDropZone({
    super.key,
    required this.draggingId,
    required this.onAccept,
  });

  final HomeWidgetId? draggingId;
  final ValueChanged<HomeWidgetId> onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final duration = appAnimationDuration(
      context,
      const Duration(milliseconds: 150),
    );

    return DragTarget<HomeWidgetId>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty;
        final candidateId = hovered ? (candidates.first ?? draggingId) : null;
        final message = hovered
            ? (candidateId != null
                ? '松开将「${homeWidgetMetaFor(candidateId).title}」放入本栏'
                : '松开即可放置到本栏')
            : '可将组件拖入此栏';

        return AnimatedContainer(
          duration: duration,
          constraints: const BoxConstraints(minHeight: 160),
          padding: const EdgeInsets.all(TpTokens.space4),
          decoration: BoxDecoration(
            color: hovered ? colors.brandSoft : colors.surfaceSubtle,
            borderRadius: BorderRadius.circular(TpTokens.radiusL),
            border: Border.all(
              color: hovered ? colors.brandInk : colors.divider,
              width: hovered ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  TpIcons.dashboard,
                  size: TpTokens.iconL,
                  color: hovered ? colors.brandInk : colors.textMuted,
                ),
                const SizedBox(height: TpTokens.space2),
                Text(
                  message,
                  style: TpTypography.itemMeta(colors).copyWith(
                    color: hovered ? colors.brandInk : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
