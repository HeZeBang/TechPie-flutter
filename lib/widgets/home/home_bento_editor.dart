import 'dart:ui';

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
/// and Edit Mode. Picking up a card automatically enters Edit Mode so the user
/// sees the edit toolbar and per-card options without obscuring the Bento grid
/// underneath a full-size opaque card.
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
    final isThisDragging = _draggingId == id;
    final surface = Opacity(
      opacity: isThisDragging ? 0.28 : 1.0,
      child: framed,
    );
    final feedback = _DesktopDragFeedbackCard(
      key: ValueKey('home.drag-feedback-${id.key}'),
      id: id,
    );

    void onDragStarted() {
      setState(() => _draggingId = id);
      if (!widget.isEditing) {
        widget.onEnterEditMode();
      }
    }

    void clearDrag() {
      if (mounted && _draggingId == id) {
        setState(() => _draggingId = null);
      }
    }

    return KeyedSubtree(
      key: ValueKey('home.bento-card-wrap-${id.key}'),
      child: widget.isEditing
          ? Draggable<HomeWidgetId>(
              key: ValueKey('home.draggable-${id.key}'),
              data: id,
              maxSimultaneousDrags: 1,
              dragAnchorStrategy: pointerDragAnchorStrategy,
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
              dragAnchorStrategy: pointerDragAnchorStrategy,
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
  }
}

class _DesktopDragFeedbackCard extends StatelessWidget {
  const _DesktopDragFeedbackCard({
    super.key,
    required this.id,
  });

  final HomeWidgetId id;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final meta = homeWidgetMetaFor(id);
    final surfaceTint =
        colors.surface.withValues(alpha: colors.isDark ? 0.72 : 0.78);
    final borderColor =
        colors.brandInk.withValues(alpha: colors.isDark ? 0.45 : 0.35);

    return Transform.translate(
      offset: const Offset(14, 14),
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 196, maxWidth: 248),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TpTokens.radiusL),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceTint,
                borderRadius: BorderRadius.circular(TpTokens.radiusL),
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: colors.textPrimary.withValues(
                      alpha: colors.isDark ? 0.28 : 0.14,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space3,
                  vertical: TpTokens.space2 + 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colors.brandSoft,
                        borderRadius: BorderRadius.circular(TpTokens.radiusS),
                      ),
                      child: Icon(
                        homeWidgetIcon(id),
                        size: TpTokens.iconS,
                        color: colors.brandInk,
                      ),
                    ),
                    const SizedBox(width: TpTokens.space2),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meta.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TpTypography.itemTitle(colors).copyWith(
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            '拖动到目标栏位',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TpTypography.cardMeta(colors).copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: TpTokens.space2),
                    Icon(
                      TpIcons.dragHandle,
                      size: TpTokens.iconXs,
                      color: colors.textMuted,
                    ),
                  ],
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
            isEdgeSlot: true,
            onAccept: (id) => onAcceptSlot(id, 0),
          ),
          for (var i = 0; i < items.length; i++) ...[
            buildCard(items[i], i, items.length),
            _BentoDropSlot(
              key: ValueKey('home.drop-$_colName-${i + 1}'),
              isEditing: isEditing,
              isDraggingAny: isDragging,
              draggingId: draggingId,
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
    required this.draggingId,
    this.isEdgeSlot = false,
    required this.onAccept,
  });

  final bool isEditing;
  final bool isDraggingAny;
  final HomeWidgetId? draggingId;
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
        final candidateId = hovered ? (candidates.first ?? draggingId) : null;
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
