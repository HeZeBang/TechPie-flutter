import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../services/assignment_service.dart';
import '../services/deadline_reminder_service.dart';
import '../services/service_provider.dart';
import '../utils/adaptive_motion.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/page_refresh.dart';
import '../widgets/swipeable_card.dart';
import 'custom_deadline_editor_page.dart';
import 'hidden_assignments_page.dart';

class AssignmentsPage extends StatefulWidget {
  const AssignmentsPage({super.key});

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

enum _SelectionPurpose { manage, reminders }

class _AssignmentsPageState extends State<AssignmentsPage> {
  bool _pastCollapsed = true;
  bool _completedCollapsed = true;
  _SelectionPurpose? _selectionPurpose;
  AssignmentService? _assignmentService;
  int? _manageSelectionEpoch;
  int? _reminderSelectionEpoch;
  bool _savingReminders = false;
  bool _showAssignments = true;
  bool _showExams = true;
  final Set<String> _selected = {};
  final Set<String> _initialReminderKeys = {};
  Timer? _countdownTimer;

  bool get _selectionMode => _selectionPurpose != null;
  bool get _selectingReminders => _selectionPurpose == _SelectionPurpose.reminders;
  bool get _loadingReminders => _selectingReminders && _reminderSelectionEpoch == null;
  bool get _remindersBusy => _loadingReminders || _savingReminders;

  @override
  void initState() {
    super.initState();
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = ServiceProvider.of(context).assignmentService;
    if (!identical(_assignmentService, service)) {
      _assignmentService?.removeListener(_onAssignmentServiceChanged);
      _assignmentService = service..addListener(_onAssignmentServiceChanged);
      if (_selectionPurpose == _SelectionPurpose.manage) _clearSelection();
    }
    // ignore: deprecated_member_use
    final isVisible = TickerMode.of(context);
    if (isVisible) {
      if (_countdownTimer == null || !_countdownTimer!.isActive) {
        _startCountdownTimer();
      }
    } else {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  @override
  void dispose() {
    _assignmentService?.removeListener(_onAssignmentServiceChanged);
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onAssignmentServiceChanged() {
    if (_selectionPurpose == _SelectionPurpose.manage &&
        _manageSelectionEpoch != _assignmentService?.identityEpoch) {
      setState(_clearSelection);
    }
  }

  void _exitSelection() {
    if (_remindersBusy) return;
    setState(_clearSelection);
  }

  void _clearSelection() {
    _selectionPurpose = null;
    _manageSelectionEpoch = null;
    _selected.clear();
    _initialReminderKeys.clear();
    _reminderSelectionEpoch = null;
  }

  void _enterSelectionWith(AssignmentService service, String key, int epoch) {
    if (_selectionMode ||
        !identical(_assignmentService, service) ||
        epoch != service.identityEpoch) {
      return;
    }
    setState(() {
      _selectionPurpose = _SelectionPurpose.manage;
      _manageSelectionEpoch = epoch;
      _selected.add(key);
    });
  }

  Future<void> _enterReminderSelection(
    AssignmentService service,
    DeadlineReminderService? reminders,
    List<Assignment> visible,
  ) async {
    if (_selectionMode || reminders == null || visible.isEmpty) return;
    final epoch = service.identityEpoch;
    final keys = visible.map(service.reminderKeyFor).toSet();
    setState(() => _selectionPurpose = _SelectionPurpose.reminders);
    try {
      final linked = await reminders.linkedKeys(keys, epoch: epoch);
      if (!mounted) return;
      setState(() {
        _reminderSelectionEpoch = epoch;
        _initialReminderKeys.addAll(linked);
        _selected.addAll(linked);
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(_clearSelection);
      _showReminderError(error, '无法读取提醒事项');
    }
  }

  void _toggleSelection(String key) {
    if (_remindersBusy) return;
    setState(() {
      if (_selected.remove(key)) {
        if (_selected.isEmpty && !_selectingReminders) _clearSelection();
      } else {
        _selected.add(key);
      }
    });
  }

  void _selectAll(Set<String> allKeys) {
    if (_remindersBusy || allKeys.isEmpty) return;
    setState(() {
      if (allKeys.every(_selected.contains)) {
        _selected.clear();
        if (!_selectingReminders) _clearSelection();
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
      if (_selected.isEmpty) _clearSelection();
    });
  }

  Future<void> _resetSelected(AssignmentService service, int? epoch) async {
    if (_selectionPurpose != _SelectionPurpose.manage ||
        !identical(_assignmentService, service) ||
        _manageSelectionEpoch != epoch ||
        service.identityEpoch != epoch ||
        _selected.isEmpty) {
      return;
    }
    await service.resetOverrides(_selected.toList());
    if (mounted &&
        identical(_assignmentService, service) &&
        _manageSelectionEpoch == epoch) {
      _exitSelection();
    }
  }

  Future<void> _saveReminderSelection(
    DeadlineReminderService reminders,
    Set<String> visibleKeys,
  ) async {
    final epoch = _reminderSelectionEpoch;
    if (_remindersBusy || epoch == null) return;
    final add = _selected.difference(_initialReminderKeys).intersection(visibleKeys);
    final remove = _initialReminderKeys.difference(_selected).intersection(visibleKeys);
    if (add.isEmpty && remove.isEmpty) return;

    setState(() => _savingReminders = true);
    try {
      final result = await reminders.saveSelection(epoch: epoch, add: add, remove: remove);
      if (!mounted) return;
      setState(() {
        if (result.failed == 0) {
          _clearSelection();
        } else {
          _initialReminderKeys
            ..addAll(result.added)
            ..addAll(result.existing)
            ..removeAll(result.removed);
        }
      });
      final message = [
        if (result.added.isNotEmpty) '已添加 ${result.added.length} 项',
        if (result.removed.isNotEmpty) '已移除 ${result.removed.length} 项',
        if (result.existing.isNotEmpty) '${result.existing.length} 项已在提醒事项中',
        if (result.failed > 0) '${result.failed} 项保存失败',
      ].join('，');
      showAdaptiveFeedback(
        context: context,
        message: message,
        style: result.failed > 0 ? AdaptiveFeedbackStyle.error : AdaptiveFeedbackStyle.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      if (error is PlatformException && error.code == 'reminders_workspace_changed') {
        setState(_clearSelection);
      }
      _showReminderError(error, '无法保存提醒事项');
    } finally {
      if (mounted) setState(() => _savingReminders = false);
    }
  }

  void _showReminderError(Exception error, String fallback) {
    final message = switch (error) {
      PlatformException(code: 'reminders_denied') => '请在系统设置中允许 TechPie 访问提醒事项',
      PlatformException(code: 'reminders_no_list') => '找不到可写入的提醒事项列表',
      PlatformException(code: 'reminders_list_creation_failed') => '无法创建 Deadline 提醒事项列表',
      PlatformException(code: 'reminders_workspace_changed') => '当前账户已切换，请重新选择提醒事项',
      MissingPluginException() => '当前设备无法访问提醒事项',
      _ => fallback,
    };
    showAdaptiveFeedback(context: context, message: message, style: AdaptiveFeedbackStyle.error);
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
    final services = ServiceProvider.of(context);
    final assignmentService = services.assignmentService;
    final reminders = services.deadlineReminderService;
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
        return AdaptiveNavigationScaffold(
          extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
          appBar: _selectionMode
              ? _buildSelectionAppBar(assignmentService, visible, reminders)
              : _buildNormalAppBar(context, assignmentService, reminders, visible),
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
    DeadlineReminderService? reminders,
    List<Assignment> visible,
  ) {
    final canManageReminders = reminders != null && visible.isNotEmpty;
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
                  const IosNativeNavigationBarMenuItem(
                    value: 'addDeadline',
                    title: '添加 Deadline',
                    sfSymbol: 'plus',
                  ),
                  if (canManageReminders)
                    const IosNativeNavigationBarMenuItem(
                      value: 'manageReminders',
                      title: '添加到提醒事项',
                      sfSymbol: 'list.bullet.circle',
                    ),
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
            case 'addDeadline':
              unawaited(CustomDeadlineEditorPage.open(context));
            case 'manageReminders':
              unawaited(_enterReminderSelection(service, reminders, visible));
            case 'hidden':
              unawaited(
                pushAdaptivePage<void>(
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
        if (isDesktop())
          PageRefreshButton(
            onRefresh: () => _refresh(service),
            refreshing: service.loading,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多操作',
          onSelected: (v) {
            switch (v) {
              case 'toggleAssignments':
                _toggleAssignmentsVisibility();
              case 'toggleExams':
                _toggleExamsVisibility();
              case 'addDeadline':
                unawaited(CustomDeadlineEditorPage.open(context));
              case 'manageReminders':
                unawaited(_enterReminderSelection(service, reminders, visible));
              case 'hidden':
                unawaited(
                  pushAdaptivePage<void>(
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
            const PopupMenuItem(
              value: 'addDeadline',
              child: Row(
                children: [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 12),
                  Text('添加 Deadline'),
                ],
              ),
            ),
            if (reminders != null)
              PopupMenuItem(
                value: 'manageReminders',
                enabled: canManageReminders,
                child: const Row(
                  children: [
                    Icon(Icons.checklist, size: 20),
                    SizedBox(width: 12),
                    Text('添加到提醒事项'),
                  ],
                ),
              ),
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
        DeadlineKind.custom => true,
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
      _clearSelection();
    });
  }

  void _toggleExamsVisibility() {
    setState(() {
      _showExams = !_showExams;
      _clearSelection();
    });
  }

  PreferredSizeWidget _buildSelectionAppBar(
    AssignmentService service,
    List<Assignment> visible,
    DeadlineReminderService? reminders,
  ) {
    final manageEpoch = _manageSelectionEpoch;
    final keyFor = _selectingReminders ? service.reminderKeyFor : AssignmentOverrides.keyFor;
    final visibleKeys = visible.map(keyFor).toSet();
    final selectedCount = visibleKeys.intersection(_selected).length;
    final allSelected = visibleKeys.isNotEmpty && selectedCount == visibleKeys.length;
    final title = _loadingReminders
        ? '正在读取提醒事项…'
        : _selectingReminders && selectedCount == 0
            ? '选择截止事项'
            : '已选择 $selectedCount 个';
    final hasChanges =
        visibleKeys.any((key) => _selected.contains(key) != _initialReminderKeys.contains(key));
    final VoidCallback? save =
        _selectingReminders && reminders != null && hasChanges && !_remindersBusy
            ? () => unawaited(_saveReminderSelection(reminders, visibleKeys))
            : null;
    final saveLabel = _savingReminders ? '保存中…' : '保存';
    if (isIos()) {
      return IosNativeNavigationBar(
        title: title,
        selectionMode: true,
        leadingItems: [
          IosNativeNavigationBarItem(
            id: 'cancelSelection',
            title: '取消',
            accessibilityLabel: '退出多选',
            placementGroup: 'leading-main',
            enabled: !_remindersBusy,
          ),
        ],
        trailingItems: [
          IosNativeNavigationBarItem(
            id: 'toggleSelectAll',
            title: allSelected ? '全不选' : '全选',
            enabled: visibleKeys.isNotEmpty && !_remindersBusy,
            accessibilityLabel: allSelected ? '全不选' : '全选',
            placementGroup: 'selection-actions',
          ),
          if (_selectingReminders)
            IosNativeNavigationBarItem(
              id: 'saveReminders',
              title: saveLabel,
              accessibilityLabel: saveLabel,
              enabled: save != null,
              role: IosNativeNavigationBarItemRole.done,
              placementGroup: 'selection-actions',
            )
          else
            IosNativeNavigationBarItem(
              id: 'selectionMore',
              sfSymbol: 'ellipsis.circle',
              accessibilityLabel: '更多选择操作',
              placementGroup: 'selection-actions',
              menuItems: [
                const IosNativeNavigationBarMenuItem(
                  value: 'invertSelection',
                  title: '反选',
                  sfSymbol: 'arrow.triangle.2.circlepath',
                ),
                IosNativeNavigationBarMenuItem(
                  value: 'resetSelected',
                  title: '重置状态',
                  sfSymbol: 'arrow.counterclockwise',
                  destructive: _selected.isNotEmpty,
                ),
              ],
            ),
        ],
        onItemPressed: (id) {
          switch (id) {
            case 'cancelSelection':
              _exitSelection();
            case 'toggleSelectAll':
              _selectAll(visibleKeys);
            case 'saveReminders':
              save?.call();
          }
        },
        onMenuSelected: (_, value) {
          switch (value) {
            case 'invertSelection':
              _invertSelection(visible);
            case 'resetSelected':
              unawaited(_resetSelected(service, manageEpoch));
          }
        },
      );
    }

    return BlurredAppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _remindersBusy ? null : _exitSelection,
        tooltip: '退出多选',
      ),
      title: Text(title),
      actions: [
        IconButton(
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          tooltip: allSelected ? '全不选' : '全选',
          onPressed: _remindersBusy || visibleKeys.isEmpty ? null : () => _selectAll(visibleKeys),
        ),
        if (_selectingReminders)
          TextButton(onPressed: save, child: Text(saveLabel))
        else ...[
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
                : () => unawaited(_resetSelected(service, manageEpoch)),
          ),
        ],
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
            child: PageRefreshIndicator(
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

    final uncompleted = sorted.where((a) => !service.isCompleted(a)).toList();
    final completed = sorted.where((a) => service.isCompleted(a)).toList()
      ..sort((a, b) => b.effectiveDue.compareTo(a.effectiveDue));

    final overdue = uncompleted
        .where((a) => a.effectiveDue.isBefore(now))
        .toList()
      ..sort((a, b) => a.effectiveDue.compareTo(b.effectiveDue));
    final upcoming = uncompleted
        .where((a) => !a.effectiveDue.isBefore(now))
        .toList()
      ..sort((a, b) {
        final targetA =
            (a.effectiveLateDue != null && a.due.isBefore(now))
                ? a.effectiveLateDue!
                : a.due;
        final targetB =
            (b.effectiveLateDue != null && b.due.isBefore(now))
                ? b.effectiveLateDue!
                : b.due;
        return targetA.compareTo(targetB);
      });

    final todayLabel = DateFormat('yyyy-MM-dd EEE').format(now);
    final itemLabel = sorted.any((item) => item is CustomDeadline)
        ? 'ddl'
        : _filteredItemLabel;

    return PageRefreshIndicator(
      onRefresh: () async => _refresh(service),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          AppShellMetrics.bottomContentPaddingOf(context),
        ),
        children: [
          if (overdue.isNotEmpty) ...[
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
                      '已逾期 (${overdue.length})',
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
            // One list child per card, not a Column of them: a single tall
            // child skews the list's extent estimate until it is laid out.
            if (!_pastCollapsed)
              ...overdue.map((a) => _buildItem(context, service, a)),
            const SizedBox(height: 4),
          ],
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
                  '没有未完成的 $itemLabel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...upcoming.map((a) => _buildItem(context, service, a)),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () =>
                  setState(() => _completedCollapsed = !_completedCollapsed),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _completedCollapsed
                          ? Icons.chevron_right
                          : Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '已完成 (${completed.length})',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _completedCollapsed ? '展开' : '折叠',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!_completedCollapsed) ...[
              const SizedBox(height: 8),
              ...completed.map((a) => _buildItem(context, service, a)),
            ],
          ],
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
    final epoch = service.identityEpoch;
    final selectionKey = _selectingReminders ? service.reminderKeyFor(a) : key;
    final selected = _selected.contains(selectionKey);
    final completed = service.isCompleted(a);
    final scheme = Theme.of(context).colorScheme;

    final card = _AssignmentCard(
      assignment: a,
      completed: completed,
      hasOverride: service.hasCompletionOverride(a),
      selected: selected,
      selectionMode: _selectionMode && !_loadingReminders,
      onTap: () => unawaited(_onTapItem(context, service, a, selectionKey)),
      onLongPress: _selectionMode
          ? null
          : () => _enterSelectionWith(service, key, epoch),
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
            onStartSwipe: () => unawaited(_toggleCompleted(context, service, a)),
            onDismissed: () => _onDismiss(context, service, a, key),
            child: card,
          );

    // Stable key by override-key so swapping selection mode keeps the
    // entry animation from re-triggering. Each new key (unhide, undo,
    // first appearance) plays the enter animation; existing items just
    // rebuild in place.
    return CardEnterAnimation(key: ValueKey(key), child: inner);
  }

  Future<void> _toggleCompleted(
    BuildContext context,
    AssignmentService service,
    Assignment assignment,
  ) async {
    try {
      await service.toggleCompleted(assignment);
    } catch (_) {
      if (!context.mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '更新完成状态失败，请重试',
        style: AdaptiveFeedbackStyle.error,
      );
    }
  }

  void _onDismiss(
    BuildContext context,
    AssignmentService service,
    Assignment a,
    String key,
  ) {
    const undoWindow = Duration(seconds: 4);
    final epoch = service.identityEpoch;
    unawaited(service.hide(a, reminderUndoWindow: undoWindow));

    showAdaptiveFeedback(
      context: context,
      message: '已忽略「${a.title}」',
      style: AdaptiveFeedbackStyle.info,
      duration: undoWindow,
      actionLabel: '撤销',
      onAction: () {
        if (epoch == service.identityEpoch) unawaited(service.unhide(key));
      },
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
    if (a is CustomDeadline) {
      await CustomDeadlineEditorPage.open(context, deadline: a);
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

String _formatRemainingTime(
  DateTime due,
  DateTime now, {
  String prefix = 'Remain',
}) {
  final diff = due.difference(now);
  if (diff.isNegative || diff.inSeconds <= 0) {
    return 'Overdue';
  }
  final days = diff.inDays;
  final hours = (diff.inHours % 24).toString().padLeft(2, '0');
  final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
  if (days > 0) {
    return '$prefix: ${days}d $hours:$minutes:$seconds';
  }
  return '$prefix: $hours:$minutes:$seconds';
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
    final lateDue = assignment.effectiveLateDue;
    final finalDue = assignment.effectiveDue;
    final isPast = finalDue.isBefore(now);
    final isLateWindow = !completed &&
        lateDue != null &&
        assignment.due.isBefore(now) &&
        !isPast;

    final formatter = DateFormat('MM/dd HH:mm');
    final displayDue = isLateWindow ? lateDue : assignment.due;
    final dueLabel = isLateWindow ? 'Late Due: ' : 'Due: ';
    final dueString = formatter.format(displayDue);
    final subtitle = switch (assignment) {
      ExamAssignment(:final location) => location.trim(),
      _ => assignment.course,
    };

    Color statusColor() {
      if (completed) return Colors.green;
      if (isPast || isLateWindow) return Colors.red;
      final hoursLeft = displayDue.difference(now).inHours;
      if (hoursLeft < 24) return Colors.orange;
      return theme.colorScheme.primary;
    }

    final statusLabel = assignment.status;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? theme.colorScheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  if (assignment is! CustomDeadline) ...[
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
                  ],
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
                    duration: appAnimationDuration(
                      context,
                      const Duration(milliseconds: 280),
                    ),
                    switchInCurve: isIos()
                        ? Curves.easeInOut
                        : Curves.easeInOutCubicEmphasized,
                    switchOutCurve: isIos()
                        ? Curves.easeInOut
                        : Curves.easeInOutCubicEmphasized,
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
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: completed
                            ? theme.colorScheme.onSurfaceVariant
                            : (isPast || isLateWindow
                                ? Colors.red
                                : theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$dueLabel$dueString',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: completed
                                ? theme.colorScheme.onSurfaceVariant
                                : (isPast || isLateWindow
                                    ? Colors.red
                                    : theme.colorScheme.onSurfaceVariant),
                            fontWeight: (isPast || isLateWindow) && !completed
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: appAnimationDuration(
                      context,
                      const Duration(milliseconds: 320),
                    ),
                    switchInCurve:
                        isIos() ? Curves.easeOut : Curves.easeOutBack,
                    switchOutCurve:
                        isIos() ? Curves.easeIn : Curves.easeInCubic,
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
                        : (isPast
                            ? Text(
                                'Overdue',
                                key: const ValueKey('overdue'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : (isLateWindow
                                ? Text(
                                    _formatRemainingTime(
                                      lateDue,
                                      now,
                                      prefix: 'Late',
                                    ),
                                    key: const ValueKey('late_remain'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  )
                                : Text(
                                    _formatRemainingTime(assignment.due, now),
                                    key: const ValueKey('remain'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ))),
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
