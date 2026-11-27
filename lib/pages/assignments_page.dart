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
import '../utils/adaptive_layout.dart';
import '../utils/adaptive_motion.dart';
import '../utils/haptics.dart';
import '../utils/motion.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_popup_menu_button.dart';
import '../widgets/adaptive_progress_indicator.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/desktop_popup.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/page_refresh.dart';
import '../widgets/swipeable_card.dart';
import 'deadline_editor_page.dart';
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
  bool _filterPrefsLoaded = false;
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
    final sp = ServiceProvider.of(context);
    if (!_filterPrefsLoaded) {
      _filterPrefsLoaded = true;
      _showAssignments = sp.storageService.deadlinesShowAssignments;
      _showExams = sp.storageService.deadlinesShowExams;
    }
    final service = sp.assignmentService;
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

  void _enterManageSelection(
    AssignmentService service,
    int epoch, {
    String? key,
  }) {
    if (!mounted ||
        _selectionMode ||
        !identical(_assignmentService, service) ||
        epoch != service.identityEpoch) {
      return;
    }
    setState(() {
      _selectionPurpose = _SelectionPurpose.manage;
      _manageSelectionEpoch = epoch;
      if (key != null) _selected.add(key);
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
      if (_selected.remove(key)) return;
      _selected.add(key);
    });
  }

  void _selectAll(Set<String> allKeys) {
    if (_remindersBusy || allKeys.isEmpty) return;
    setState(() {
      if (allKeys.every(_selected.contains)) {
        _selected.clear();
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
        final now = DateTime.now();
        final allVisible = assignmentService.visibleAssignments
            .where((a) => !a.isExpiredAt(now))
            .toList();
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
    final epoch = service.identityEpoch;
    final VoidCallback? select = visible.isEmpty
        ? null
        : () => _enterManageSelection(service, epoch);

    void handleMenuSelection(String value) {
      switch (value) {
        case 'toggleAssignments':
          _toggleAssignmentsVisibility();
        case 'toggleExams':
          _toggleExamsVisibility();
        case 'select':
          select?.call();
        case 'addDeadline':
          unawaited(DeadlineEditorPage.open(context));
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
    }

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
                  if (select != null)
                    const IosNativeNavigationBarMenuItem(
                      value: 'select',
                      title: '选择',
                      sfSymbol: 'checkmark.circle',
                    ),
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
        onMenuSelected: (_, value) => handleMenuSelection(value),
      ),
      material: () => BlurredAppBar(
        title: const Text('Deadlines'),
        actions: [
          if (isDesktop())
            PageRefreshButton(
              onRefresh: () => _refresh(service),
              refreshing: service.loading,
            ),
          if (usesSidebarLayout(context))
            Builder(
              builder: (anchorContext) => IconButton(
                icon: const Icon(TpIcons.more),
                tooltip: '更多操作',
                onPressed: () => _showDesktopMoreMenu(
                  anchorContext,
                  service,
                  reminders,
                  visible,
                  canManageReminders: canManageReminders,
                  onSelect: select,
                ),
              ),
            )
          else
            AdaptivePopupMenuButton<String>(
              icon: TpIcons.more,
              sfSymbol: 'ellipsis',
              tooltip: '更多操作',
              onSelected: handleMenuSelection,
              items: [
                AdaptivePopupMenuItem<String>(
                  value: 'toggleAssignments',
                  label: '显示作业',
                  checked: _showAssignments,
                ),
                AdaptivePopupMenuItem<String>(
                  value: 'toggleExams',
                  label: '显示考试',
                  checked: _showExams,
                ),
                const AdaptivePopupMenuItem<String>.divider(),
                if (select != null)
                  const AdaptivePopupMenuItem<String>(
                    value: 'select',
                    label: '选择',
                    icon: TpIcons.checkCircle,
                    sfSymbol: 'checkmark.circle',
                  ),
                const AdaptivePopupMenuItem<String>(
                  value: 'addDeadline',
                  label: '添加 Deadline',
                  icon: TpIcons.add,
                  sfSymbol: 'plus',
                ),
                if (reminders != null)
                  AdaptivePopupMenuItem<String>(
                    value: 'manageReminders',
                    label: '添加到提醒事项',
                    icon: TpIcons.checkCircle,
                    sfSymbol: 'checklist',
                    enabled: canManageReminders,
                  ),
                AdaptivePopupMenuItem<String>(
                  value: 'hidden',
                  label: '查看已忽略 (${service.overrides.hidden.length})',
                  icon: TpIcons.eyeOff,
                  sfSymbol: 'eye.slash',
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showDesktopMoreMenu(
    BuildContext anchorContext,
    AssignmentService service,
    DeadlineReminderService? reminders,
    List<Assignment> visible, {
    required bool canManageReminders,
    required VoidCallback? onSelect,
  }) {
    showDesktopPopover(
      anchorContext: anchorContext,
      width: 232,
      placement: DesktopPopoverPlacement.belowEnd,
      offset: const Offset(0, 6),
      builder: (menuContext, close) {
        final colors = menuContext.tpColors;
        return DesktopPopoverSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopMenuRow(
                leading: _showAssignments
                    ? const Icon(TpIcons.check, size: TpTokens.iconS)
                    : const SizedBox(width: TpTokens.iconS),
                title: Text('显示作业', style: TpTypography.itemTitle(colors)),
                selected: _showAssignments,
                onTap: () {
                  close();
                  _toggleAssignmentsVisibility();
                },
              ),
              DesktopMenuRow(
                leading: _showExams
                    ? const Icon(TpIcons.check, size: TpTokens.iconS)
                    : const SizedBox(width: TpTokens.iconS),
                title: Text('显示考试', style: TpTypography.itemTitle(colors)),
                selected: _showExams,
                onTap: () {
                  close();
                  _toggleExamsVisibility();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space2,
                  vertical: 4,
                ),
                child: Divider(height: 1, thickness: 0.5, color: colors.divider),
              ),
              if (onSelect != null)
                DesktopMenuRow(
                  leading: const Icon(TpIcons.checkCircle, size: TpTokens.iconM),
                  title: Text('选择', style: TpTypography.itemTitle(colors)),
                  onTap: () {
                    close();
                    onSelect();
                  },
                ),
              DesktopMenuRow(
                leading: const Icon(TpIcons.add, size: TpTokens.iconM),
                title: Text('添加 Deadline', style: TpTypography.itemTitle(colors)),
                onTap: () {
                  close();
                  unawaited(DeadlineEditorPage.open(context));
                },
              ),
              if (reminders != null)
                DesktopMenuRow(
                  leading:
                      const Icon(TpIcons.checkCircle, size: TpTokens.iconM),
                  title: Text('添加到提醒事项', style: TpTypography.itemTitle(colors)),
                  onTap: canManageReminders
                      ? () {
                          close();
                          unawaited(
                            _enterReminderSelection(service, reminders, visible),
                          );
                        }
                      : null,
                ),
              DesktopMenuRow(
                leading: const Icon(TpIcons.eyeOff, size: TpTokens.iconM),
                title: Text(
                  '查看已忽略 (${service.overrides.hidden.length})',
                  style: TpTypography.itemTitle(colors),
                ),
                onTap: () {
                  close();
                  unawaited(
                    pushAdaptivePage<void>(
                      context,
                      builder: (_) => const HiddenAssignmentsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
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
    final next = !_showAssignments;
    setState(() {
      _showAssignments = next;
      _clearSelection();
    });
    unawaited(
      ServiceProvider.of(context).storageService.setDeadlinesShowAssignments(
            next,
          ),
    );
  }

  void _toggleExamsVisibility() {
    final next = !_showExams;
    setState(() {
      _showExams = next;
      _clearSelection();
    });
    unawaited(
      ServiceProvider.of(context).storageService.setDeadlinesShowExams(next),
    );
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
    final selectionStatus = _loadingReminders
        ? '正在读取提醒事项…'
        : selectedCount == 0
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
        title: selectionStatus,
        largeTitleMode: true,
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
                if (_selected.isNotEmpty)
                  const IosNativeNavigationBarMenuItem(
                    value: 'resetSelected',
                    title: '重置状态',
                    sfSymbol: 'arrow.counterclockwise',
                    destructive: true,
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
        title: Text(selectionStatus),
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

    final uncompleted = sorted
        .where((a) => !service.isCompleted(a) && !a.isExpiredAt(now))
        .toList();
    final completed = sorted
        .where((a) => service.isCompleted(a) && !a.isExpiredAt(now))
        .toList()
      ..sort((a, b) => b.effectiveDue.compareTo(a.effectiveDue));

    final overdue = uncompleted
        .where((a) => a.canBeOverdue && a.effectiveDue.isBefore(now))
        .toList()
      ..sort((a, b) => a.effectiveDue.compareTo(b.effectiveDue));
    final upcoming = uncompleted
        .where((a) => !a.canBeOverdue || !a.effectiveDue.isBefore(now))
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

    final todayShort = DateFormat('M/d').format(now);
    final itemLabel = sorted.any((item) => item is CustomDeadline)
        ? 'ddl'
        : _filteredItemLabel;
    final upcomingTitle = (!_showAssignments && !_showExams)
        ? '即将截止 · 已隐藏全部'
        : (_showAssignments && !_showExams)
            ? '即将截止 · 仅作业'
            : (!_showAssignments && _showExams)
                ? '即将截止 · 仅考试'
                : '即将截止';

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
              TpTokens.space3,
              horizontalPadding,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              // Hero grouped card mirroring TechPie website Deadlines view.
              TpCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        TpTokens.cardPaddingHorizontal,
                        TpTokens.cardPaddingVertical,
                        TpTokens.cardPaddingHorizontal,
                        TpTokens.space3,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    upcomingTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TpTypography.cardTitle(colors),
                                  ),
                                ),
                                const SizedBox(width: TpTokens.space2),
                                TpBadge(
                                  label: '${upcoming.length} 项',
                                  tone: upcoming.isEmpty
                                      ? TpBadgeTone.muted
                                      : TpBadgeTone.brand,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: TpTokens.space2),
                          Text(
                            upcoming.isEmpty ? '今天 $todayShort' : '按紧迫度排序',
                            maxLines: 1,
                            style: TpTypography.cardMeta(colors),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 0.5, color: colors.divider),
                    if (upcoming.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: TpTokens.cardPaddingHorizontal,
                          vertical: TpTokens.space5,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '没有未完成的 $itemLabel',
                              style: TpTypography.itemMeta(colors).copyWith(
                                fontSize: 13.5,
                              ),
                            ),
                            if (!_showAssignments && !_showExams) ...[
                              const SizedBox(height: TpTokens.space2),
                              TextButton(
                                onPressed: () => setState(() {
                                  _showAssignments = true;
                                  _showExams = true;
                                }),
                                child: const Text('恢复显示全部'),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      for (var i = 0; i < upcoming.length; i++)
                        _buildItem(
                          context,
                          service,
                          upcoming[i],
                          isLast: i == upcoming.length - 1,
                        ),
                  ],
                ),
              ),
              if (overdue.isNotEmpty) ...[
                const SizedBox(height: TpTokens.sectionGap),
                TpCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionToggleRow(
                        collapsed: _pastCollapsed,
                        leadingIcon: TpIcons.deadlines,
                        leadingColor: colors.dangerRed,
                        actionColor: colors.dangerRed,
                        label: '已逾期 (${overdue.length})',
                        onTap: () {
                          unawaited(AppHaptics.play(AppHaptics.selection));
                          setState(() => _pastCollapsed = !_pastCollapsed);
                        },
                      ),
                      AnimatedSize(
                        duration: appAnimationDuration(
                          context,
                          TgMotion.medium,
                        ),
                        curve: TgMotion.easeOutQuint,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: _pastCollapsed
                            ? const SizedBox.shrink()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: colors.divider,
                                  ),
                                  for (var i = 0; i < overdue.length; i++)
                                    _buildItem(
                                      context,
                                      service,
                                      overdue[i],
                                      isLast: i == overdue.length - 1,
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
              if (completed.isNotEmpty) ...[
                const SizedBox(height: TpTokens.sectionGap),
                TpCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionToggleRow(
                        collapsed: _completedCollapsed,
                        leadingIcon: TpIcons.checkCircle,
                        leadingColor: colors.successGreen,
                        label: '已完成 (${completed.length})',
                        onTap: () {
                          unawaited(AppHaptics.play(AppHaptics.selection));
                          setState(
                            () => _completedCollapsed = !_completedCollapsed,
                          );
                        },
                      ),
                      AnimatedSize(
                        duration: appAnimationDuration(
                          context,
                          TgMotion.medium,
                        ),
                        curve: TgMotion.easeOutQuint,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        child: _completedCollapsed
                            ? const SizedBox.shrink()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    color: colors.divider,
                                  ),
                                  for (var i = 0; i < completed.length; i++)
                                    _buildItem(
                                      context,
                                      service,
                                      completed[i],
                                      isLast: i == completed.length - 1,
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
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
    Assignment a, {
    required bool isLast,
  }) {
    final key = AssignmentOverrides.keyFor(a);
    final epoch = service.identityEpoch;
    final selectionKey = _selectingReminders ? service.reminderKeyFor(a) : key;
    final selected = _selected.contains(selectionKey);
    final completed = service.isCompleted(a);
    final colors = context.tpColors;

    final row = _AssignmentRow(
      assignment: a,
      completed: completed,
      showCompletionOverride: completed != a.submitted,
      selected: selected,
      selectionMode: _selectionMode && !_loadingReminders,
      showDivider: !isLast,
      onTap: _selectionMode
          ? () => _toggleSelection(selectionKey)
          : a is CustomDeadline
              ? null
              : () => unawaited(_openAssignmentUrl(context, a)),
      onLongPress: _selectionMode
          ? null
          : () => _enterManageSelection(service, epoch, key: key),
      editAction: !_selectionMode && a.kind != DeadlineKind.exam
          ? DeadlineEditButton(assignment: a)
          : null,
      onQuickToggleComplete: isDesktop() && !_selectionMode
          ? () => unawaited(_toggleCompleted(context, service, a))
          : null,
      onQuickHide: isDesktop() && !_selectionMode
          ? () => _onDismiss(context, service, a, key)
          : null,
    );

    final inner = _selectionMode
        ? row
        : SwipeableCard(
            borderRadius: BorderRadius.zero,
            bottomMargin: 0,
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
            child: row,
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

  Future<void> _openAssignmentUrl(BuildContext context, Assignment a) async {
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
    this.actionColor,
  });

  final bool collapsed;
  final IconData leadingIcon;
  final Color leadingColor;
  final String label;
  final VoidCallback onTap;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final trailingColor = actionColor ?? colors.textMuted;
    return InkWell(
      onTap: onTap,
      hoverColor: colors.textPrimary.withValues(
        alpha: colors.isDark ? 0.06 : 0.04,
      ),
      splashColor: colors.brandSoft,
      highlightColor: colors.surfacePressed.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TpTokens.cardPaddingHorizontal,
          vertical: TpTokens.space3,
        ),
        child: Row(
          children: [
            Icon(
              leadingIcon,
              size: TpTokens.iconS,
              color: leadingColor,
            ),
            const SizedBox(width: TpTokens.space2),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTypography.cardTitle(colors).copyWith(fontSize: 14),
              ),
            ),
            const SizedBox(width: TpTokens.space2),
            Text(
              collapsed ? '展开' : '收起',
              style: TpTypography.cardMeta(colors).copyWith(
                color: trailingColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: collapsed ? 0.0 : 0.25,
              duration: appAnimationDuration(context, TgMotion.short),
              curve: TgMotion.easeOutQuint,
              child: Icon(
                Icons.chevron_right,
                size: TpTokens.iconS + 2,
                color: trailingColor,
              ),
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
                            ? AdaptiveActivityIndicator(
                                size: 16,
                                strokeWidth: 2,
                                color: colors.dangerRed,
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

String _formatPlatformLabel(String platform) {
  return switch (platform.trim().toLowerCase()) {
    'blackboard' => 'Blackboard',
    'gradescope' => 'Gradescope',
    'hydro' => 'Hydro',
    'elearning' => 'eLearning',
    'egate' => 'eGate',
    'exam' || 'custom' || '' => '',
    final other => other[0].toUpperCase() + other.substring(1),
  };
}

String _formatExamDueText(ExamAssignment exam, String startShort) {
  final end = exam.lateDue;
  if (end == null || !end.isAfter(exam.due)) return startShort;
  final sameDay = exam.due.year == end.year &&
      exam.due.month == end.month &&
      exam.due.day == end.day;
  final endText = sameDay
      ? DateFormat('HH:mm').format(end)
      : DateFormat('MM/dd HH:mm').format(end);
  return '$startShort–$endText';
}

String _formatRemainingLabel(
  DateTime due,
  DateTime now, {
  bool late = false,
}) {
  final diff = due.difference(now);
  final prefix = late ? '迟交剩余 ' : '剩余 ';
  if (diff.isNegative || diff.inSeconds <= 0) {
    return '已逾期';
  }
  final days = diff.inDays;
  final remHours = diff.inHours % 24;
  if (days >= 3) {
    return '$prefix$days 天';
  }
  if (days >= 1) {
    return remHours > 0 ? '$prefix$days 天 $remHours 小时' : '$prefix$days 天';
  }
  final hours = diff.inHours.toString().padLeft(2, '0');
  final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
  return '$prefix$hours:$minutes:$seconds';
}

String _formatOverdueLabel(DateTime due, DateTime now) {
  final diff = now.difference(due);
  if (diff.inDays >= 1) {
    return '已逾期 ${diff.inDays} 天';
  }
  if (diff.inHours >= 1) {
    return '已逾期 ${diff.inHours} 小时';
  }
  return '已逾期';
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

class _AssignmentRow extends StatefulWidget {
  final Assignment assignment;
  final bool completed;
  final bool showCompletionOverride;
  final bool selected;
  final bool selectionMode;
  final bool showDivider;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? editAction;
  final VoidCallback? onQuickToggleComplete;
  final VoidCallback? onQuickHide;

  const _AssignmentRow({
    required this.assignment,
    required this.completed,
    required this.showCompletionOverride,
    required this.selected,
    required this.selectionMode,
    required this.showDivider,
    required this.onTap,
    required this.onLongPress,
    this.editAction,
    this.onQuickToggleComplete,
    this.onQuickHide,
  });

  @override
  State<_AssignmentRow> createState() => _AssignmentRowState();
}

class _AssignmentRowState extends State<_AssignmentRow> {
  // End padding for the countdown and more button on touch layouts.
  static const double _editRowEndPadding = TpTokens.space2;
  static const double _selectionIconSize = TpTokens.iconM - 1;
  static const double _selectionIconGap = 10;
  static const double _desktopQuickActionSize = 16;
  static const double _desktopQuickActionsGap = 6;
  static const _desktopQuickActionConstraints = BoxConstraints.tightFor(
    width: _desktopQuickActionSize,
    height: _desktopQuickActionSize,
  );

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    final completed = widget.completed;
    final selected = widget.selected;
    final colors = context.tpColors;
    final now = DateTime.now();
    final exam = assignment is ExamAssignment ? assignment : null;
    final isExamInProgress = exam != null && exam.isInProgressAt(now);
    final lateDue = assignment.effectiveLateDue;
    final finalDue = assignment.effectiveDue;
    final isPast = assignment.canBeOverdue && finalDue.isBefore(now);
    final isLateWindow = !completed &&
        lateDue != null &&
        assignment.due.isBefore(now) &&
        !isPast;

    final displayDue = isLateWindow ? lateDue : assignment.due;
    final hoursLeft = displayDue.difference(now).inHours;
    final isCalm = !completed &&
        !isPast &&
        !isLateWindow &&
        !isExamInProgress &&
        hoursLeft >= 72;
    final dueShort = DateFormat('MM/dd HH:mm').format(displayDue);

    final subtitle = switch (assignment) {
      ExamAssignment(:final location) => location.trim(),
      CustomDeadline(:final course, :final location) => [
          if (course.isNotEmpty) course,
          if (location.isNotEmpty) location,
        ].join(' · '),
      _ => assignment.course.trim(),
    };
    final notes = assignment.notes.trim();

    final Color urgencyColor = () {
      if (completed) return colors.successGreen;
      if (isPast || isLateWindow || isExamInProgress) return colors.dangerRed;
      if (hoursLeft < 24) return colors.dangerRed;
      if (hoursLeft < 72) return colors.warningAmber;
      return colors.textPrimary.withValues(alpha: colors.isDark ? 0.30 : 0.28);
    }();
    final Color countdownColor = isCalm ? colors.textMuted : urgencyColor;

    final progress = isExamInProgress
        ? 1.0
        : _urgencyProgress(
            due: displayDue,
            now: now,
            completed: completed,
            isPast: isPast,
            isLateWindow: isLateWindow,
          );

    final completedStatusLabel = (completed && assignment is! CustomDeadline)
        ? (assignment.status == 'Graded' ? 'Graded' : 'Submitted')
        : null;

    final platformLabel = _formatPlatformLabel(assignment.platform);
    final metaLeft = switch (assignment) {
      CustomDeadline() => subtitle,
      ExamAssignment() => [
          if (subtitle.isNotEmpty) subtitle,
          if (assignment.course.isNotEmpty &&
              assignment.course.trim() != assignment.title.trim())
            assignment.course.trim(),
        ].join(' · '),
      _ => [
          if (subtitle.isNotEmpty) subtitle,
          if (platformLabel.isNotEmpty) platformLabel,
          if (lateDue != null && !isLateWindow && !completed) '支持迟交',
        ].join(' · '),
    };

    final dueText = exam != null
        ? _formatExamDueText(exam, dueShort)
        : isLateWindow
            ? '迟交截止 $dueShort'
            : (isPast && !completed ? '原截止 $dueShort' : '$dueShort 截止');

    final showQuickActions =
        widget.onQuickToggleComplete != null || widget.onQuickHide != null;
    final desktop = isDesktop();
    final canEdit = assignment.kind != DeadlineKind.exam;
    final editButtonHeight = desktop
        ? DeadlineEditButton.desktopSize
        : kMinInteractiveDimension;
    final desktopActionsWidth = (canEdit ? DeadlineEditButton.desktopSize : 0) +
        2 * _desktopQuickActionSize +
        _desktopQuickActionsGap;
    final selectionIconWidth =
        widget.selectionMode ? _selectionIconSize + _selectionIconGap : 0.0;
    // Keep wrapped titles the same width when desktop actions are hidden.
    final titleEndGap = desktop && !showQuickActions
        ? TpTokens.space3 + desktopActionsWidth - selectionIconWidth
        : TpTokens.space3;
    final headerEndPadding = !desktop && widget.editAction != null
        ? _editRowEndPadding
        : TpTokens.cardPaddingHorizontal;

    final Widget countdownWidget = completed
        ? Row(
            key: const ValueKey('completed'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                TpIcons.checkCircle,
                size: 13,
                color: colors.successGreen,
              ),
              const SizedBox(width: 4),
              Text(
                '已完成',
                style: TpTypography.badge(colors.successGreen),
              ),
            ],
          )
        : (isExamInProgress
            ? Text(
                '考试中',
                key: const ValueKey('in_progress'),
                maxLines: 1,
                style: TpTypography.badge(colors.dangerRed),
              )
            : (isPast
                ? Text(
                    _formatOverdueLabel(finalDue, now),
                    key: const ValueKey('overdue'),
                    maxLines: 1,
                    style: TpTypography.badge(colors.dangerRed),
                  )
                : (isLateWindow
                    ? Text(
                        _formatRemainingLabel(lateDue, now, late: true),
                        key: const ValueKey('late_remain'),
                        maxLines: 1,
                        style: TpTypography.badge(colors.dangerRed),
                      )
                    : Text(
                        _formatRemainingLabel(assignment.due, now),
                        key: const ValueKey('remain'),
                        maxLines: 1,
                        style: TpTypography.badge(countdownColor).copyWith(
                          fontSize: 12,
                          fontWeight:
                              isCalm ? FontWeight.w500 : FontWeight.w600,
                        ),
                      ))));

    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Material(
        color: selected ? colors.opaqueBrandContainer : colors.surface,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          hoverColor: colors.textPrimary.withValues(
            alpha: colors.isDark ? 0.06 : 0.04,
          ),
          splashColor: colors.brandSoft,
          highlightColor: colors.surfacePressed.withValues(alpha: 0.35),
          child: DecoratedBox(
            decoration: selected
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(color: colors.brand, width: 3),
                    ),
                  )
                : const BoxDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    TpTokens.cardPaddingHorizontal,
                    11,
                    0,
                    11,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: Title + Urgency Countdown + subtle desktop quick actions.
                      // Exactly ONE flex child (Expanded on the left) guarantees
                      // countdown & actions are always pinned flush to the right edge.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: canEdit ? editButtonHeight : _selectionIconSize,
                          ),
                          if (widget.selectionMode) ...[
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: _selectionIconSize,
                              color:
                                  selected ? colors.brandInk : colors.textMuted,
                            ),
                            const SizedBox(width: _selectionIconGap),
                          ],
                          Expanded(
                            child: Row(
                              children: [
                                if (assignment.kind == DeadlineKind.exam) ...[
                                  const _CompactKindTag(
                                    label: '考试',
                                    tone: TpBadgeTone.danger,
                                  ),
                                  const SizedBox(width: 6),
                                ] else if (assignment.kind ==
                                    DeadlineKind.custom) ...[
                                  const _CompactKindTag(
                                    label: '自定义',
                                    tone: TpBadgeTone.info,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(
                                    assignment.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TpTypography.itemTitle(colors).copyWith(
                                      fontSize: 14.5,
                                      height: 1.3,
                                      color: completed
                                          ? colors.textSecondary
                                          : colors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (widget.showCompletionOverride) ...[
                                  const SizedBox(width: 5),
                                  Tooltip(
                                    message: '本地标记',
                                    child: Icon(
                                      TpIcons.edit,
                                      size: 12,
                                      color: colors.brandInk,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: titleEndGap),
                          AnimatedSwitcher(
                            duration: appAnimationDuration(
                              context,
                              const Duration(milliseconds: 240),
                            ),
                            switchInCurve: appAnimationCurve(
                              Curves.easeOutCubic,
                              iosCurve: Curves.easeOut,
                            ),
                            switchOutCurve: appAnimationCurve(
                              Curves.easeInCubic,
                              iosCurve: Curves.easeIn,
                            ),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                            child: countdownWidget,
                          ),
                          if (widget.editAction case final action?) action,
                          if (showQuickActions) ...[
                            const SizedBox(width: _desktopQuickActionsGap),
                            AnimatedOpacity(
                              opacity: _hovered ? 1.0 : 0.42,
                              duration: appAnimationDuration(
                                context,
                                const Duration(milliseconds: 140),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.onQuickToggleComplete != null)
                                    IconButton(
                                      icon: Icon(
                                        completed
                                            ? TpIcons.close
                                            : TpIcons.checkCircle,
                                        size: 15,
                                      ),
                                      color: completed
                                          ? colors.textMuted
                                          : colors.successGreen,
                                      tooltip: completed ? '取消完成' : '标记完成',
                                      visualDensity: VisualDensity.standard,
                                      style: IconButton.styleFrom(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      constraints: _desktopQuickActionConstraints,
                                      padding: EdgeInsets.zero,
                                      onPressed: widget.onQuickToggleComplete,
                                    ),
                                  if (widget.onQuickHide != null)
                                    IconButton(
                                      icon: const Icon(
                                        TpIcons.delete,
                                        size: 15,
                                      ),
                                      color: colors.textMuted,
                                      hoverColor: colors.dangerRed
                                          .withValues(alpha: 0.10),
                                      tooltip: '忽略',
                                      visualDensity: VisualDensity.standard,
                                      style: IconButton.styleFrom(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      constraints: _desktopQuickActionConstraints,
                                      padding: EdgeInsets.zero,
                                      onPressed: widget.onQuickHide,
                                    ),
                                ],
                              ),
                            ),
                          ],
                          SizedBox(width: headerEndPadding),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: TpTokens.cardPaddingHorizontal,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Row 2: Single subtle metadata line (course · platform | due time).
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    metaLeft.isNotEmpty
                                        ? metaLeft
                                        : (assignment is CustomDeadline
                                            ? '自定义截止事项'
                                            : '截止事项'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TpTypography.itemMeta(colors).copyWith(
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: TpTokens.space2),
                                if (completedStatusLabel != null) ...[
                                  Text(
                                    completedStatusLabel,
                                    maxLines: 1,
                                    style: TpTypography.itemMeta(colors).copyWith(
                                      fontSize: 11.5,
                                      color: colors.successGreen,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    ' · $dueShort',
                                    maxLines: 1,
                                    style: TpTypography.itemMeta(colors).copyWith(
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ] else
                                  Text(
                                    dueText,
                                    maxLines: 1,
                                    style: TpTypography.itemMeta(colors).copyWith(
                                      fontSize: 11.5,
                                      color: !completed && (isPast || isLateWindow)
                                          ? colors.dangerRed
                                          : colors.textMuted,
                                      fontWeight:
                                          !completed && (isPast || isLateWindow)
                                              ? FontWeight.w500
                                              : FontWeight.w400,
                                    ),
                                  ),
                              ],
                            ),
                            if (notes.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                notes,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TpTypography.itemMeta(colors).copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: TpTokens.space2),
                            // Row 3: Thin rounded urgency progress bar.
                            TpProgressBar(
                              progress: progress,
                              color: completed
                                  ? urgencyColor.withValues(alpha: 0.45)
                                  : urgencyColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.showDivider)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.cardPaddingHorizontal,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: colors.divider,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactKindTag extends StatelessWidget {
  const _CompactKindTag({
    required this.label,
    required this.tone,
  });

  final String label;
  final TpBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final alpha = colors.isDark ? 0.18 : 0.11;
    final (fg, bg) = switch (tone) {
      TpBadgeTone.danger => (
          colors.dangerRed,
          colors.dangerRed.withValues(alpha: alpha),
        ),
      TpBadgeTone.info => (
          colors.infoBlue,
          colors.infoBlue.withValues(alpha: alpha),
        ),
      _ => (colors.brandInk, colors.brandSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TpTokens.radiusXs),
      ),
      child: Text(
        label,
        style: TpTypography.badge(fg).copyWith(fontSize: 10.5),
      ),
    );
  }
}
