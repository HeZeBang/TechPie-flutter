import 'package:flutter/material.dart';

import '../../models/home_layout.dart';
import '../../theme/theme.dart';
import '../../utils/adaptive_motion.dart';
import '../design_system/design_system.dart';
import 'home_widget_chrome.dart';

/// Builds a rendered card widget for a given [HomeWidgetId] in Home.
typedef HomeWidgetCardBuilder = Widget Function(HomeWidgetId id);

/// Dual-column Bento workspace for wide/desktop viewports.
///
/// Outside edit mode, if only one column contains widgets, this collapses
/// cleanly into a single full-width column (or delegates evenly when both have
/// items via [TpBentoGrid]). During edit mode, both columns remain visible with
/// drag-and-drop slots across columns and button fallbacks on every card.
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

  Widget _wrapViewCard(HomeWidgetId id, HomeBentoColumn column, int index, int count) {
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
    if (!widget.isEditing) {
      final primary = [
        for (var i = 0; i < widget.layout.primary.length; i++)
          _wrapViewCard(
            widget.layout.primary[i],
            HomeBentoColumn.primary,
            i,
            widget.layout.primary.length,
          ),
        if (widget.footerWidget != null) widget.footerWidget!,
      ];
      final secondary = [
        for (var i = 0; i < widget.layout.secondary.length; i++)
          _wrapViewCard(
            widget.layout.secondary[i],
            HomeBentoColumn.secondary,
            i,
            widget.layout.secondary.length,
          ),
      ];

      if (primary.isEmpty && secondary.isEmpty) {
        return const SizedBox.shrink();
      }
      if (primary.isEmpty || secondary.isEmpty) {
        final single = primary.isNotEmpty ? primary : secondary;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < single.length; i++) ...[
              if (i > 0) const SizedBox(height: TpTokens.sectionGap),
              single[i],
            ],
          ],
        );
      }

      return TpBentoGrid(
        primaryColumn: primary,
        secondaryColumn: secondary,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 55,
              child: _EditableColumn(
                column: HomeBentoColumn.primary,
                label: '主栏 · 课程与待办',
                items: widget.layout.primary,
                draggingId: _draggingId,
                buildCard: (id, index, count) =>
                    _buildDraggableCard(id, HomeBentoColumn.primary, index, count),
                onAcceptSlot: (id, slot) {
                  setState(() => _draggingId = null);
                  widget.onMoveToSlot(id, HomeBentoColumn.primary, slot);
                },
              ),
            ),
            const SizedBox(width: TpTokens.space4),
            Expanded(
              flex: 45,
              child: _EditableColumn(
                column: HomeBentoColumn.secondary,
                label: '副栏 · 卡片与快捷',
                items: widget.layout.secondary,
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
        if (widget.footerWidget != null) ...[
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
    final framed = _wrapViewCard(id, column, index, count);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        return Draggable<HomeWidgetId>(
          key: ValueKey('home.draggable-${id.key}'),
          data: id,
          maxSimultaneousDrags: 1,
          onDragStarted: () => setState(() => _draggingId = id),
          onDragEnd: (_) {
            if (mounted && _draggingId != null) {
              setState(() => _draggingId = null);
            }
          },
          onDraggableCanceled: (_, __) {
            if (mounted && _draggingId != null) {
              setState(() => _draggingId = null);
            }
          },
          feedback: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: BorderRadius.circular(TpTokens.radiusL + 2),
            child: SizedBox(
              width: width,
              child: Opacity(opacity: 0.92, child: framed),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: framed),
          child: framed,
        );
      },
    );
  }
}

class _EditableColumn extends StatelessWidget {
  const _EditableColumn({
    required this.column,
    required this.label,
    required this.items,
    required this.draggingId,
    required this.buildCard,
    required this.onAcceptSlot,
  });

  final HomeBentoColumn column;
  final String label;
  final List<HomeWidgetId> items;
  final HomeWidgetId? draggingId;
  final Widget Function(HomeWidgetId id, int index, int count) buildCard;
  final void Function(HomeWidgetId id, int slotIndex) onAcceptSlot;

  String get _colName => column == HomeBentoColumn.primary ? 'primary' : 'secondary';

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Column(
      key: ValueKey('home.bento-col-$_colName'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
          _EmptyColumnDropZone(
            key: ValueKey('home.empty-column-$_colName'),
            onAccept: (id) => onAcceptSlot(id, 0),
          )
        else ...[
          _BentoDropSlot(
            key: ValueKey('home.drop-$_colName-0'),
            isDraggingAny: draggingId != null,
            onAccept: (id) => onAcceptSlot(id, 0),
          ),
          for (var i = 0; i < items.length; i++) ...[
            buildCard(items[i], i, items.length),
            _BentoDropSlot(
              key: ValueKey('home.drop-$_colName-${i + 1}'),
              isDraggingAny: draggingId != null,
              isBottomZone: i == items.length - 1,
              onAccept: (id) => onAcceptSlot(id, i + 1),
            ),
          ],
        ],
      ],
    );
  }
}

class _BentoDropSlot extends StatelessWidget {
  const _BentoDropSlot({
    super.key,
    required this.isDraggingAny,
    this.isBottomZone = false,
    required this.onAccept,
  });

  final bool isDraggingAny;
  final bool isBottomZone;
  final ValueChanged<HomeWidgetId> onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final duration = appAnimationDuration(
      context,
      const Duration(milliseconds: 140),
    );
    final baseHeight = isDraggingAny
        ? (isBottomZone ? 48.0 : 28.0)
        : (isBottomZone ? TpTokens.space3 : TpTokens.space3);

    return DragTarget<HomeWidgetId>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final hovered = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          height: hovered ? 44 : baseHeight,
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
