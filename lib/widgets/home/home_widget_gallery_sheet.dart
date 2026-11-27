import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/home_layout.dart';
import '../../theme/theme.dart';
import '../../utils/adaptive_motion.dart';
import '../../utils/haptics.dart';
import '../adaptive_button.dart';
import '../adaptive_navigation_scaffold.dart';
import '../design_system/design_system.dart';
import 'home_widget_chrome.dart';

/// Live state snapshot synchronized between HomePage and the Widget Gallery sheet.
@immutable
class HomeGalleryState {
  const HomeGalleryState({
    required this.visibleIds,
    required this.campusCardStyle,
  });

  final Set<HomeWidgetId> visibleIds;
  final HomeCampusCardStyle campusCardStyle;
}

/// Opens the adaptive Home widget gallery (bottom sheet on mobile, centered
/// dialog on wide/desktop viewports) allowing users to add/remove widgets,
/// switch the campus card style, or reset defaults with immediate live updates.
Future<void> showHomeWidgetGallery({
  required BuildContext context,
  required ValueListenable<HomeGalleryState> stateListenable,
  required ValueChanged<HomeWidgetId> onAddWidget,
  required ValueChanged<HomeWidgetId> onRemoveWidget,
  required ValueChanged<HomeCampusCardStyle> onChangeCampusCardStyle,
  required VoidCallback onResetDefaults,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= TpTokens.bentoBreakpoint;
  if (isWide) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) {
        final colors = dialogCtx.tpColors;
        return Dialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TpTokens.radiusL),
            side: BorderSide(color: colors.divider),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500, maxHeight: maxHeight),
            child: _HomeWidgetGalleryBody(
              hostContext: dialogCtx,
              contentPadding: const EdgeInsets.all(TpTokens.space5),
              stateListenable: stateListenable,
              onAddWidget: onAddWidget,
              onRemoveWidget: onRemoveWidget,
              onChangeCampusCardStyle: onChangeCampusCardStyle,
              onResetDefaults: onResetDefaults,
            ),
          ),
        );
      },
    );
  }

  return AdaptiveNavigationScaffold.showSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetCtx, contentPadding) => _HomeWidgetGalleryBody(
      hostContext: sheetCtx,
      contentPadding: contentPadding,
      stateListenable: stateListenable,
      onAddWidget: onAddWidget,
      onRemoveWidget: onRemoveWidget,
      onChangeCampusCardStyle: onChangeCampusCardStyle,
      onResetDefaults: onResetDefaults,
    ),
  );
}

class _HomeWidgetGalleryBody extends StatefulWidget {
  const _HomeWidgetGalleryBody({
    required this.hostContext,
    required this.contentPadding,
    required this.stateListenable,
    required this.onAddWidget,
    required this.onRemoveWidget,
    required this.onChangeCampusCardStyle,
    required this.onResetDefaults,
  });

  final BuildContext hostContext;
  final EdgeInsets contentPadding;
  final ValueListenable<HomeGalleryState> stateListenable;
  final ValueChanged<HomeWidgetId> onAddWidget;
  final ValueChanged<HomeWidgetId> onRemoveWidget;
  final ValueChanged<HomeCampusCardStyle> onChangeCampusCardStyle;
  final VoidCallback onResetDefaults;

  @override
  State<_HomeWidgetGalleryBody> createState() => _HomeWidgetGalleryBodyState();
}

class _HomeWidgetGalleryBodyState extends State<_HomeWidgetGalleryBody> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(HomeWidgetMeta meta, String query) {
    if (query.isEmpty) return true;
    return meta.title.toLowerCase().contains(query) ||
        meta.subtitle.toLowerCase().contains(query) ||
        meta.id.key.toLowerCase().contains(query) ||
        meta.group.label.toLowerCase().contains(query) ||
        meta.keywords.any((k) => k.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HomeGalleryState>(
      valueListenable: widget.stateListenable,
      builder: (context, state, _) {
        final colors = context.tpColors;
        final query = _query.trim().toLowerCase();
        final showStyleCard = query.isEmpty ||
            '校园卡样式 compact full 精简条带 完整卡面'
                .toLowerCase()
                .contains(query);
        final groups = [
          for (final group in HomeWidgetGroup.values)
            (
              group: group,
              ids: [
                for (final id in HomeWidgetId.values)
                  if (homeWidgetMetaFor(id).group == group &&
                      _matchesQuery(homeWidgetMetaFor(id), query))
                    id,
              ],
            ),
        ].where((entry) => entry.ids.isNotEmpty).toList();

        return Padding(
          padding: widget.contentPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    TpIcons.dashboard,
                    size: TpTokens.iconS + 2,
                    color: colors.brandInk,
                  ),
                  const SizedBox(width: TpTokens.space2),
                  Expanded(
                    child: Text(
                      '管理主页组件',
                      style: TpTypography.cardTitle(colors).copyWith(
                        fontSize: 17,
                      ),
                    ),
                  ),
                  TpBadge(
                    label:
                        '已添加 ${state.visibleIds.length}/${HomeWidgetId.values.length}',
                    tone: TpBadgeTone.muted,
                  ),
                  const SizedBox(width: TpTokens.space1),
                  AdaptiveButton(
                    key: const ValueKey('home.gallery-close'),
                    onPressed: () => Navigator.of(widget.hostContext).pop(),
                    icon: TpIcons.close,
                    sfSymbol: 'xmark',
                    accessibilityLabel: '关闭',
                    role: AdaptiveButtonRole.plain,
                    width: 40,
                    height: 40,
                  ),
                ],
              ),
              const SizedBox(height: TpTokens.space1),
              Text(
                '选择主页展示的模块与校园卡外观；改动立即生效并自动保存。',
                style: TpTypography.itemMeta(colors),
              ),
              const SizedBox(height: TpTokens.space3),
              TextField(
                key: const ValueKey('home.gallery-search'),
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: '搜索组件',
                  hintText: '按名称或关键词筛选，如 GPA、请假、Blackboard',
                  filled: true,
                  fillColor: colors.surfaceSubtle,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TpTokens.radiusM),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TpTokens.radiusM),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  prefixIcon: Icon(TpIcons.search, color: colors.textMuted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: const Icon(TpIcons.close),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: TpTokens.space3),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showStyleCard)
                        TpSectionCard(
                          title: '校园卡样式',
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(TpTokens.space3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _StyleOptionTile(
                                      key: const ValueKey(
                                        'home.gallery-style-compact',
                                      ),
                                      title: '精简条带',
                                      subtitle: '紧凑单行卡片，节省首屏空间',
                                      selected: state.campusCardStyle ==
                                          HomeCampusCardStyle.compact,
                                      onTap: () =>
                                          widget.onChangeCampusCardStyle(
                                        HomeCampusCardStyle.compact,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: TpTokens.space2),
                                  Expanded(
                                    child: _StyleOptionTile(
                                      key: const ValueKey(
                                        'home.gallery-style-full',
                                      ),
                                      title: '完整卡面',
                                      subtitle: '展开校徽卡面与完整操作栏',
                                      selected: state.campusCardStyle ==
                                          HomeCampusCardStyle.full,
                                      onTap: () =>
                                          widget.onChangeCampusCardStyle(
                                        HomeCampusCardStyle.full,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (groups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: TpTokens.space2),
                          child: TpStateCard.empty(
                            icon: TpIcons.search,
                            title: '没有匹配的组件',
                            compact: true,
                          ),
                        )
                      else
                        for (var i = 0; i < groups.length; i++) ...[
                          if (showStyleCard || i > 0)
                            const SizedBox(height: TpTokens.space3),
                          TpSectionCard(
                            title: groups[i].group.label,
                            children: [
                              for (var j = 0; j < groups[i].ids.length; j++)
                                _GalleryWidgetRow(
                                  id: groups[i].ids[j],
                                  added: state.visibleIds
                                      .contains(groups[i].ids[j]),
                                  showDivider: j < groups[i].ids.length - 1,
                                  onAdd: () =>
                                      widget.onAddWidget(groups[i].ids[j]),
                                  onRemove: () =>
                                      widget.onRemoveWidget(groups[i].ids[j]),
                                ),
                            ],
                          ),
                        ],
                      const SizedBox(height: TpTokens.space3),
                      AdaptiveButton(
                        key: const ValueKey('home.gallery-reset'),
                        onPressed: () {
                          widget.onResetDefaults();
                          Navigator.of(widget.hostContext).pop();
                        },
                        icon: TpIcons.reset,
                        sfSymbol: 'arrow.counterclockwise',
                        label: '重置为默认布局',
                        role: AdaptiveButtonRole.destructive,
                        showIosIcon: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StyleOptionTile extends StatelessWidget {
  const _StyleOptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusM);
    final duration = appAnimationDuration(
      context,
      const Duration(milliseconds: 160),
    );
    return TpTapSurface(
      style: TpTapFeedbackStyle.card,
      borderRadius: radius,
      onTap: () {
        unawaited(AppHaptics.play(AppHaptics.selection));
        onTap();
      },
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(TpTokens.space3),
        decoration: BoxDecoration(
          color: selected ? colors.brandSoft : colors.surfaceSubtle,
          borderRadius: radius,
          border: Border.all(
            color: selected ? colors.brandInk : colors.divider,
            width: selected ? 1.5 : 0.75,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TpTypography.itemTitle(colors).copyWith(
                      fontSize: 14,
                      color: selected ? colors.brandInk : colors.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(TpIcons.checkCircle, size: 16, color: colors.brandInk),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TpTypography.itemMeta(colors),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryWidgetRow extends StatelessWidget {
  const _GalleryWidgetRow({
    required this.id,
    required this.added,
    required this.showDivider,
    required this.onAdd,
    required this.onRemove,
  });

  final HomeWidgetId id;
  final bool added;
  final bool showDivider;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = homeWidgetMetaFor(id);

    return TpListRow(
      icon: homeWidgetIcon(id),
      title: meta.title,
      subtitle: meta.subtitle,
      showDivider: showDivider,
      trailing: added
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TpBadge(
                  label: '已添加',
                  tone: TpBadgeTone.success,
                ),
                const SizedBox(width: TpTokens.space1),
                AdaptiveButton(
                  key: ValueKey('home.gallery-remove-${id.key}'),
                  onPressed: onRemove,
                  icon: TpIcons.minus,
                  sfSymbol: 'minus.circle',
                  accessibilityLabel: '移除${meta.title}',
                  role: AdaptiveButtonRole.destructive,
                  width: 40,
                  height: 36,
                ),
              ],
            )
          : AdaptiveButton(
              key: ValueKey('home.gallery-add-${id.key}'),
              onPressed: onAdd,
              icon: TpIcons.add,
              sfSymbol: 'plus',
              label: '添加',
              role: AdaptiveButtonRole.standard,
              width: 84,
              height: 36,
              showIosIcon: true,
            ),
    );
  }
}
