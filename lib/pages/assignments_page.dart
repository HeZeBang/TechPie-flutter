import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../services/assignment_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';
import '../widgets/swipeable_card.dart';
import 'hidden_assignments_page.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key});

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  bool _pastCollapsed = true;
  bool _selectionMode = false;
  bool _showAssignments = true;
  bool _showExams = true;
  final Set<String> _selected = {};

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _enterSelectionWith(String key) {
    setState(() {
      _selectionMode = true;
      _selected.add(key);
    });
  }

  void _toggleSelection(String key) {
    setState(() {
      if (_selected.remove(key)) {
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(key);
      }
    });
  }

  void _selectAll(List<Assignment> all) {
    setState(() {
      final allKeys = all.map(AssignmentOverrides.keyFor).toSet();
      if (_selected.length == allKeys.length) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(allKeys);
      }
    });
  }

  void _invertSelection(List<Assignment> all) {
    setState(() {
      final allKeys = all.map(AssignmentOverrides.keyFor).toSet();
      final next = allKeys.difference(_selected);
      _selected
        ..clear()
        ..addAll(next);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _resetSelected(AssignmentService service) async {
    await service.resetOverrides(_selected.toList());
    _exitSelection();
  }

  Future<void> _refresh(AssignmentService service) async {
    await service.fetchAssignments();
    if (!mounted) return;
    final hasError = service.error != null;
    showAdaptiveFeedback(
      context: context,
      message: hasError ? '刷新失败' : '已刷新',
      style: hasError
          ? AdaptiveFeedbackStyle.error
          : AdaptiveFeedbackStyle.success,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignmentService = ServiceProvider.of(context).assignmentService;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return ListenableBuilder(
      listenable: assignmentService,
      builder: (context, _) {
        final allVisible = assignmentService.visibleAssignments;
        final visible = _filterAssignments(allVisible);
        return Scaffold(
          extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
          appBar: _selectionMode
              ? _buildSelectionAppBar(context, assignmentService, visible)
              : _buildNormalAppBar(context, assignmentService),
          body: PopScope(
            canPop: !_selectionMode,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _selectionMode) _exitSelection();
            },
            child: _buildBody(
              context,
              assignmentService,
              allVisible,
              visible,
              topInset,
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildNormalAppBar(
    BuildContext context,
    AssignmentService service,
  ) {
    if (isIos()) {
      return IosNativeNavigationBar(
        title: 'Deadlines',
        largeTitleMode: true,
        trailingItems: [
          IosNativeNavigationBarItem(
            id: 'more',
            sfSymbol: 'ellipsis',
            accessibilityLabel: '更多操作',
            menuItems: [
              IosNativeNavigationBarMenuItem(
                value: 'toggleAssignments',
                title: '显示作业',
                sfSymbol: 'checklist',
                checked: _showAssignments,
              ),
              IosNativeNavigationBarMenuItem(
                value: 'toggleExams',
                title: '显示考试',
                sfSymbol: 'calendar.badge.clock',
                checked: _showExams,
              ),
              IosNativeNavigationBarMenuItem(
                value: '__hidden_section__',
                title: '',
                displayInline: true,
                children: [
                  IosNativeNavigationBarMenuItem(
                    value: 'hidden',
                    title: '查看已忽略 (${service.overrides.hidden.length})',
                  ),
                ],
              ),
            ],
          ),
        ],
        onMenuSelected: (_, value) {
          switch (value) {
            case 'toggleAssignments':
              _toggleAssignmentsVisibility();
            case 'toggleExams':
              _toggleExamsVisibility();
            case 'hidden':
              unawaited(
                pushPlatformViewPage<void>(
                  context,
                  builder: (_) => const HiddenAssignmentsPage(),
                ),
              );
          }
        },
      );
    }

    return BlurredAppBar(
      title: const Text('Deadlines'),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'toggleAssignments':
                _toggleAssignmentsVisibility();
              case 'toggleExams':
                _toggleExamsVisibility();
              case 'hidden':
                unawaited(
                  pushPlatformViewPage<void>(
                    context,
                    builder: (_) => const HiddenAssignmentsPage(),
                  ),
                );
            }
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'toggleAssignments',
              checked: _showAssignments,
              child: const Text('显示作业'),
            ),
            CheckedPopupMenuItem(
              value: 'toggleExams',
              checked: _showExams,
              child: const Text('显示考试'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'hidden',
              child: Row(
                children: [
                  const Icon(Icons.visibility_off_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text('查看已忽略 (${service.overrides.hidden.length})'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Assignment> _filterAssignments(List<Assignment> items) {
    return items.where((item) {
      return switch (item.kind) {
        DeadlineKind.assignment => _showAssignments,
        DeadlineKind.exam => _showExams,
      };
    }).toList();
  }

  String get _filteredItemLabel {
    if (_showAssignments && !_showExams) return '作业';
    if (!_showAssignments && _showExams) return '考试';
    return 'ddl';
  }

  void _toggleAssignmentsVisibility() {
    setState(() {
      _showAssignments = !_showAssignments;
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleExamsVisibility() {
    setState(() {
      _showExams = !_showExams;
      _selectionMode = false;
      _selected.clear();
    });
  }

  PreferredSizeWidget _buildSelectionAppBar(
    BuildContext context,
    AssignmentService service,
    List<Assignment> visible,
  ) {
    final allSelected =
        visible.isNotEmpty && _selected.length == visible.length;
    return BlurredAppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
        tooltip: '退出多选',
      ),
      title: Text('已选择 ${_selected.length} 个'),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? '全不选' : '全选',
          onPressed: () => _selectAll(visible),
        ),
        IconButton(
          icon: const Icon(Icons.flip_to_front),
          tooltip: '反选',
          onPressed: () => _invertSelection(visible),
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: '重置状态',
          onPressed: _selected.isEmpty
              ? null
              : () => unawaited(_resetSelected(service)),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    AssignmentService service,
    List<Assignment> allVisible,
    List<Assignment> filtered,
    double topInset,
  ) {
    final banner = _PlatformErrorsBanner(service: service);

    if (allVisible.isEmpty) {
      return Column(
        children: [
          SizedBox(height: topInset),
          banner,
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(service),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: _emptyState(context, service),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(height: topInset),
        banner,
        Expanded(child: _buildList(context, service, filtered)),
      ],
    );
  }

  Widget _emptyState(BuildContext context, AssignmentService service) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_turned_in_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('No upcoming deadlines', style: theme.textTheme.titleMedium),
          if (service.error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                service.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    AssignmentService service,
    List<Assignment> sorted,
  ) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final past = sorted.where((a) => a.due.isBefore(now)).toList();
    final upcoming = sorted.where((a) => !a.due.isBefore(now)).toList();
    final todayLabel = DateFormat('yyyy-MM-dd EEE').format(now);
    final itemLabel = _filteredItemLabel;

    return RefreshIndicator(
      onRefresh: () async => _refresh(service),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          InkWell(
            onTap: () => setState(() => _pastCollapsed = !_pastCollapsed),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _pastCollapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '已过期 (${past.length})',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _pastCollapsed ? '展开' : '折叠',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_pastCollapsed)
            past.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 16, 16),
                    child: Text(
                      '没有已过期的 $itemLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: past
                        .map((a) => _buildItem(context, service, a))
                        .toList(),
                  ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: theme.colorScheme.primary)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '今天 · $todayLabel',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: theme.colorScheme.primary)),
              ],
            ),
          ),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '没有未来的 $itemLabel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...upcoming.map((a) => _buildItem(context, service, a)),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    AssignmentService service,
    Assignment a,
  ) {
    final key = AssignmentOverrides.keyFor(a);
    final selected = _selected.contains(key);
    final completed = service.isCompleted(a);
    final scheme = Theme.of(context).colorScheme;

    final card = _AssignmentCard(
      assignment: a,
      completed: completed,
      hasOverride: service.hasCompletionOverride(a),
      selected: selected,
      selectionMode: _selectionMode,
      onTap: () => unawaited(_onTapItem(context, service, a, key)),
      onLongPress: _selectionMode ? null : () => _enterSelectionWith(key),
    );

    final inner = _selectionMode
        ? Padding(padding: const EdgeInsets.only(bottom: 12), child: card)
        : SwipeableCard(
            startAction: SwipeAction(
              icon: completed
                  ? Icons.cancel_outlined
                  : Icons.check_circle_outline,
              label: completed ? '取消完成' : '标记完成',
              background: scheme.primaryContainer,
              foreground: scheme.onPrimaryContainer,
            ),
            endAction: SwipeAction(
              icon: Icons.delete_outline,
              label: '删除',
              background: scheme.errorContainer,
              foreground: scheme.onErrorContainer,
            ),
            onStartSwipe: () => unawaited(service.toggleCompleted(a)),
            onDismissed: () => _onDismiss(context, service, a, key),
            child: card,
          );

    // Stable key by override-key so swapping selection mode keeps the
    // entry animation from re-triggering. Each new key (unhide, undo,
    // first appearance) plays the enter animation; existing items just
    // rebuild in place.
    return CardEnterAnimation(key: ValueKey(key), child: inner);
  }

  void _onDismiss(
    BuildContext context,
    AssignmentService service,
    Assignment a,
    String key,
  ) {
    unawaited(service.hide(a));

    showAdaptiveFeedback(
      context: context,
      message: '已忽略「${a.title}」',
      style: AdaptiveFeedbackStyle.info,
      duration: const Duration(seconds: 4),
      actionLabel: '撤销',
      onAction: () => unawaited(service.unhide(key)),
    );
  }

  Future<void> _onTapItem(
    BuildContext context,
    AssignmentService service,
    Assignment a,
    String key,
  ) async {
    final usesIosContextualFeedback = isIos();
    if (_selectionMode) {
      _toggleSelection(key);
      return;
    }
    final url = a.url;
    if (url == null || url.isEmpty) {
      final itemLabel = a.kind == DeadlineKind.exam ? '考试' : '作业';
      if (usesIosContextualFeedback) {
        await showAdaptiveAlertDialog<void>(
          context: context,
          title: '无法打开$itemLabel',
          message: '这个$itemLabel没有可打开的链接。',
          actions: const [
            AdaptiveAlertAction<void>(label: 'Done', isDefault: true),
          ],
        );
      } else {
        showAdaptiveFeedback(
          context: context,
          message: '该$itemLabel没有链接',
          style: AdaptiveFeedbackStyle.info,
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (usesIosContextualFeedback) {
        await showAdaptiveAlertDialog<void>(
          context: context,
          title: '无法打开作业',
          message: '链接格式无效。',
          actions: const [
            AdaptiveAlertAction<void>(label: 'Done', isDefault: true),
          ],
        );
      } else {
        showAdaptiveFeedback(
          context: context,
          message: '链接无法解析',
          style: AdaptiveFeedbackStyle.error,
        );
      }
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      if (usesIosContextualFeedback) {
        await showAdaptiveAlertDialog<void>(
          context: context,
          title: '无法打开作业',
          message: '目前无法打开这个链接。',
          actions: const [
            AdaptiveAlertAction<void>(label: 'Done', isDefault: true),
          ],
        );
      } else {
        showAdaptiveFeedback(
          context: context,
          message: '无法打开链接',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    }
  }
}

class _PlatformErrorsBanner extends StatelessWidget {
  final AssignmentService service;
  const _PlatformErrorsBanner({required this.service});

  @override
  Widget build(BuildContext context) {
    final errors = service.platformErrors;
    if (errors.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: errors.entries.map((entry) {
        return Material(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${entry.key}: ${entry.value}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => unawaited(service.fetchPlatform(entry.key)),
                  color: theme.colorScheme.onErrorContainer,
                  tooltip: '重试 ${entry.key}',
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DeadlineKindChip extends StatelessWidget {
  final DeadlineKind kind;

  const _DeadlineKindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExam = kind == DeadlineKind.exam;
    final background = isExam
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.primaryContainer;
    final foreground = isExam
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        kind.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final bool completed;
  final bool hasOverride;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _AssignmentCard({
    required this.assignment,
    required this.completed,
    required this.hasOverride,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isPast = assignment.due.isBefore(now);

    final formatter = DateFormat('MM/dd HH:mm');
    final dueString = formatter.format(assignment.due);

    Color statusColor() {
      if (completed) return Colors.green;
      if (isPast) return Colors.red;
      final hoursLeft = assignment.due.difference(now).inHours;
      if (hoursLeft < 24) return Colors.orange;
      return theme.colorScheme.primary;
    }

    final statusLabel = completed
        ? (assignment.status == 'Graded' ? 'Graded' : 'Submitted')
        : assignment.status;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? theme.colorScheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selectionMode) ...[
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _DeadlineKindChip(kind: assignment.kind),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      assignment.platform.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (hasOverride) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: '本地标记',
                      child: Icon(
                        Icons.edit_note,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeInOutCubicEmphasized,
                    switchOutCurve: Curves.easeInOutCubicEmphasized,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: statusLabel == null
                        ? const SizedBox.shrink()
                        : Text(
                            statusLabel,
                            key: ValueKey(statusLabel),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: statusColor(),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                assignment.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                assignment.course,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: isPast && !completed
                        ? Colors.red
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Due: $dueString',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isPast && !completed
                          ? Colors.red
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isPast && !completed
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: completed
                        ? Row(
                            key: const ValueKey('completed'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 16,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已完成',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(key: ValueKey('not')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
