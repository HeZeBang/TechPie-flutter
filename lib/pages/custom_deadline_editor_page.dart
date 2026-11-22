import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/assignment.dart';
import '../services/assignment_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_date_picker.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_area.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/schedule_picker_sheet.dart';

class CustomDeadlineEditorPage extends StatefulWidget {
  const CustomDeadlineEditorPage._({
    required this.service,
    required this.owner,
    this.deadline,
  });

  final AssignmentService service;
  final String? owner;
  final CustomDeadline? deadline;

  static Future<void> open(BuildContext context, {CustomDeadline? deadline}) async {
    final service = ServiceProvider.of(context).assignmentService;
    final owner = service.customDeadlineOwner;
    await pushAdaptivePage<void>(
      context,
      builder: (_) => CustomDeadlineEditorPage._(
        service: service,
        owner: owner,
        deadline: deadline,
      ),
    );
  }

  @override
  State<CustomDeadlineEditorPage> createState() => _CustomDeadlineEditorPageState();
}

class _CustomDeadlineEditorPageState extends State<CustomDeadlineEditorPage> {
  late final _title = TextEditingController(text: widget.deadline?.title);
  late final _course = TextEditingController(text: widget.deadline?.course);
  late final _notes = TextEditingController(text: widget.deadline?.notes);
  late DateTime? _date = widget.deadline?.due.toLocal();
  late TimeOfDay? _time = _date == null ? null : TimeOfDay.fromDateTime(_date!);
  bool _busy = false;

  String? get _id => widget.deadline?.id;

  @override
  void dispose() {
    _title.dispose();
    _course.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final date = await showAdaptiveDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      title: '截止日期',
    );
    if (mounted && date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showScheduleTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 23, minute: 59),
      title: '截止时间',
    );
    if (mounted && time != null) setState(() => _time = time);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final date = _date;
    final time = _time;
    if (title.isEmpty || date == null || time == null) {
      showAdaptiveFeedback(
        context: context,
        message: title.isEmpty ? '请输入标题' : '请选择截止日期和时间',
        style: AdaptiveFeedbackStyle.error,
      );
      return;
    }
    await _runAction(
      () => widget.service.saveCustomDeadline(
        owner: widget.owner,
        id: _id,
        title: title,
        course: _course.text,
        notes: _notes.text,
        due: DateTime(date.year, date.month, date.day, time.hour, time.minute),
      ),
      errorMessage: '保存失败，请重试',
      close: true,
    );
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String errorMessage,
    bool close = false,
  }) async {
    if (_busy || widget.owner != widget.service.customDeadlineOwner) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      await action();
      if (close && mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: errorMessage,
        style: AdaptiveFeedbackStyle.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _id == null ? '添加 Deadline' : '编辑 Deadline';
    final ios = isIos();
    final extendBody = !ios && !usesLegacyIosChrome();
    final topInset =
        extendBody ? adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top : 0.0;

    return Scaffold(
      extendBodyBehindAppBar: extendBody,
      appBar: ios
          ? IosNativeNavigationBar(
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
            )
          : BlurredAppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final id = _id;
          final current = id == null ? null : widget.service.findCustomDeadline(id);
          if (widget.owner != widget.service.customDeadlineOwner ||
              (id != null && current == null)) {
            return const Center(child: Text('此 Deadline 已无法访问'));
          }
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              topInset + 12,
              16,
              AppShellMetrics.bottomContentPaddingOf(context),
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _buildForm(current),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(CustomDeadline? current) {
    final date = _date;
    final time = _time;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AdaptiveTextFieldGroup(
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
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AdaptiveTextArea(
                  controller: _notes,
                  placeholder: '备注（可选）',
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 2,
                  maxLines: 4,
                  enabled: !_busy,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card.outlined(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('截止日期'),
                subtitle: Text(date == null ? '未选择' : DateFormat('yyyy-MM-dd').format(date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _pickDate,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('截止时间'),
                subtitle: Text(time == null ? '未选择' : _formatTime(time)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _pickTime,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdaptiveButton(
          onPressed: _busy ? null : _save,
          icon: Icons.check_rounded,
          sfSymbol: 'checkmark',
          label: '保存',
          role: AdaptiveButtonRole.prominent,
          loading: _busy,
        ),
        if (current != null) ...[
          const SizedBox(height: 8),
          AdaptiveButton(
            onPressed: _busy
                ? null
                : () => unawaited(
                      _runAction(
                        () => widget.service.toggleCompleted(current),
                        errorMessage: '更新完成状态失败，请重试',
                      ),
                    ),
            icon: current.completed ? Icons.undo : Icons.check_circle_outline,
            sfSymbol: current.completed ? 'arrow.uturn.backward' : 'checkmark.circle',
            label: current.completed ? '取消完成' : '标记完成',
            role: AdaptiveButtonRole.plain,
          ),
          IgnorePointer(
            ignoring: _busy,
            child: AdaptiveConfirmationButton(
              label: '删除',
              confirmTitle: '删除此 Deadline？',
              confirmLabel: '删除',
              icon: Icons.delete_outline,
              sfSymbol: 'trash',
              destructive: true,
              onConfirmed: () => unawaited(
                _runAction(
                  () => widget.service.deleteCustomDeadline(
                    current.id,
                    owner: widget.owner,
                  ),
                  errorMessage: '删除失败，请重试',
                  close: true,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
