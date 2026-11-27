import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/assignment.dart';
import '../services/assignment_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_date_picker.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_area.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/schedule_picker_sheet.dart';

class DeadlineEditorPage extends StatefulWidget {
  const DeadlineEditorPage._({
    required this.service,
    required this.owner,
    required this.epoch,
    this.deadline,
  });

  final AssignmentService service;
  final String? owner;
  final int epoch;
  final Assignment? deadline;

  static Future<void> open(BuildContext context, {Assignment? deadline}) async {
    final service = ServiceProvider.of(context).assignmentService;
    final current = switch (deadline) {
      CustomDeadline(:final id) => service.findCustomDeadline(id),
      Assignment(kind: DeadlineKind.assignment) => service.findImportedDeadline(deadline),
      _ => null,
    };
    if (deadline != null && current == null) return;
    final editor = DeadlineEditorPage._(
      service: service,
      owner: service.customDeadlineOwner,
      epoch: service.identityEpoch,
      deadline: current,
    );
    await pushAdaptivePage<void>(
      context,
      builder: (_) => editor,
    );
  }

  @override
  State<DeadlineEditorPage> createState() => _DeadlineEditorPageState();
}

class _DeadlineEditorPageState extends State<DeadlineEditorPage> {
  late final _title = TextEditingController(text: widget.deadline?.title);
  late final _course = TextEditingController(text: widget.deadline?.course);
  late final _location = TextEditingController(text: _custom?.location);
  late final _notes = TextEditingController(text: widget.deadline?.notes);
  late final _textChanges = Listenable.merge([_title, _course, _location, _notes]);
  late Assignment? _savedDeadline = widget.deadline;
  late DateTime? _date = _savedDeadline?.due.toLocal();
  late TimeOfDay? _time = _date == null ? null : TimeOfDay.fromDateTime(_date!);
  late DateTime? _lateDate = _savedDeadline?.effectiveLateDue?.toLocal();
  late TimeOfDay? _lateTime = _lateDate == null ? null : TimeOfDay.fromDateTime(_lateDate!);
  bool _busy = false;
  bool _confirmingExit = false;

  String? get _id => widget.deadline?.id;
  CustomDeadline? get _custom => switch (widget.deadline) {
        final CustomDeadline deadline => deadline,
        _ => null,
      };
  Assignment? get _imported => _custom == null ? _savedDeadline : null;
  String get _initialNotes => widget.deadline?.notes.trim() ?? '';
  bool get _workspaceChanged => _imported != null
      ? widget.epoch != widget.service.identityEpoch
      : widget.owner != widget.service.customDeadlineOwner;
  bool get _hasUnsavedSourceChanges =>
      _title.text.trim() != (_savedDeadline?.title.trim() ?? '') ||
      _course.text.trim() != (_savedDeadline?.course.trim() ?? '') ||
      _deadlineChanged(_date, _time, _savedDeadline?.due.toLocal()) ||
      _deadlineChanged(_lateDate, _lateTime, _savedDeadline?.effectiveLateDue?.toLocal());
  bool get _hasUnsavedChanges =>
      _hasUnsavedSourceChanges ||
      _location.text.trim() != (_custom?.location.trim() ?? '') ||
      _notes.text.trim() != _initialNotes;

  @override
  void dispose() {
    _title.dispose();
    _course.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isLate}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final date = await showAdaptiveDatePicker(
      context: context,
      initialDate: (isLate ? _lateDate ?? _date : _date) ?? DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      title: isLate ? '迟交截止日期' : '截止日期',
    );
    if (mounted && date != null) {
      setState(() {
        if (isLate) {
          _lateDate = date;
        } else {
          _date = date;
        }
      });
    }
  }

  Future<void> _pickTime({required bool isLate}) async {
    final time = await showScheduleTimePicker(
      context: context,
      initialTime: (isLate ? _lateTime : _time) ?? const TimeOfDay(hour: 23, minute: 59),
      title: isLate ? '迟交截止时间' : '截止时间',
    );
    if (mounted && time != null) {
      setState(() {
        if (isLate) {
          _lateTime = time;
        } else {
          _time = time;
        }
      });
    }
  }

  static DateTime _dateTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  static bool _deadlineChanged(DateTime? date, TimeOfDay? time, DateTime? initial) =>
      !DateUtils.isSameDay(date, initial) ||
      time != (initial == null ? null : TimeOfDay.fromDateTime(initial));

  static DateTime? _changedTime(DateTime value, DateTime? initial) {
    final local = initial?.toLocal();
    if (local == null) return value;
    return value == _dateTime(local, TimeOfDay.fromDateTime(local)) ? null : value;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final date = _date;
    final time = _time;
    final imported = _imported;
    final lateDate = _lateDate;
    final lateTime = _lateTime;
    if (title.isEmpty || date == null || time == null) {
      _showError(title.isEmpty ? '请输入标题' : '请选择截止日期和时间');
      return;
    }
    if ((lateDate == null) != (lateTime == null)) {
      _showError('请选择迟交截止日期和时间');
      return;
    }
    final due = _dateTime(date, time);
    final course = _course.text.trim();
    final notes = _notes.text.trim();
    if (imported != null) {
      await _runAction(
        () => widget.service.saveImportedDeadlineEdit(
          imported,
          epoch: widget.epoch,
          title: title == imported.title.trim() ? null : title,
          course: course == imported.course.trim() ? null : course,
          notes: notes == _initialNotes ? null : notes,
          due: _changedTime(due, imported.due),
          lateDue: lateDate == null || lateTime == null
              ? null
              : _changedTime(_dateTime(lateDate, lateTime), imported.effectiveLateDue),
        ),
        errorMessage: '保存失败，请重试',
      );
      return;
    }
    final originalDue = _custom?.due;
    await _runAction(
      () => widget.service.saveCustomDeadline(
        owner: widget.owner,
        id: _id,
        title: title,
        course: course,
        location: _location.text,
        notes: notes,
        due: _changedTime(due, originalDue) ?? originalDue ?? due,
      ),
      errorMessage: '保存失败，请重试',
    );
  }

  Future<void> _confirmExit() async {
    if (_busy || _confirmingExit || !_hasUnsavedChanges) return;
    _confirmingExit = true;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      final discard = await showAdaptiveAlertDialog<bool>(
        context: context,
        title: '放弃未保存的修改？',
        message: '',
        centerContent: true,
        actions: const [
          AdaptiveAlertAction(label: '继续编辑', value: false, isDefault: true),
          AdaptiveAlertAction(label: '放弃并退出', value: true, isDestructive: true),
        ],
      );
      if (discard == true && mounted && ModalRoute.isCurrentOf(context) == true) {
        Navigator.pop(context);
      }
    } finally {
      _confirmingExit = false;
    }
  }

  Future<void> _restoreSource(Assignment imported) => _runAction(
        () async {
          await widget.service.restoreImportedDeadline(imported, epoch: widget.epoch);
          if (!mounted || _workspaceChanged) return;
          final restored = widget.service.findImportedDeadline(imported);
          if (restored == null) return;
          final due = restored.due.toLocal();
          final lateDue = restored.effectiveLateDue?.toLocal();
          setState(() {
            _savedDeadline = restored;
            _title.text = restored.title;
            _course.text = restored.course;
            _date = due;
            _time = TimeOfDay.fromDateTime(due);
            _lateDate = lateDue;
            _lateTime = lateDue == null ? null : TimeOfDay.fromDateTime(lateDue);
          });
        },
        errorMessage: '恢复失败，请重试',
        close: false,
      );

  void _showError(String message) => showAdaptiveFeedback(
        context: context,
        message: message,
        style: AdaptiveFeedbackStyle.error,
      );

  Future<void> _runAction(
    Future<void> Function() action, {
    required String errorMessage,
    bool close = true,
  }) async {
    if (_busy || _confirmingExit || _workspaceChanged) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      await action();
      if (close && mounted && ModalRoute.isCurrentOf(context) == true) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      _showError(
        error is ArgumentError && error.message is String ? error.message as String : errorMessage,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final title = _id == null ? '添加 Deadline' : '编辑 Deadline';
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space3,
    );

    final page = Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar: AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: title,
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '返回',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') unawaited(maybePopAdaptivePage<void>(context));
          },
        ),
        material: () => BlurredAppBar(title: Text(title)),
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final imported = _imported;
          final current = switch (widget.deadline) {
            CustomDeadline(:final id) => widget.service.findCustomDeadline(id),
            final Assignment assignment => widget.service.findImportedDeadline(assignment),
            null => null,
          };
          if (_workspaceChanged || (widget.deadline != null && current == null)) {
            return const Center(child: Text('此 Deadline 已无法访问'));
          }
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              TpTokens.pageHorizontalPadding,
              topInset,
              TpTokens.pageHorizontalPadding,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              TpPageBody(
                child: _buildForm(
                  current is CustomDeadline ? current : null,
                  imported: imported,
                ),
              ),
            ],
          );
        },
      ),
    );
    return ListenableBuilder(
      listenable: _textChanges,
      child: page,
      builder: (context, child) {
        final hasUnsavedChanges = _hasUnsavedChanges;
        return PopScope<void>(
          canPop: !_busy && !hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_confirmExit());
          },
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              if (isIos() && hasUnsavedChanges && !_busy) _buildBackSwipe(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBackSwipe() {
    // PopScope disables CupertinoPageRoute's interactive swipe while dirty.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final padding = MediaQuery.paddingOf(context);
    final leadingInset = isRtl ? padding.right : padding.left;
    final edgeWidth = leadingInset < 20 ? 20.0 : leadingInset;
    return PositionedDirectional(
      start: 0,
      top: 0,
      bottom: 0,
      width: edgeWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onHorizontalDragEnd: (details) {
          final velocity = (details.primaryVelocity ?? 0) * (isRtl ? -1 : 1);
          final distance = isRtl ? -details.localPosition.dx : details.localPosition.dx - edgeWidth;
          if (velocity > 0 || (velocity == 0 && distance >= 48)) {
            unawaited(maybePopAdaptivePage<void>(context));
          }
        },
      ),
    );
  }

  Widget _buildForm(CustomDeadline? current, {required Assignment? imported}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpCard(
          title: '事项信息',
          padding: const EdgeInsets.fromLTRB(
            TpTokens.cardPaddingHorizontal,
            TpTokens.space1,
            TpTokens.cardPaddingHorizontal,
            TpTokens.space4,
          ),
          child: Column(
            children: [
              AdaptiveTextFieldGroup(
                embedded: true,
                items: [
                  AdaptiveTextFieldGroupItem(
                    controller: _title,
                    placeholder: '标题',
                    enabled: !_busy,
                  ),
                  AdaptiveTextFieldGroupItem(
                    controller: _course,
                    placeholder: '课程名（可选）',
                    enabled: !_busy,
                  ),
                  if (imported == null)
                    AdaptiveTextFieldGroupItem(
                      controller: _location,
                      placeholder: '地点（可选）',
                      enabled: !_busy,
                      textInputAction: TextInputAction.done,
                    ),
                ],
              ),
              const SizedBox(height: TpTokens.space3),
              AdaptiveTextArea(
                controller: _notes,
                placeholder: '备注（可选）',
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 2,
                maxLines: 4,
                enabled: !_busy,
                embedded: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: TpTokens.sectionGap),
        _buildDeadlineFields(isLate: false),
        if (imported?.supportsLateDue ?? false) ...[
          const SizedBox(height: TpTokens.sectionGap),
          _buildDeadlineFields(isLate: true),
        ],
        const SizedBox(height: TpTokens.space4),
        AdaptiveButton(
          onPressed: _busy ? null : _save,
          icon: TpIcons.check,
          sfSymbol: 'checkmark',
          label: '保存',
          role: AdaptiveButtonRole.prominent,
          loading: _busy,
          height: 46,
        ),
        if (imported != null)
          ListenableBuilder(
            listenable: _textChanges,
            builder: (context, _) {
              if (!_hasUnsavedSourceChanges &&
                  !widget.service.hasImportedDeadlineSourceEdit(imported)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: TpTokens.space2),
                child: AdaptiveButton(
                  onPressed: _busy ? null : () => unawaited(_restoreSource(imported)),
                  icon: TpIcons.refresh,
                  sfSymbol: 'arrow.uturn.backward',
                  label: '恢复来源信息',
                  role: AdaptiveButtonRole.plain,
                ),
              );
            },
          ),
        if (current != null) ...[
          const SizedBox(height: TpTokens.space2),
          IgnorePointer(
            ignoring: _busy,
            child: AdaptiveConfirmationButton(
              label: '删除',
              confirmTitle: '删除此 Deadline？',
              confirmLabel: '删除',
              icon: TpIcons.delete,
              sfSymbol: 'trash',
              destructive: true,
              onConfirmed: () => unawaited(
                _runAction(
                  () => widget.service.deleteCustomDeadline(
                    current.id,
                    owner: widget.owner,
                  ),
                  errorMessage: '删除失败，请重试',
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDeadlineFields({required bool isLate}) {
    final colors = context.tpColors;
    final date = isLate ? _lateDate : _date;
    final time = isLate ? _lateTime : _time;
    return TpCard(
      child: Column(
        children: [
          TpListRow(
            icon: TpIcons.calendar,
            iconColor: colors.brandInk,
            title: isLate ? '迟交截止日期' : '截止日期',
            subtitle: date == null ? '未选择' : DateFormat('yyyy-MM-dd').format(date),
            showChevron: true,
            showDivider: true,
            onTap: _busy ? null : () => _pickDate(isLate: isLate),
          ),
          TpListRow(
            icon: TpIcons.deadlines,
            iconColor: colors.infoBlue,
            title: isLate ? '迟交截止时间' : '截止时间',
            subtitle: time == null ? '未选择' : _formatTime(time),
            showChevron: true,
            onTap: _busy ? null : () => _pickTime(isLate: isLate),
          ),
        ],
      ),
    );
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class DeadlineEditButton extends StatelessWidget {
  const DeadlineEditButton({super.key, required this.assignment});

  static const double _editMenuWidth = 64;
  static const double _editMenuItemHeight = 40;

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final service = ServiceProvider.of(context).assignmentService;
    final epoch = service.identityEpoch;
    void openEditor() {
      if (context.mounted && epoch == service.identityEpoch) {
        unawaited(DeadlineEditorPage.open(context, deadline: assignment));
      }
    }

    if (isDesktop()) {
      return IconButton(
        icon: const Icon(TpIcons.edit, size: 15),
        tooltip: '编辑 Deadline',
        color: context.tpColors.textMuted,
        visualDensity: VisualDensity.compact,
        onPressed: openEditor,
      );
    }
    return PopupMenuButton<String>(
      key: ValueKey((epoch, assignment.platform, assignment.id)),
      icon: const Icon(TpIcons.more, size: 18),
      tooltip: 'Deadline 操作',
      constraints: const BoxConstraints.tightFor(width: _editMenuWidth),
      menuPadding: EdgeInsets.zero,
      onSelected: (_) => openEditor(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'edit',
          height: _editMenuItemHeight,
          padding: EdgeInsets.symmetric(horizontal: TpTokens.space2),
          child: Center(child: Text('编辑', textAlign: TextAlign.center)),
        ),
      ],
    );
  }
}
