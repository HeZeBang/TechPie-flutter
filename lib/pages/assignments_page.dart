import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../services/assignment_service.dart';
import '../services/deadline_reminder_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/adaptive_motion.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/page_refresh.dart';
import '../widgets/swipeable_card.dart';
import 'custom_deadline_editor_page.dart';
import 'hidden_assignments_page.dart';
import 'third_party_accounts_page.dart';

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
  bool get _selectingReminders =>
      _selectionPurpose == _SelectionPurpose.reminders;
  bool get _loadingReminders =>
      _selectingReminders && _reminderSelectionEpoch == null;
  bool get _remindersBusy => _loadingReminders || _savingReminders;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _startCountdownTimer();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!mounted ||
        !_selectionMode ||
        _remindersBusy ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return false;
    }
    _exitSelection();
    return true;
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
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
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
    final add =
        _selected.difference(_initialReminderKeys).intersection(visibleKeys);
    final remove =
        _initialReminderKeys.difference(_selected).intersection(visibleKeys);
    if (add.isEmpty && remove.isEmpty) return;

    setState(() => _savingReminders = true);
    try {
      final result =
          await reminders.saveSelection(epoch: epoch, add: add, remove: remove);
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
        style: result.failed > 0
            ? AdaptiveFeedbackStyle.error
            : AdaptiveFeedbackStyle.success,
      );
    } on Exception catch (error) {
      if (!mounted) return;
      if (error is PlatformException &&
          error.code == 'reminders_workspace_changed') {
        setState(_clearSelection);
      }
      _showReminderError(error, '无法保存提醒事项');
    } finally {
      if (mounted) setState(() => _savingReminders = false);
    }
  }

  void _showReminderError(Exception error, String fallback) {
    final message = switch (error) {
      PlatformException(code: 'reminders_denied') =>
        '请在系统设置中允许 TechPie 访问提醒事项',
      PlatformException(code: 'reminders_no_list') => '找不到可写入的提醒事项列表',
      PlatformException(code: 'reminders_list_creation_failed') =>
        '无法创建 Deadline 提醒事项列表',
      PlatformException(code: 'reminders_workspace_changed') =>
        '当前账户已切换，请重新选择提醒事项',
      MissingPluginException() => '当前设备无法访问提醒事项',
      _ => fallback,
    };
    showAdaptiveFeedback(
      context: context,
      message: message,
      style: AdaptiveFeedbackStyle.error,
    );
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
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(context);

    return ListenableBuilder(
      listenable: assignmentService,
      builder: (context, _) {
        final allVisible = assignmentService.visibleAssignments;
        final visible = _filterAssignments(allVisible);
        return AdaptiveNavigationScaffold(
          extendBodyBehindAppBar:
              AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
          appBar: _selectionMode
              ? _buildSelectionAppBar(assignmentService, visible, reminders)
              : _buildNormalAppBar(
                  context,
                  assignmentService,
                  reminders,
                  visible,
                ),
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
    return AdaptiveNavigationScaffold.adaptiveBar(
      ios: () => IosNativeNavigationBar(
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
      ),
      material: () => BlurredAppBar(
        title: const Text('Deadlines'),
        actions: [
          if (isDesktop())
            PageRefreshButton(
              onRefresh: () => _refresh(service),
              refreshing: service.loading,
            ),
          PopupMenuButton<String>(
            icon: const Icon(TpIcons.more),
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
                  unawaited(
                    _enterReminderSelection(service, reminders, visible),
                  );
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
                    Icon(TpIcons.add, size: TpTokens.iconM),
                    SizedBox(width: TpTokens.space3),
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
                      Icon(TpIcons.checkCircle, size: TpTokens.iconM),
                      SizedBox(width: TpTokens.space3),
                      Text('添加到提醒事项'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'hidden',
                child: Row(
                  children: [
                    const Icon(TpIcons.eyeOff, size: TpTokens.iconM),
                    const SizedBox(width: TpTokens.space3),
                    Text('查看已忽略 (${service.overrides.hidden.length})'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
    final keyFor = _selectingReminders
        ? service.reminderKeyFor
        : AssignmentOverrides.keyFor;
    final visibleKeys = visible.map(keyFor).toSet();
    final selectedCount = visibleKeys.intersection(_selected).length;
    final allSelected =
        visibleKeys.isNotEmpty && selectedCount == visibleKeys.length;
    final title = _loadingReminders
        ? '正在读取提醒事项…'
        : _selectingReminders && selectedCount == 0
            ? '选择截止事项'
            : '已选择 $selectedCount 个';
    final hasChanges = visibleKeys.any(
      (key) => _selected.contains(key) != _initialReminderKeys.contains(key),
    );
    final VoidCallback? save =
        _selectingReminders && reminders != null && hasChanges && !_remindersBusy
            ? () => unawaited(_saveReminderSelection(reminders, visibleKeys))
            : null;
    final saveLabel = _savingReminders ? '保存中…' : '保存';

    return AdaptiveNavigationScaffold.adaptiveBar(
      ios: () => IosNativeNavigationBar(
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
      ),
      material: () => BlurredAppBar(
        leading: IconButton(
          icon: const Icon(TpIcons.close),
          onPressed: _remindersBusy ? null : _exitSelection,
          tooltip: '退出多选',
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
            tooltip: allSelected ? '全不选' : '全选',
            onPressed: _remindersBusy || visibleKeys.isEmpty
                ? null
                : () => _selectAll(visibleKeys),
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
              icon: const Icon(TpIcons.refresh),
              tooltip: '重置状态',
              onPressed: _selected.isEmpty
                  ? null
                  : () => unawaited(_resetSelected(service, manageEpoch)),
            ),
          ],
        ],
      ),
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
                padding: EdgeInsets.fromLTRB(
                  TpTokens.pageHorizontalPadding,
                  TpTokens.space4,
                  TpTokens.pageHorizontalPadding,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height * 0.55,
                    ),
                    child: Center(
                      child: TpPageBody(
                        child: _emptyState(context, service),
                      ),
                    ),
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
    final colors = context.tpColors;
    final hasSources = ServiceProvider.of(context)
        .thirdPartyAuthService
        .boundPlatforms
        .isNotEmpty;
    final title = !hasSources
        ? '连接课程平台以获取Deadlines'
        : service.loading
            ? '正在同步截止日期…'
            : !service.hasCachedData
                ? '尚未成功同步截止日期'
                : '近期暂无待办截止事项';

    return TpCard(
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
              color: colors.brandSoft,
              borderRadius: BorderRadius.circular(TpTokens.radiusM),
            ),
            alignment: Alignment.center,
            child: Icon(
              TpIcons.deadlines,
              size: TpTokens.iconL + 4,
              color: colors.brandInk,
            ),
          ),
          const SizedBox(height: TpTokens.space4),
          Text(
            title,
            style: TpTypography.cardTitle(colors).copyWith(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          if (!hasSources) ...[
            const SizedBox(height: TpTokens.space2),
            Text(
              '绑定 eGate / Gradescope / Hydro 后将自动聚合全部作业与考试截止时间',
              style: TpTypography.itemMeta(colors),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TpTokens.space4),
            AdaptiveButton(
              icon: TpIcons.linkedAccounts,
              sfSymbol: 'link',
              label: '连接课程平台',
              role: AdaptiveButtonRole.prominent,
              height: 44,
              onPressed: () => unawaited(
                pushAdaptivePage<void>(
                  context,
                  builder: (_) => const ThirdPartyAccountsPage(),
                ),
              ),
            ),
          ],
          if (service.error != null) ...[
            const SizedBox(height: TpTokens.space3),
            Text(
              service.error!,
              style: TpTypography.itemMeta(colors).copyWith(
                color: colors.dangerRed,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasSources) ...[
              const SizedBox(height: TpTokens.space4),
              AdaptiveButton(
                icon: TpIcons.refresh,
                sfSymbol: 'arrow.clockwise',
                label: '重新同步',
                role: AdaptiveButtonRole.standard,
                loading: service.loading,
                width: 180,
                height: 44,
                onPressed: service.loading
                    ? null
                    : () => unawaited(_refresh(service)),
              ),
            ],
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
    final colors = context.tpColors;
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
        final targetA = (a.effectiveLateDue != null && a.due.isBefore(now))
            ? a.effectiveLateDue!
            : a.due;
        final targetB = (b.effectiveLateDue != null && b.due.isBefore(now))
            ? b.effectiveLateDue!
            : b.due;
        return targetA.compareTo(targetB);
      });

    final todayLabel = DateFormat('yyyy-MM-dd EEE').format(now);
    final itemLabel = sorted.any((item) => item is CustomDeadline)
        ? 'ddl'
        : _filteredItemLabel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = math.max(
          TpTokens.pageHorizontalPadding,
          (constraints.maxWidth - TpTokens.singleColumnMaxWidth) / 2,
        );

        return PageRefreshIndicator(
          onRefresh: () async => _refresh(service),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              TpTokens.space2,
              horizontalPadding,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              if (overdue.isNotEmpty) ...[
                _SectionToggleRow(
                  collapsed: _pastCollapsed,
                  leadingIcon: TpIcons.deadlines,
                  leadingColor: colors.dangerRed,
                  label: '已逾期 (${overdue.length})',
                  onTap: () =>
                      setState(() => _pastCollapsed = !_pastCollapsed),
                ),
                // One list child per card, not a Column of them: a single tall
                // child skews the list's extent estimate until it is laid out.
                if (!_pastCollapsed) ...[
                  const SizedBox(height: TpTokens.space2),
                  ...overdue.map((a) => _buildItem(context, service, a)),
                ],
                const SizedBox(height: TpTokens.space1),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: TpTokens.space2),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        height: 1,
                        thickness: 0.75,
                        color: colors.brand.withValues(alpha: 0.35),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TpTokens.space3,
                      ),
                      child: TpBadge(
                        label: '今天 · $todayLabel',
                        tone: TpBadgeTone.brand,
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        height: 1,
                        thickness: 0.75,
                        color: colors.brand.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
              if (upcoming.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: TpTokens.space5),
                  child: Center(
                    child: Text(
                      '没有未完成的 $itemLabel',
                      style: TpTypography.itemMeta(colors).copyWith(
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                ...upcoming.map((a) => _buildItem(context, service, a)),
              if (completed.isNotEmpty) ...[
                const SizedBox(height: TpTokens.space3),
                _SectionToggleRow(
                  collapsed: _completedCollapsed,
                  leadingIcon: TpIcons.checkCircle,
                  leadingColor: colors.successGreen,
                  label: '已完成 (${completed.length})',
                  onTap: () => setState(
                    () => _completedCollapsed = !_completedCollapsed,
                  ),
                ),
                if (!_completedCollapsed) ...[
                  const SizedBox(height: TpTokens.space2),
                  ...completed.map((a) => _buildItem(context, service, a)),
                ],
              ],
            ],
          ),
        );
      },
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
    final colors = context.tpColors;

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
      onQuickToggleComplete: isDesktop() && !_selectionMode
          ? () => unawaited(_toggleCompleted(context, service, a))
          : null,
      onQuickHide: isDesktop() && !_selectionMode
          ? () => _onDismiss(context, service, a, key)
          : null,
    );

    final inner = _selectionMode
        ? Padding(
            padding: const EdgeInsets.only(bottom: TpTokens.sectionGap),
            child: card,
          )
        : SwipeableCard(
            borderRadius: BorderRadius.circular(TpTokens.radiusM),
            bottomMargin: TpTokens.sectionGap,
            startAction: SwipeAction(
              icon: completed ? TpIcons.close : TpIcons.checkCircle,
              label: completed ? '取消完成' : '标记完成',
              background: completed
                  ? colors.surfaceSubtle
                  : colors.successGreen
                      .withValues(alpha: colors.isDark ? 0.24 : 0.14),
              foreground: completed ? colors.textPrimary : colors.successGreen,
            ),
            endAction: SwipeAction(
              icon: TpIcons.delete,
              label: '删除',
              background:
                  colors.dangerRed.withValues(alpha: colors.isDark ? 0.24 : 0.14),
              foreground: colors.dangerRed,
            ),
            onStartSwipe: () => unawaited(_toggleCompleted(context, service, a)),
            onDismissed: () => _onDismiss(context, service, a, key),
            child: card,
          );

    // Stable key by override-key so swapping selection mode keeps the
    // entry animation from re-triggering.
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
      await showAdaptiveContextualNotice(
        context: context,
        iosTitle: '无法打开$itemLabel',
        iosMessage: '这个$itemLabel没有可打开的链接。',
        feedbackMessage: '该$itemLabel没有链接',
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      await showAdaptiveContextualNotice(
        context: context,
        iosTitle: '无法打开作业',
        iosMessage: '链接格式无效。',
        feedbackMessage: '链接无法解析',
        style: AdaptiveFeedbackStyle.error,
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      await showAdaptiveContextualNotice(
        context: context,
        iosTitle: '无法打开作业',
        iosMessage: '目前无法打开这个链接。',
        feedbackMessage: '无法打开链接',
        style: AdaptiveFeedbackStyle.error,
      );
    }
  }
}

class _SectionToggleRow extends StatelessWidget {
  const _SectionToggleRow({
    required this.collapsed,
    required this.leadingIcon,
    required this.leadingColor,
    required this.label,
    required this.onTap,
  });

  final bool collapsed;
  final IconData leadingIcon;
  final Color leadingColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TpTokens.radiusS),
      hoverColor: colors.textPrimary.withValues(
        alpha: colors.isDark ? 0.06 : 0.04,
      ),
      splashColor: colors.brandSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpTokens.space2,
          vertical: TpTokens.space2,
        ),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: TpTokens.iconM,
              color: colors.textMuted,
            ),
            const SizedBox(width: TpTokens.space1),
            Icon(
              leadingIcon,
              size: TpTokens.iconS,
              color: leadingColor,
            ),
            const SizedBox(width: TpTokens.space2),
            Text(
              label,
              style: TpTypography.cardMeta(colors).copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Text(
              collapsed ? '展开' : '折叠',
              style: TpTypography.badge(colors.brandInk),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformErrorsBanner extends StatefulWidget {
  final AssignmentService service;
  const _PlatformErrorsBanner({required this.service});

  @override
  State<_PlatformErrorsBanner> createState() => _PlatformErrorsBannerState();
}

class _PlatformErrorsBannerState extends State<_PlatformErrorsBanner> {
  final Set<String> _retrying = <String>{};

  Future<void> _retryPlatform(String platform) async {
    if (!_retrying.add(platform)) return;
    setState(() {});
    try {
      await widget.service.fetchPlatform(platform);
    } finally {
      if (mounted) {
        setState(() => _retrying.remove(platform));
      } else {
        _retrying.remove(platform);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = widget.service.platformErrors;
    if (errors.isEmpty) return const SizedBox.shrink();
    final colors = context.tpColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TpTokens.pageHorizontalPadding,
        TpTokens.space2,
        TpTokens.pageHorizontalPadding,
        0,
      ),
      child: TpPageBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in errors.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: TpTokens.space2),
                child: TpCard(
                  color: colors.opaqueDangerContainer,
                  borderColor: colors.dangerRed.withValues(alpha: 0.30),
                  borderRadius: TpTokens.radiusS,
                  padding: const EdgeInsets.symmetric(
                    horizontal: TpTokens.space3,
                    vertical: TpTokens.space2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        TpIcons.info,
                        size: TpTokens.iconS,
                        color: colors.dangerRed,
                      ),
                      const SizedBox(width: TpTokens.space2),
                      Expanded(
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: TpTypography.itemMeta(colors).copyWith(
                            color: colors.dangerRed,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _retrying.contains(entry.key)
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.dangerRed,
                                ),
                              )
                            : const Icon(TpIcons.refresh, size: TpTokens.iconS),
                        onPressed: _retrying.contains(entry.key)
                            ? null
                            : () => unawaited(_retryPlatform(entry.key)),
                        color: colors.dangerRed,
                        tooltip: '重试 ${entry.key}',
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
          ],
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

double _urgencyProgress({
  required DateTime due,
  required DateTime now,
  required bool completed,
  required bool isPast,
  required bool isLateWindow,
}) {
  if (completed || isPast || isLateWindow) return 1.0;
  final hoursLeft = due.difference(now).inMinutes / 60.0;
  if (hoursLeft <= 0) return 1.0;
  if (hoursLeft <= 24) {
    return (0.98 - (hoursLeft / 24.0) * 0.13).clamp(0.85, 0.98);
  }
  if (hoursLeft <= 7 * 24) {
    return (0.85 - ((hoursLeft - 24.0) / (6 * 24.0)) * 0.60).clamp(0.25, 0.85);
  }
  return 0.15;
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;
  final bool completed;
  final bool hasOverride;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onQuickToggleComplete;
  final VoidCallback? onQuickHide;

  const _AssignmentCard({
    required this.assignment,
    required this.completed,
    required this.hasOverride,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onQuickToggleComplete,
    this.onQuickHide,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
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
      CustomDeadline(:final course, :final location) => [
          if (course.isNotEmpty) course,
          if (location.isNotEmpty) location,
        ].join(' · '),
      _ => assignment.course,
    };
    final notes = switch (assignment) {
      CustomDeadline(:final notes) => notes,
      _ => '',
    };

    final Color urgencyColor = () {
      if (completed) return colors.successGreen;
      if (isPast || isLateWindow) return colors.dangerRed;
      final hoursLeft = displayDue.difference(now).inHours;
      if (hoursLeft < 24) return colors.dangerRed;
      if (hoursLeft < 72) return colors.warningAmber;
      return colors.infoBlue;
    }();

    final progress = _urgencyProgress(
      due: displayDue,
      now: now,
      completed: completed,
      isPast: isPast,
      isLateWindow: isLateWindow,
    );

    final statusLabel = assignment is CustomDeadline
        ? null
        : completed
            ? (assignment.status == 'Graded' ? 'Graded' : 'Submitted')
            : assignment.status;

    final kindTone = switch (assignment.kind) {
      DeadlineKind.exam => TpBadgeTone.danger,
      DeadlineKind.custom => TpBadgeTone.info,
      DeadlineKind.assignment => TpBadgeTone.brand,
    };

    return TpCard(
      borderRadius: TpTokens.radiusM,
      color: selected ? colors.opaqueBrandContainer : colors.surface,
      borderColor: selected ? colors.brand : null,
      borderWidth: selected ? 1.5 : 0.75,
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(TpTokens.space4),
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
                  size: TpTokens.iconM,
                  color: selected ? colors.brandInk : colors.textMuted,
                ),
                const SizedBox(width: TpTokens.space2),
              ],
              TpBadge(label: assignment.kind.label, tone: kindTone),
              if (assignment is! CustomDeadline) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: TpBadge(
                    label: assignment.platform.toUpperCase(),
                    tone: TpBadgeTone.muted,
                  ),
                ),
              ],
              if (hasOverride) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: '本地标记',
                  child: Icon(
                    TpIcons.edit,
                    size: TpTokens.iconXs,
                    color: colors.brandInk,
                  ),
                ),
              ],
              const Spacer(),
              Flexible(
                child: AnimatedSwitcher(
                  duration: appAnimationDuration(
                    context,
                    const Duration(milliseconds: 280),
                  ),
                  switchInCurve: appAnimationCurve(
                    Curves.easeInOutCubicEmphasized,
                    iosCurve: Curves.easeInOut,
                  ),
                  switchOutCurve: appAnimationCurve(
                    Curves.easeInOutCubicEmphasized,
                    iosCurve: Curves.easeInOut,
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: statusLabel == null
                      ? const SizedBox.shrink()
                      : Text(
                          statusLabel,
                          key: ValueKey(statusLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTypography.badge(urgencyColor),
                        ),
                ),
              ),
              if (onQuickToggleComplete != null || onQuickHide != null) ...[
                const SizedBox(width: TpTokens.space1),
                if (onQuickToggleComplete != null)
                  IconButton(
                    icon: Icon(
                      completed ? TpIcons.close : TpIcons.checkCircle,
                      size: TpTokens.iconS,
                    ),
                    color: completed ? colors.textMuted : colors.successGreen,
                    tooltip: completed ? '取消完成' : '标记完成',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onQuickToggleComplete,
                  ),
                if (onQuickHide != null)
                  IconButton(
                    icon: const Icon(TpIcons.delete, size: TpTokens.iconS),
                    color: colors.textMuted,
                    hoverColor: colors.dangerRed.withValues(alpha: 0.10),
                    tooltip: '忽略',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onQuickHide,
                  ),
              ],
            ],
          ),
          const SizedBox(height: TpTokens.space3),
          Text(
            assignment.title,
            style: TpTypography.itemTitle(colors).copyWith(
              fontSize: 15.5,
              color: completed ? colors.textSecondary : colors.textPrimary,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TpTypography.itemMeta(colors),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TpTypography.itemMeta(colors),
            ),
          ],
          const SizedBox(height: TpTokens.space3),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: TpTokens.space2,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    TpIcons.deadlines,
                    size: TpTokens.iconXs,
                    color: completed
                        ? colors.textMuted
                        : (isPast || isLateWindow
                            ? colors.dangerRed
                            : colors.textMuted),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$dueLabel$dueString',
                      style: TpTypography.itemMeta(colors).copyWith(
                        color: completed
                            ? colors.textMuted
                            : (isPast || isLateWindow
                                ? colors.dangerRed
                                : colors.textMuted),
                        fontWeight: (isPast || isLateWindow) && !completed
                            ? FontWeight.w600
                            : FontWeight.w400,
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
                switchInCurve: appAnimationCurve(
                  Curves.easeOutBack,
                  iosCurve: Curves.easeOut,
                ),
                switchOutCurve: appAnimationCurve(
                  Curves.easeInCubic,
                  iosCurve: Curves.easeIn,
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: completed
                    ? Row(
                        key: const ValueKey('completed'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            TpIcons.checkCircle,
                            size: TpTokens.iconXs,
                            color: colors.successGreen,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '已完成',
                            style: TpTypography.badge(colors.successGreen),
                          ),
                        ],
                      )
                    : (isPast
                        ? Text(
                            'Overdue',
                            key: const ValueKey('overdue'),
                            style: TpTypography.badge(colors.dangerRed),
                          )
                        : (isLateWindow
                            ? Text(
                                _formatRemainingTime(
                                  lateDue,
                                  now,
                                  prefix: 'Late',
                                ),
                                key: const ValueKey('late_remain'),
                                style: TpTypography.badge(colors.dangerRed),
                              )
                            : Text(
                                _formatRemainingTime(assignment.due, now),
                                key: const ValueKey('remain'),
                                style: TpTypography.itemMeta(colors).copyWith(
                                  color: urgencyColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ))),
              ),
            ],
          ),
          const SizedBox(height: TpTokens.space2),
          TpProgressBar(
            progress: progress,
            color: urgencyColor,
          ),
        ],
      ),
    );
  }
}
