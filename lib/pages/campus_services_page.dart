import 'dart:async';

import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../models/quick_shortcuts.dart';
import '../services/service_provider.dart';
import '../services/storage_service.dart';
import '../theme/theme.dart';
import '../utils/haptics.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'campus_feature_navigation.dart';

class CampusServicesPage extends StatefulWidget {
  const CampusServicesPage({
    super.key,
    this.storage,
    this.isRootDestination = false,
  });

  final StorageService? storage;
  final bool isRootDestination;

  @override
  State<CampusServicesPage> createState() => _CampusServicesPageState();
}

class _CampusServicesPageState extends State<CampusServicesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  StorageService _resolveStorage(BuildContext context) =>
      widget.storage ?? ServiceProvider.of(context).storageService;

  void _openShortcutEditor(BuildContext context) {
    final storage = _resolveStorage(context);
    unawaited(
      pushAdaptivePage<void>(
        context,
        builder: (_) => HomeShortcutEditorPage(storage: storage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final query = _query.trim().toLowerCase();
    final results = featureEntries
        .where(
          (f) => [f.description, f.subtitle, ...f.keywords]
              .any((text) => text.toLowerCase().contains(query)),
        )
        .toList();

    final nonRootBar = widget.isRootDestination
        ? null
        : AdaptiveNavigationScaffold.adaptiveBar(
            ios: () => IosNativeNavigationBar(
              title: '校园服务中心',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: '首页',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回首页',
                  placementGroup: 'leading-main',
                ),
              ],
              trailingItems: const [
                IosNativeNavigationBarItem(
                  id: 'shortcuts',
                  sfSymbol: 'slider.horizontal.3',
                  accessibilityLabel: '编辑首页快捷',
                  placementGroup: 'trailing-main',
                ),
              ],
              onItemPressed: (id) {
                if (id == 'back') {
                  unawaited(maybePopAdaptivePage<void>(context));
                } else if (id == 'shortcuts') {
                  _openShortcutEditor(context);
                }
              },
            ),
            material: () => BlurredAppBar(
              title: const Text('校园服务中心'),
              actions: [
                IconButton(
                  tooltip: '编辑首页快捷',
                  icon: const Icon(TpIcons.sliders),
                  onPressed: () => _openShortcutEditor(context),
                ),
              ],
            ),
          );

    final topInset = widget.isRootDestination
        ? 0.0
        : AdaptiveNavigationScaffold.contentTopInsetOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar: !widget.isRootDestination &&
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: nonRootBar,
      body: SafeArea(
        top: widget.isRootDestination,
        bottom: false,
        child: TpPageBody(
          maxWidth: 1120,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = constraints.maxWidth < 600
                  ? TpTokens.space4
                  : TpTokens.space5;
              final columns = constraints.maxWidth < 600
                  ? 1
                  : constraints.maxWidth < 960
                      ? 2
                      : 3;
              final width = (constraints.maxWidth -
                      2 * gutter -
                      (columns - 1) * TpTokens.space3) /
                  columns;
              final topPadding = (widget.isRootDestination &&
                          constraints.maxWidth >= 600
                      ? TpTokens.space5
                      : TpTokens.space4) +
                  topInset;
              return ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  topPadding,
                  gutter,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                children: [
                  if (widget.isRootDestination) ...[
                    TpPageHeader(
                      key: const ValueKey('campus_services.header'),
                      padding: const EdgeInsets.only(bottom: TpTokens.space4),
                      subtitle: '全部校内应用与快捷入口',
                      title: '校园服务',
                      trailing: Semantics(
                        button: true,
                        label: '编辑首页快捷',
                        child: Tooltip(
                          message: '编辑首页快捷',
                          child: TpPressScale(
                            pressedScale: 0.96,
                            child: Material(
                              key: const ValueKey(
                                'campus_services.edit-shortcuts',
                              ),
                              color: colors.surface,
                              shape: StadiumBorder(
                                side: BorderSide(color: colors.divider),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: TpTapSurface(
                                style: TpTapFeedbackStyle.button,
                                customBorder: const StadiumBorder(),
                                enablePressScale: false,
                                onTap: () => _openShortcutEditor(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: TpTokens.space3,
                                    vertical: TpTokens.space2,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        TpIcons.sliders,
                                        size: TpTokens.iconS,
                                        color: colors.brandInk,
                                      ),
                                      const SizedBox(width: TpTokens.space2),
                                      Text(
                                        '首页快捷',
                                        style: TpTypography.itemTitle(colors)
                                            .copyWith(
                                          fontSize: 13.5,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  TextField(
                    controller: _search,
                    onChanged: (text) => setState(() => _query = text),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: '搜索服务',
                      hintText: '输入服务名、拼音或关键词',
                      filled: true,
                      fillColor: colors.surface,
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
                              onPressed: _clear,
                              icon: const Icon(TpIcons.close),
                            ),
                    ),
                  ),
                  if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: TpTokens.space5),
                      child: TpStateCard.empty(
                        icon: TpIcons.search,
                        title: '没有找到相关服务',
                        message: '尝试更换关键词或拼音，或清除搜索查看全部校园服务。',
                        primaryActionLabel: '清除搜索',
                        primaryActionIcon: TpIcons.close,
                        primaryActionSfSymbol: 'xmark.circle',
                        onPrimaryAction: _clear,
                      ),
                    ),
                  for (final category in CampusServiceCategory.values)
                    if (results.any((f) => f.category == category)) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: TpTokens.space5,
                          bottom: TpTokens.space2,
                        ),
                        child: Row(
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                category.label,
                                style: TpTypography.cardTitle(colors),
                              ),
                            ),
                            const SizedBox(width: TpTokens.space2),
                            TpBadge(
                              label:
                                  '${results.where((f) => f.category == category).length}',
                              tone: TpBadgeTone.muted,
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: TpTokens.space3,
                        runSpacing: TpTokens.space3,
                        children: [
                          for (final f
                              in results.where((f) => f.category == category))
                            SizedBox(
                              width: width,
                              child: TpCard(
                                onTap: () => openCampusFeature(context, f),
                                child: ListTile(
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: colors.brandSoft,
                                      borderRadius: BorderRadius.circular(
                                        TpTokens.radiusS,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      f.icon.icon ?? TpIcons.activities,
                                      size: TpTokens.iconM,
                                      color: colors.brandInk,
                                    ),
                                  ),
                                  title: Text(
                                    f.description,
                                    style: TpTypography.itemTitle(colors),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    f.subtitle,
                                    style: TpTypography.itemMeta(colors),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(
                                    TpIcons.chevronRight,
                                    size: TpTokens.iconS,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class HomeShortcutEditorPage extends StatefulWidget {
  const HomeShortcutEditorPage({super.key, required this.storage});
  final StorageService storage;

  @override
  State<HomeShortcutEditorPage> createState() => _HomeShortcutEditorPageState();
}

class _HomeShortcutEditorPageState extends State<HomeShortcutEditorPage> {
  late final _available = {
    for (final f in featureEntries)
      if (f.id != 'campus_card') f.id: f,
  };
  late final List<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.storage.pinnedQuickFeatureIds;
    _selected = saved == null
        ? homeQuickFeatures(null).map((f) => f.id).toList()
        : pinnedShortcutIds(saved.where(_available.containsKey));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.storage.setPinnedQuickFeatureIds(_selected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAdaptiveFeedback(
        context: context,
        message: '快捷入口保存失败，请重试',
        style: AdaptiveFeedbackStyle.error,
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _move(int index, int by) {
    unawaited(AppHaptics.play(AppHaptics.selection));
    setState(() {
      final id = _selected.removeAt(index);
      _selected.insert(index + by, id);
    });
  }

  void _resetDefaults() {
    unawaited(AppHaptics.play(AppHaptics.selection));
    setState(() {
      _selected
        ..clear()
        ..addAll(homeQuickFeatures(null).map((f) => f.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: colors.canvas,
        appBar: BlurredAppBar(
          leading: IconButton(
            tooltip: '取消',
            icon: const Icon(TpIcons.close),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          title: const Text('编辑首页快捷'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _resetDefaults,
              child: const Text('恢复默认'),
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
        body: TpPageBody(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              TpTokens.space4,
              TpTokens.space4,
              TpTokens.space4,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              TpCard(
                leadingIcon: TpIcons.sliders,
                title: '已选 ${_selected.length}/$maxPinnedQuickFeatures',
                child: Column(
                  children: [
                    for (var i = 0; i < _selected.length; i++)
                      ListTile(
                        key: ValueKey('pin-${_selected[i]}'),
                        leading: Icon(
                          _available[_selected[i]]!.icon.icon ??
                              TpIcons.activities,
                          color: colors.brandInk,
                        ),
                        title: Text(_available[_selected[i]]!.description),
                        subtitle: Text(
                          _available[_selected[i]]!.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '上移',
                              onPressed: i == 0 || _saving
                                  ? null
                                  : () => _move(i, -1),
                              icon: const Icon(TpIcons.arrowUp),
                            ),
                            IconButton(
                              tooltip: '下移',
                              onPressed:
                                  i == _selected.length - 1 || _saving
                                      ? null
                                      : () => _move(i, 1),
                              icon: const Icon(TpIcons.arrowDown),
                            ),
                          ],
                        ),
                      ),
                    if (_selected.length < maxPinnedQuickFeatures)
                      Padding(
                        padding: const EdgeInsets.all(TpTokens.space3),
                        child: Text(
                          '首页的空位会按默认顺序补齐。',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: TpTokens.space4),
              TpCard(
                leadingIcon: TpIcons.activities,
                title: '选择服务',
                child: Column(
                  children: [
                    for (final f in _available.values)
                      CheckboxListTile(
                        secondary: Icon(
                          f.icon.icon ?? TpIcons.activities,
                          color: colors.brandInk,
                        ),
                        title: Text(f.description),
                        subtitle: Text(
                          f.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: _selected.contains(f.id),
                        onChanged: _saving ||
                                (!_selected.contains(f.id) &&
                                    _selected.length == maxPinnedQuickFeatures)
                            ? null
                            : (checked) {
                                unawaited(
                                  AppHaptics.play(AppHaptics.selection),
                                );
                                setState(() {
                                  if (checked == true) {
                                    _selected.add(f.id);
                                  } else {
                                    _selected.remove(f.id);
                                  }
                                });
                              },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
