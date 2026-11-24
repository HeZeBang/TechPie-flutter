import 'dart:async';
import 'dart:math' as math;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../services/assignment_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/app_shell/app_shell_tab_bar.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class HiddenAssignmentsPage extends StatefulWidget {
  const HiddenAssignmentsPage({super.key});

  @override
  State<HiddenAssignmentsPage> createState() => _HiddenAssignmentsPageState();
}

class _HiddenAssignmentsPageState extends State<HiddenAssignmentsPage> {
  bool _selectionMode = false;
  final Set<String> _selected = {};
  final Set<String> _restoring = {};

  /// On iOS the selection toolbar takes the tab bar's place, as it does in
  /// Photos, Files and Mail, instead of stacking a second bar above it.
  AppShellTabBarHold? _tabBarHold;
  AssignmentService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = ServiceProvider.of(context).assignmentService;
    if (!identical(service, _service)) {
      _service?.removeListener(_onServiceChanged);
      _service = service..addListener(_onServiceChanged);
    }
    _syncTabBarHold();
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    _tabBarHold?.release();
    super.dispose();
  }

  void _syncTabBarHold() {
    final wants = usesIosSelectionToolbar() &&
        _selectionMode &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (wants) {
      _tabBarHold ??= AppShellTabBar.maybeOf(context)?.hide();
    } else {
      _tabBarHold?.release();
      _tabBarHold = null;
    }
  }

  void _onServiceChanged() {
    final hidden = _service!.overrides.hidden;
    if (!_selectionMode) return;
    if (hidden.every(_restoring.contains)) {
      _exitSelectionMode();
    } else if (_selected.any(
      (key) => !hidden.contains(key) || _restoring.contains(key),
    )) {
      setState(
        () => _selected.removeWhere(
          (key) => !hidden.contains(key) || _restoring.contains(key),
        ),
      );
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
    });
    _syncTabBarHold();
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
    _syncTabBarHold();
  }

  void _toggleSelection(String key) {
    setState(() {
      if (_selected.remove(key)) return;
      _selected.add(key);
    });
  }

  void _toggleSelectAll(List<String> allKeys) {
    setState(() {
      if (_selected.length == allKeys.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(allKeys);
      }
    });
  }

  Future<void> _restoreSelected() async {
    final service = ServiceProvider.of(context).assignmentService;
    final keys = _selected.where((key) => !_restoring.contains(key)).toList();
    if (keys.isEmpty) return;
    setState(() => _restoring.addAll(keys));
    _exitSelectionMode();
    var restored = 0;
    var failed = 0;
    for (final key in keys) {
      try {
        await service.unhide(key);
        restored++;
      } catch (_) {
        failed++;
      } finally {
        if (mounted) {
          setState(() => _restoring.remove(key));
        } else {
          _restoring.remove(key);
        }
      }
    }
    if (!mounted) return;
    showAdaptiveFeedback(
      context: context,
      message: failed == 0 ? '已恢复 $restored 项' : '恢复部分事项失败，请重试',
      style: failed == 0
          ? AdaptiveFeedbackStyle.success
          : AdaptiveFeedbackStyle.error,
    );
  }

  String get _selectionTitle =>
      _selected.isEmpty ? '选择项目' : '已选择 ${_selected.length} 项';

  @override
  Widget build(BuildContext context) {
    final service = ServiceProvider.of(context).assignmentService;
    final colors = context.tpColors;
    final topPad = AdaptiveNavigationScaffold.contentTopInsetOf(context);
    final iosToolbar = usesIosSelectionToolbar();

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final hiddenKeys = service.overrides.hidden
            .where((key) => !_restoring.contains(key))
            .toList();
        final selectedAll =
            hiddenKeys.isNotEmpty && _selected.length == hiddenKeys.length;

        return Scaffold(
          backgroundColor: colors.canvas,
          extendBodyBehindAppBar:
              AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
          appBar: AdaptiveNavigationScaffold.adaptiveBar(
            ios: () => IosNativeNavigationBar(
              title: _selectionMode ? _selectionTitle : '已忽略的事项',
              selectionMode: _selectionMode,
              leadingItems: [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Deadlines',
                  sfSymbol: 'chevron.left',
                  hidden: _selectionMode,
                  accessibilityLabel: '返回 Deadlines',
                  placementGroup: 'leading-main',
                ),
                IosNativeNavigationBarItem(
                  id: 'toggleSelectAll',
                  title: selectedAll ? '取消全选' : '全选',
                  enabled: hiddenKeys.isNotEmpty,
                  hidden: !_selectionMode,
                  accessibilityLabel: selectedAll ? '取消全选' : '全选',
                  placementGroup: 'leading-main',
                ),
              ],
              trailingItems: [
                IosNativeNavigationBarItem(
                  id: 'select',
                  title: '选择',
                  enabled: hiddenKeys.isNotEmpty,
                  hidden: _selectionMode,
                  accessibilityLabel: '选择',
                  placementGroup: 'selection-actions',
                ),
                IosNativeNavigationBarItem(
                  id: 'done',
                  title: '完成',
                  role: IosNativeNavigationBarItemRole.done,
                  hidden: !_selectionMode,
                  accessibilityLabel: '完成',
                  placementGroup: 'selection-actions',
                ),
              ],
              onItemPressed: (id) {
                switch (id) {
                  case 'back':
                    unawaited(maybePopAdaptivePage<void>(context));
                  case 'toggleSelectAll':
                    if (hiddenKeys.isNotEmpty) {
                      _toggleSelectAll(hiddenKeys);
                    }
                  case 'select':
                    _enterSelectionMode();
                  case 'done':
                    _exitSelectionMode();
                }
              },
            ),
            material: () => BlurredAppBar(
              centerTitle: false,
              title: Text(_selectionMode ? _selectionTitle : '已忽略的事项'),
              actions: [
                if (_selectionMode)
                  IconButton(
                    tooltip: selectedAll ? '取消全选' : '全选',
                    icon: Icon(
                      selectedAll ? Icons.deselect : Icons.select_all,
                    ),
                    onPressed: hiddenKeys.isEmpty
                        ? null
                        : () => _toggleSelectAll(hiddenKeys),
                  ),
                if (_selectionMode)
                  IconButton(
                    tooltip: '恢复',
                    onPressed: _selected.isNotEmpty
                        ? () => unawaited(_restoreSelected())
                        : null,
                    icon: const Icon(TpIcons.refresh),
                  ),
                if (hiddenKeys.isNotEmpty)
                  IconButton(
                    tooltip: _selectionMode ? '完成' : '选择',
                    icon: Icon(
                      _selectionMode ? TpIcons.check : TpIcons.checkCircle,
                    ),
                    onPressed: _selectionMode
                        ? _exitSelectionMode
                        : _enterSelectionMode,
                  ),
              ],
            ),
          ),
          bottomNavigationBar: iosToolbar
              ? Offstage(
                  offstage: !_selectionMode,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TpTokens.space4,
                        vertical: TpTokens.space2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          CNButton(
                            label: '恢复',
                            semanticLabel: '恢复所选事项',
                            enabled: _selected.isNotEmpty,
                            onPressed: _selected.isEmpty
                                ? null
                                : () => unawaited(_restoreSelected()),
                            tint: colors.brand,
                            config: const CNButtonConfig(
                              style: CNButtonStyle.glass,
                              minHeight: 44,
                              shrinkWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
          body: hiddenKeys.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: topPad),
                  child: _buildEmptyState(colors),
                )
              : _buildList(context, service, hiddenKeys, colors, topPad),
        );
      },
    );
  }

  Widget _buildEmptyState(TpColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpTokens.pageHorizontalPadding,
        ),
        child: TpPageBody(
          child: TpCard(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.space5,
              vertical: TpTokens.space6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(TpTokens.radiusM),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    TpIcons.eyeOff,
                    size: TpTokens.iconL + 4,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: TpTokens.space4),
                Text(
                  '没有被忽略的事项',
                  style: TpTypography.cardTitle(colors).copyWith(fontSize: 16),
                ),
                const SizedBox(height: TpTokens.space2),
                Text(
                  '在 Deadlines 中忽略的事项会出现在这里，随时可以恢复。',
                  textAlign: TextAlign.center,
                  style: TpTypography.itemMeta(colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restoreOne(String key) async {
    final service = ServiceProvider.of(context).assignmentService;
    if (!_restoring.add(key)) return;
    setState(() {});
    try {
      await service.unhide(key);
      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '已恢复事项',
        style: AdaptiveFeedbackStyle.success,
      );
    } catch (_) {
      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '恢复事项失败，请重试',
        style: AdaptiveFeedbackStyle.error,
      );
    } finally {
      if (mounted) {
        setState(() => _restoring.remove(key));
      } else {
        _restoring.remove(key);
      }
    }
  }

  Widget _buildList(
    BuildContext context,
    AssignmentService service,
    List<String> hiddenKeys,
    TpColors colors,
    double topPad,
  ) {
    final iosToolbar = usesIosSelectionToolbar();
    final lookup = <String, Assignment>{
      for (final a in service.assignments) AssignmentOverrides.keyFor(a): a,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = math.max(
          TpTokens.pageHorizontalPadding,
          (constraints.maxWidth - TpTokens.singleColumnMaxWidth) / 2,
        );
        return ListView.separated(
          padding: iosToolbar
              ? EdgeInsets.only(
                  top: topPad,
                  // The offstage selection toolbar makes Scaffold strip body
                  // padding even while the shell tab bar is visible.
                  bottom: _selectionMode
                      ? 0
                      : AppShellMetrics.bottomContentPaddingOf(
                          context,
                          margin: 0,
                        ),
                )
              : EdgeInsets.fromLTRB(
                  horizontal,
                  topPad + TpTokens.space3,
                  horizontal,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
          itemCount: hiddenKeys.length,
          separatorBuilder: (_, __) => iosToolbar
              ? Divider(height: 1, thickness: 0.5, color: colors.divider)
              : const SizedBox(height: TpTokens.space2),
          itemBuilder: (context, i) {
            final key = hiddenKeys[i];
            final a = lookup[key];
            final selected = _selected.contains(key);

            final title = a?.title ?? key;
            final subtitle = switch (a) {
              null => '(已无缓存数据)',
              CustomDeadline(:final kind, :final course, :final location) => [
                  kind.label,
                  if (course.isNotEmpty) course,
                  if (location.isNotEmpty) location,
                ].join(' · '),
              final item =>
                '${item.kind.label} · ${item.platform.toUpperCase()} · ${item.course}',
            };
            if (iosToolbar) {
              return _buildIosRow(context, colors, key, title, subtitle, selected);
            }
            return TpCard(
              color: selected ? colors.opaqueBrandContainer : colors.surface,
              borderColor: selected ? colors.brand : null,
              borderWidth: selected ? 1.5 : 0.75,
              onTap: _selectionMode ? () => _toggleSelection(key) : null,
              onLongPress: _selectionMode
                  ? null
                  : () {
                      _enterSelectionMode();
                      _toggleSelection(key);
                    },
              padding: const EdgeInsets.symmetric(
                horizontal: TpTokens.cardPaddingHorizontal,
                vertical: TpTokens.space3,
              ),
              child: Row(
                children: [
                  Icon(
                    _selectionMode
                        ? (selected
                            ? Icons.check_circle
                            : Icons.circle_outlined)
                        : TpIcons.eyeOff,
                    size: TpTokens.iconM,
                    color: _selectionMode && selected
                        ? colors.brand
                        : colors.textMuted,
                  ),
                  const SizedBox(width: TpTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TpTypography.itemTitle(colors),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  if (!_selectionMode) ...[
                    const SizedBox(width: TpTokens.space2),
                    AdaptiveButton(
                      icon: TpIcons.refresh,
                      sfSymbol: 'arrow.uturn.backward',
                      width: 44,
                      height: 44,
                      accessibilityLabel: '恢复 ${a?.title ?? key}',
                      onPressed: () => unawaited(_restoreOne(key)),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIosRow(
    BuildContext context,
    TpColors colors,
    String key,
    String title,
    String subtitle,
    bool selected,
  ) {
    final tile = Material(
      color: colors.surface,
      child: ListTile(
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _selectionMode
              ? Icon(
                  selected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  key: ValueKey(selected),
                  size: 24,
                  color: selected
                      ? colors.brand
                      : CupertinoColors.systemGrey3.resolveFrom(context),
                )
              : Icon(
                  TpIcons.eyeOff,
                  key: const ValueKey('hidden'),
                  size: TpTokens.iconM,
                  color: colors.textMuted,
                ),
        ),
        title: Text(title, style: TpTypography.itemTitle(colors)),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TpTypography.itemMeta(colors),
        ),
        onTap: _selectionMode ? () => _toggleSelection(key) : null,
      ),
    );
    if (_selectionMode) {
      return Semantics(selected: selected, child: tile);
    }
    return Dismissible(
      key: ValueKey('restore:$key'),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: colors.brand,
        child: const Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.arrow_uturn_left, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  '恢复',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      onDismissed: (_) => unawaited(_restoreOne(key)),
      child: CupertinoContextMenu(
        actions: [
          CupertinoContextMenuAction(
            trailingIcon: CupertinoIcons.arrow_uturn_left,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
              unawaited(_restoreOne(key));
            },
            child: const Text('恢复'),
          ),
        ],
        child: SizedBox(width: MediaQuery.sizeOf(context).width, child: tile),
      ),
    );
  }
}
