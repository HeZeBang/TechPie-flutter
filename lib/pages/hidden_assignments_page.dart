import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../services/assignment_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/app_shell/app_shell_tab_bar.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class HiddenAssignmentsPage extends StatefulWidget {
  const HiddenAssignmentsPage({super.key});

  @override
  State<HiddenAssignmentsPage> createState() => _HiddenAssignmentsPageState();
}

class _HiddenAssignmentsPageState extends State<HiddenAssignmentsPage> {
  bool _selectionMode = false;
  final Set<String> _selected = {};

  /// On iOS the selection toolbar takes the tab bar's place, as it does in
  /// Photos, Files and Mail, instead of stacking a second bar above it.
  AppShellTabBarHold? _tabBarHold;

  @override
  void dispose() {
    _tabBarHold?.release();
    super.dispose();
  }

  void _enterSelectionMode() {
    if (isIos()) _tabBarHold ??= AppShellTabBar.maybeOf(context)?.hide();
    setState(() {
      _selectionMode = true;
    });
  }

  void _exitSelectionMode() {
    _tabBarHold?.release();
    _tabBarHold = null;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
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

  void _restoreSelected() {
    final service = ServiceProvider.of(context).assignmentService;
    final count = _selected.length;
    for (final key in _selected.toList()) {
      unawaited(service.unhide(key));
    }
    _exitSelectionMode();
    showAdaptiveFeedback(
      context: context,
      message: '已恢复 $count 项',
      style: AdaptiveFeedbackStyle.success,
    );
  }

  /// The selection title, in the words iOS uses: nothing chosen yet reads as
  /// an instruction, not as "0 selected".
  String get _selectionTitle =>
      _selected.isEmpty ? '选择项目' : '已选择 ${_selected.length} 项';

  @override
  Widget build(BuildContext context) {
    final service = ServiceProvider.of(context).assignmentService;
    final theme = Theme.of(context);
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topPad = isIos() || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final hiddenKeys = service.overrides.hidden.toList();
        final selectedAll =
            hiddenKeys.isNotEmpty && _selected.length == hiddenKeys.length;
        if (_selectionMode && hiddenKeys.isEmpty) {
          // Everything was restored from elsewhere: nothing left to select.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectionMode) _exitSelectionMode();
          });
        }

        return Scaffold(
          extendBodyBehindAppBar: !isIos() && !useLegacyIosChrome,
          appBar: isIos()
              ? IosNativeNavigationBar(
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
                  // Two items rather than one that restyles: each keeps its
                  // own native button, so switching modes only swaps which
                  // one is shown.
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
                )
              : BlurredAppBar(
                  centerTitle: false,
                  title: Text(
                    _selectionMode ? _selectionTitle : '已忽略的事项',
                  ),
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
                        onPressed:
                            _selected.isNotEmpty ? _restoreSelected : null,
                        icon: const Icon(Icons.restore),
                      ),
                    if (hiddenKeys.isNotEmpty)
                      IconButton(
                        tooltip: _selectionMode ? '完成' : '选择',
                        icon: Icon(
                          _selectionMode
                              ? Icons.check
                              : Icons.checklist_outlined,
                        ),
                        onPressed: _selectionMode
                            ? _exitSelectionMode
                            : _enterSelectionMode,
                      ),
                  ],
                ),
          // The selection toolbar, where the tab bar was while selecting.
          // Mounted for the page's life and offstage outside selection, so
          // its native button is not created on the frame selection starts.
          bottomNavigationBar: isIos()
              ? Offstage(
                  offstage: !_selectionMode,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          CNButton(
                            label: '恢复',
                            semanticLabel: '恢复所选事项',
                            enabled: _selected.isNotEmpty,
                            onPressed: _selected.isEmpty ? null : _restoreSelected,
                            tint: theme.colorScheme.primary,
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
                  child: _buildEmptyState(theme),
                )
              : _buildList(context, service, hiddenKeys, theme, topPad),
        );
      },
    );
  }

  /// An empty list says what the page is for, the way ContentUnavailableView
  /// does: a symbol, a title and one line of explanation.
  Widget _buildEmptyState(ThemeData theme) {
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIos() ? CupertinoIcons.eye_slash : Icons.visibility_off_outlined,
              size: 48,
              color: secondary,
            ),
            const SizedBox(height: 12),
            Text('没有被忽略的事项', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '在 Deadlines 中忽略的事项会出现在这里，随时可以恢复。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreOne(String key) async {
    final service = ServiceProvider.of(context).assignmentService;
    await service.unhide(key);
    if (!mounted) return;
    showAdaptiveFeedback(
      context: context,
      message: '已恢复事项',
      style: AdaptiveFeedbackStyle.success,
    );
  }

  Widget _buildList(
    BuildContext context,
    AssignmentService service,
    List<String> hiddenKeys,
    ThemeData theme,
    double topPad,
  ) {
    final lookup = <String, Assignment>{
      for (final a in service.assignments) AssignmentOverrides.keyFor(a): a,
    };
    return ListView.separated(
      padding: EdgeInsets.only(
        top: topPad,
        // The offstage selection toolbar makes Scaffold strip body padding
        // even while the shell tab bar is visible.
        bottom: isIos() && !_selectionMode
            ? AppShellMetrics.bottomContentPaddingOf(context, margin: 0)
            : 0,
      ),
      itemCount: hiddenKeys.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final key = hiddenKeys[i];
        final a = lookup[key];
        final selected = _selected.contains(key);

        final title = a?.title ?? key;
        final subtitle = a == null
            ? '(已无缓存数据)'
            : '${a.kind.label} · ${a.platform.toUpperCase()} · ${a.course}';
        if (isIos()) {
          return _buildIosRow(context, theme, key, title, subtitle, selected);
        }
        return ListTile(
          selected: selected,
          selectedColor: isIos() ? theme.colorScheme.onSurface : null,
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.22,
          ),
          leading: _selectionMode
              ? Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                )
              : const Icon(Icons.visibility_off_outlined),
          title: Text(a?.title ?? key),
          subtitle: Text(
            a == null
                ? '(已无缓存数据)'
                : '${a.kind.label} · ${a.platform.toUpperCase()} · ${a.course}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: isIos() ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null,
          ),
          onTap: _selectionMode ? () => _toggleSelection(key) : null,
          onLongPress: _selectionMode
              ? null
              : () {
                  _enterSelectionMode();
                  _toggleSelection(key);
                },
          trailing: _selectionMode
              ? null
              : AdaptiveButton(
                  icon: Icons.restore,
                  sfSymbol: 'arrow.uturn.backward',
                  width: 44,
                  height: 44,
                  accessibilityLabel: '恢复 ${a?.title ?? key}',
                  onPressed: () => unawaited(_restoreOne(key)),
                ),
        );
      },
    );
  }

  /// A row the way a UIKit list draws one: selection circles that come in with
  /// selection mode, no tint on a selected row, and the row's own action behind
  /// a swipe and a long-press menu rather than a permanent button.
  Widget _buildIosRow(
    BuildContext context,
    ThemeData theme,
    String key,
    String title,
    String subtitle,
    bool selected,
  ) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final tile = Material(
      color: theme.scaffoldBackgroundColor,
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
                      ? theme.colorScheme.primary
                      : CupertinoColors.systemGrey3.resolveFrom(context),
                )
              : Icon(
                  CupertinoIcons.eye_slash,
                  key: const ValueKey('hidden'),
                  color: secondary,
                ),
        ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: secondary),
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
        color: theme.colorScheme.primary,
        child: const Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: EdgeInsetsDirectional.only(end: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.arrow_uturn_left, color: Colors.white),
                SizedBox(width: 6),
                Text('恢复', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
      // Restoring removes the key from the hidden set synchronously, so the
      // row has left the list by the time Dismissible checks for it.
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
        // The menu's preview lays its child out unconstrained; the row spans
        // the list, so give it that width explicitly.
        child: SizedBox(width: MediaQuery.sizeOf(context).width, child: tile),
      ),
    );
  }
}
