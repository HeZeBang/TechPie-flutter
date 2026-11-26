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
/// and Edit Mode so initiating a drag outside Edit Mode never unmounts the
/// active draggable or flashes column headers unnecessarily. When neither edit
/// mode nor an active drag is in progress and one column is empty, the
/// populated column cleanly expands to full width.
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

class _HomeBentoEditorState extends State<HomeBentoEditor> {
  HomeWidgetId? _draggingId;

  Widget _wrapCard(HomeWidgetId id, HomeBentoColumn column, int index, int count) {
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
                  buildCard: (id, index, count) => _buildDraggableCard(
                    id,
                    HomeBentoColumn.primary,
                    index,
                    count,
                  ),
                  onAcceptSlot: (id, slot) {
                    setState(() => _draggingId = null);
                    widget.onMoveToSlot(id, HomeBentoColumn.primary, slot);
                  },
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
                  buildCard: (id, index, count) => _buildDraggableCard(
                    id,
                    HomeBentoColumn.secondary,
                    index,
                    count,
                  ),
                  onAcceptSlot: (id, slot) {
                    setState(() => _draggingId = null);
                    widget.onMoveToSlot(id, HomeBentoColumn.secondary, slot);
                  },
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
  ) {
    final framed = _wrapCard(id, column, index, count);
    return LayoutBuilder(
      key: ValueKey('home.bento-card-wrap-${id.key}'),
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final feedback = Material(
          color: Colors.transparent,
          elevation: 10,
          borderRadius: BorderRadius.circular(TpTokens.radiusL + 2),
          child: Transform.scale(
            scale: 1.015,
            child: SizedBox(
              width: width,
              child: Opacity(opacity: 0.94, child: framed),
            ),
          ),
        );
        final placeholder = Opacity(opacity: 0.35, child: framed);

        void onDragStarted() => setState(() => _draggingId = id);
        void clearDrag() {
          if (mounted && _draggingId != null) {
            setState(() => _draggingId = null);
          }
        }

        if (widget.isEditing) {
          return Draggable<HomeWidgetId>(
            key: ValueKey('home.draggable-${id.key}'),
            data: id,
            maxSimultaneousDrags: 1,
            onDragStarted: onDragStarted,
            onDragEnd: (_) => clearDrag(),
            onDraggableCanceled: (_, __) => clearDrag(),
            feedback: feedback,
            childWhenDragging: placeholder,
            child: framed,
          );
        }

        return LongPressDraggable<HomeWidgetId>(
          key: ValueKey('home.draggable-${id.key}'),
          data: id,
          delay: const Duration(milliseconds: 260),
          maxSimultaneousDrags: 1,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => clearDrag(),
          onDraggableCanceled: (_, __) => clearDrag(),
          feedback: feedback,
          childWhenDragging: placeholder,
          child: framed,
        );
      },
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
    required this.buildCard,
    required this.onAcceptSlot,
    this.footer,
  });

  final HomeBentoColumn column;
  final String label;
  final List<HomeWidgetId> items;
  final bool isEditing;
  final bool isDragging;
  final HomeWidgetId? draggingId;
  final Widget Function(HomeWidgetId id, int index, int count) buildCard;
  final void Function(HomeWidgetId id, int slotIndex) onAcceptSlot;
  final Widget? footer;

  String get _colName =>
      column == HomeBentoColumn.primary ? 'primary' : 'secondary';

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final showDropChrome = isEditing || isDragging;

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
              onAccept: (id) => onAcceptSlot(id, 0),
            )
          else if (footer == null)
            const SizedBox.shrink()
          else
            const SizedBox.shrink()
        else ...[
          _BentoDropSlot(
            key: ValueKey('home.drop-$_colName-0'),
            isEditing: isEditing,
            isDraggingAny: isDragging,
            isEdgeSlot: true,
            onAccept: (id) => onAcceptSlot(id, 0),
          ),
          for (var i = 0; i < items.length; i++) ...[
            buildCard(items[i], i, items.length),
            _BentoDropSlot(
              key: ValueKey('home.drop-$_colName-${i + 1}'),
              isEditing: isEditing,
              isDraggingAny: isDragging,
              isEdgeSlot: i == items.length - 1,
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
  }
}

class _BentoDropSlot extends StatelessWidget {
  const _BentoDropSlot({
    super.key,
    required this.isEditing,
    required this.isDraggingAny,
    this.isEdgeSlot = false,
    required this.onAccept,
  });

  final bool isEditing;
  final bool isDraggingAny;
  final bool isEdgeSlot;
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
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty;
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
                    '放置到此处',
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
  const _EmptyColumnDropZone({super.key, required this.onAccept});

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
                  hovered ? '松开即可放置到本栏' : '可将组件拖入此栏',
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
