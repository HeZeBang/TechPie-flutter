import 'dart:async';

import 'package:flutter/material.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../services/assignment_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_glass_button.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';

class HiddenAssignmentsPage extends StatefulWidget {
  const HiddenAssignmentsPage({super.key});

  @override
  State<HiddenAssignmentsPage> createState() => _HiddenAssignmentsPageState();
}

class _HiddenAssignmentsPageState extends State<HiddenAssignmentsPage> {
  bool _selectionMode = false;
  final Set<String> _selected = {};

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
    });
  }

  void _exitSelectionMode() {
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
    for (final key in _selected.toList()) {
      unawaited(service.unhide(key));
    }
    _exitSelectionMode();
  }

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

        return Scaffold(
          extendBodyBehindAppBar: !isIos() && !useLegacyIosChrome,
          appBar: isIos()
              ? IosNativeNavigationBar(
                  title:
                      _selectionMode ? '已选择 ${_selected.length} 个' : '已忽略的事项',
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
                      title: selectedAll ? 'Deselect All' : 'Select All',
                      enabled: hiddenKeys.isNotEmpty,
                      hidden: !_selectionMode,
                      accessibilityLabel: selectedAll ? '全不选' : '全选',
                      placementGroup: 'leading-main',
                    ),
                  ],
                  trailingItems: [
                    IosNativeNavigationBarItem(
                      id: 'restore',
                      sfSymbol: 'arrow.uturn.backward',
                      enabled: _selected.isNotEmpty,
                      hidden: !_selectionMode,
                      accessibilityLabel: '恢复',
                      placementGroup: 'selection-actions',
                    ),
                    IosNativeNavigationBarItem(
                      id: 'toggleSelection',
                      title: _selectionMode ? 'Done' : 'Select',
                      role: _selectionMode
                          ? IosNativeNavigationBarItemRole.done
                          : IosNativeNavigationBarItemRole.normal,
                      enabled: _selectionMode || hiddenKeys.isNotEmpty,
                      accessibilityLabel: _selectionMode ? '完成' : '选择',
                      placementGroup: 'selection-actions',
                    ),
                  ],
                  onItemPressed: (id) {
                    switch (id) {
                      case 'back':
                        unawaited(maybePopPlatformViewPage<void>(context));
                      case 'toggleSelectAll':
                        if (hiddenKeys.isNotEmpty) {
                          _toggleSelectAll(hiddenKeys);
                        }
                      case 'restore':
                        if (_selected.isNotEmpty) {
                          _restoreSelected();
                        }
                      case 'toggleSelection':
                        _selectionMode
                            ? _exitSelectionMode()
                            : _enterSelectionMode();
                    }
                  },
                )
              : BlurredAppBar(
                  centerTitle: false,
                  title: Text(
                    _selectionMode ? '已选择 ${_selected.length} 个' : '已忽略的事项',
                  ),
                  actions: [
                    if (_selectionMode)
                      IconButton(
                        tooltip: selectedAll ? '全不选' : '全选',
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
          body: hiddenKeys.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: topPad),
                  child: Center(
                    child: Text(
                      '没有被忽略的事项',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : _buildList(context, service, hiddenKeys, theme, topPad),
        );
      },
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
      padding: EdgeInsets.only(top: topPad),
      itemCount: hiddenKeys.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final key = hiddenKeys[i];
        final a = lookup[key];
        final selected = _selected.contains(key);

        return ListTile(
          selected: selected,
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
          ),
          onTap: _selectionMode ? () => _toggleSelection(key) : null,
          onLongPress: _selectionMode
              ? null
              : () {
                  setState(() {
                    _selectionMode = true;
                    _selected.add(key);
                  });
                },
          trailing: _selectionMode
              ? null
              : IosGlassButton(
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
}
