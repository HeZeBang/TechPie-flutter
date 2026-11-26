import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/home_layout.dart';
import '../../theme/theme.dart';
import '../../utils/adaptive_motion.dart';
import '../../utils/haptics.dart';

IconData homeWidgetIcon(HomeWidgetId id) => switch (id) {
      HomeWidgetId.campusCard => TpIcons.campusCard,
      HomeWidgetId.todayCourses => TpIcons.course,
      HomeWidgetId.deadlines => TpIcons.deadlines,
      HomeWidgetId.quickActions => TpIcons.activities,
    };

/// Wraps a Home dashboard widget with adaptive customization chrome:
///
/// - Mobile (`isDesktopMode == false`): long-pressing anywhere on the card
///   enters edit mode with haptic feedback; in edit mode an iOS-inspired
///   toolbar shows a remove control, inline widget options (campus card style /
///   shortcut customization), and an explicit [ReorderableDragStartListener]
///   handle so normal vertical scrolling never collides with dragging.
/// - Desktop (`isDesktopMode == true`): right-clicking opens a context menu;
///   in edit mode an editorial toolbar adds grab handles, column swap, up/down
///   buttons, inline style switches, and remove actions without infinite
///   jiggle animations.
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
  bool _hovered = false;

  void _triggerLongPressEdit() {
    if (widget.isEditing || widget.onEnterEditMode == null) return;
    unawaited(AppHaptics.play(AppHaptics.tabHold));
    widget.onEnterEditMode!();
  }

  Future<void> _showDesktopContextMenu(TapDownDetails details) async {
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) return;
    final colors = context.tpColors;
    final meta = homeWidgetMetaFor(widget.id);
    final pos = details.globalPosition;

    final action = await showMenu<String>(
      context: context,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TpTokens.radiusM),
        side: BorderSide(color: colors.divider),
      ),
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy,
        overlay.size.width - pos.dx,
        overlay.size.height - pos.dy,
      ),
      items: [
        if (!widget.isEditing && widget.onEnterEditMode != null)
          const PopupMenuItem<String>(
            value: 'edit',
            child: _ContextMenuLabel(
              icon: TpIcons.dashboard,
              label: '编辑主页布局',
            ),
          ),
        if (widget.id == HomeWidgetId.campusCard &&
            widget.campusCardStyle != null &&
            widget.onCampusCardStyleChanged != null)
          PopupMenuItem<String>(
            value: 'toggle_card_style',
            child: _ContextMenuLabel(
              icon: TpIcons.campusCard,
              label: widget.campusCardStyle == HomeCampusCardStyle.full
                  ? '切换为精简校园卡'
                  : '切换为完整校园卡',
            ),
          ),
        if (widget.id == HomeWidgetId.quickActions &&
            widget.onConfigureQuickActions != null)
          PopupMenuItem<String>(
            value: 'configure_quick_actions',
            child: _ContextMenuLabel(
              icon: TpIcons.sliders,
              label: '定制${meta.title}',
            ),
          ),
        if (widget.onSwapColumn != null)
          PopupMenuItem<String>(
            value: 'swap_column',
            child: _ContextMenuLabel(
              icon: TpIcons.swapColumns,
              label: widget.column == HomeBentoColumn.primary
                  ? '移至副栏'
                  : '移至主栏',
            ),
          ),
        if (widget.onRemove != null)
          PopupMenuItem<String>(
            value: 'remove',
            child: _ContextMenuLabel(
              icon: TpIcons.minus,
              label: '隐藏${meta.title}',
              destructive: true,
            ),
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

    Widget content = AbsorbPointer(
      absorbing: widget.isEditing,
      child: widget.child,
    );

    if (!widget.isEditing) {
      if (widget.isDesktopMode) {
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: _showDesktopContextMenu,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                content,
                if (_hovered && widget.onEnterEditMode != null)
                  Positioned(
                    top: TpTokens.space2,
                    right: TpTokens.space2,
                    child: _HoverEditBadge(onTap: widget.onEnterEditMode!),
                  ),
              ],
            ),
          ),
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: _triggerLongPressEdit,
        child: content,
      );
    }

    final dragHandleIcon = Icon(
      TpIcons.dragHandle,
      key: ValueKey('home.drag-handle-${widget.id.key}'),
      size: TpTokens.iconS,
      color: colors.textMuted,
    );

    final dragHandle = widget.enableReorderDragHandle
        ? Semantics(
            label: '拖动调整${homeWidgetMetaFor(widget.id).title}顺序',
            child: ReorderableDragStartListener(
              index: widget.index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space2,
                  vertical: TpTokens.space1,
                ),
                child: dragHandleIcon,
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

    return AnimatedContainer(
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
            ),
          ),
          content,
        ],
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

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final meta = homeWidgetMetaFor(id);

    return Row(
      children: [
        if (onRemove != null) ...[
          _RemoveWidgetButton(
            widgetId: id,
            title: meta.title,
            onPressed: onRemove!,
          ),
          const SizedBox(width: TpTokens.space2),
        ],
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
        if (id == HomeWidgetId.campusCard &&
            campusCardStyle != null &&
            onCampusCardStyleChanged != null) ...[
          _CampusCardStyleSegmented(
            current: campusCardStyle!,
            onChanged: onCampusCardStyleChanged!,
          ),
          const SizedBox(width: TpTokens.space1),
        ],
        if (id == HomeWidgetId.quickActions &&
            onConfigureQuickActions != null) ...[
          _ToolbarChipButton(
            key: const ValueKey('home.configure-quick-actions'),
            icon: TpIcons.sliders,
            label: '定制',
            onTap: onConfigureQuickActions!,
          ),
          const SizedBox(width: TpTokens.space1),
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
        child: Material(
          color: colors.dangerRed.withValues(alpha: colors.isDark ? 0.22 : 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            key: ValueKey('home.remove-${widgetId.key}'),
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                TpIcons.minus,
                size: 14,
                color: colors.dangerRed,
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
            onTap: () => onChanged(HomeCampusCardStyle.compact),
          ),
          _SegmentChoice(
            key: const ValueKey('home.campus-card-style-full'),
            label: '完整',
            selected: current == HomeCampusCardStyle.full,
            onTap: () => onChanged(HomeCampusCardStyle.full),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? colors.brandInk : Colors.transparent,
          borderRadius: BorderRadius.circular(TpTokens.radiusPill),
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
    return Material(
      color: colors.surface,
      shape: StadiumBorder(side: BorderSide(color: colors.divider)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

class _HoverEditBadge extends StatelessWidget {
  const _HoverEditBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Material(
      color: colors.surface.withValues(alpha: 0.92),
      elevation: 2,
      shape: StadiumBorder(side: BorderSide(color: colors.divider)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TpIcons.dragHandleHorizontal,
                size: 13,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text('编辑', style: TpTypography.badge(colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextMenuLabel extends StatelessWidget {
  const _ContextMenuLabel({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final fg = destructive ? colors.dangerRed : colors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: TpTokens.iconS, color: fg),
        const SizedBox(width: TpTokens.space2),
        Text(label, style: TpTypography.itemTitle(colors).copyWith(color: fg)),
      ],
    );
  }
}
