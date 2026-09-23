import 'dart:async';

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_date_picker.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_multi_select.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/adaptive_time_picker.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

/// Add or edit one hand-entered session — a tutorial, a recitation, a lab.
///
/// Passing [course] edits it in place, keeping its id so a save replaces it.
class CustomCourseEditorPage extends StatefulWidget {
  final CustomCourse? course;

  const CustomCourseEditorPage({super.key, this.course});

  @override
  State<CustomCourseEditorPage> createState() => _CustomCourseEditorPageState();
}

class _CustomCourseEditorPageState extends State<CustomCourseEditorPage> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _teachers = TextEditingController();

  late ScheduleService _schedule;
  List<Period> _periods = const [];
  late int _totalWeeks;
  DateTime? _termBegin;

  bool _initialized = false;
  bool _saving = false;

  /// A difference between these two is a move the service has to honour.
  String? _semesterId;
  String? _originSemesterId;

  int _scheduleMode = 0; // 0 = 按周重复, 1 = 只上一次
  final Set<int> _weeks = {};
  bool _usesDefaultWeeks = true;
  DateTime? _date;

  int _timeMode = 0; // 0 = 按节次, 1 = 自定义时间
  final Set<int> _weekdays = {};
  int _startPeriod = 1;
  int _endPeriod = 1;
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 8, minute: 45);

  String? _id;
  CourseColor _color = CourseColor.primary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _schedule = ServiceProvider.of(context).scheduleService;
    _semesterId = _schedule.selectedSemesterId;
    _loadSemesterContext(_semesterId);

    final existing = widget.course;
    if (existing == null) {
      _weeks.addAll(_allWeeks.where((week) => week <= 16));
      _weekdays.add(DateTime.now().weekday);
      _startPeriod = 1;
      _endPeriod = 1;
      return;
    }

    _id = existing.id;
    _originSemesterId = existing.semesterId.isEmpty ? _semesterId : existing.semesterId;
    _color = existing.color;
    _name.text = existing.name;
    _location.text = existing.location;
    _teachers.text = existing.teachers;
    _scheduleMode = existing.isOneOff ? 1 : 0;
    _weeks
      ..clear()
      ..addAll(existing.weeks);
    _usesDefaultWeeks = false;
    _date = existing.date;
    _weekdays
      ..clear()
      ..addAll(existing.effectiveWeekdays);
    switch (existing.time) {
      case PeriodCourseTime(:final startPeriod, :final endPeriod):
        _startPeriod = startPeriod;
        _endPeriod = endPeriod;
        _timeMode = 0;
      case ClockCourseTime(:final startTime, :final endTime):
        _timeMode = 1;
        _startTime = _parseTime(startTime) ?? _startTime;
        _endTime = _parseTime(endTime) ?? _endTime;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _teachers.dispose();
    super.dispose();
  }

  List<int> get _allWeeks => List<int>.generate(_totalWeeks, (index) => index + 1);

  void _loadSemesterContext(String? semesterId) {
    final table = _schedule.courseTableFor(semesterId);
    _periods = table?.periods.map((period) => period.toPeriod()).toList() ?? const [];
    final calendar = _schedule.termCalendarFor(semesterId);
    _termBegin = calendar?.termBegin;
    _totalWeeks = (calendar?.allTeachWeeks ?? 0) > 0
        ? calendar!.allTeachWeeks
        : semesterId == _schedule.selectedSemesterId
            ? _schedule.totalWeeks
            : 16;
  }

  void _setSemester(String value) {
    setState(() {
      final selectedAllWeeks = _weeks.length == _totalWeeks;
      _semesterId = value;
      _loadSemesterContext(value);
      if (_usesDefaultWeeks) {
        _weeks
          ..clear()
          ..addAll(_allWeeks.where((week) => week <= 16));
      } else if (selectedAllWeeks) {
        _weeks
          ..clear()
          ..addAll(_allWeeks);
      } else {
        _weeks.removeWhere((week) => week > _totalWeeks);
      }
      if (_timeMode == 0 && _periods.isEmpty) _timeMode = 1;
    });
  }

  bool get _isOneOff => _scheduleMode == 1;

  /// A one-off takes its own date's weekday, not a picked one.
  List<int> get _effectiveWeekdays {
    final day = _date;
    if (_isOneOff && day != null) return [day.weekday];
    return _weekdays.toList()..sort();
  }

  String get _weeksSummary {
    if (_weeks.isEmpty) return '';
    return formatWeekRanges(_weeks.toList()..sort());
  }

  String get _weekdaySummary => _effectiveWeekdays.map((day) => _weekdayLabels[day - 1]).join('、');

  /// Null when the timetable is shorter than the period asked for.
  Period? _periodOf(int number) =>
      number >= 1 && number <= _periods.length ? _periods[number - 1] : null;

  void _setWeeks(Iterable<int> weeks) {
    setState(() {
      _usesDefaultWeeks = false;
      _weeks
        ..clear()
        ..addAll(weeks);
    });
  }

  void _setWeekdays(Iterable<int> days) {
    setState(() {
      _weekdays
        ..clear()
        ..addAll(days);
    });
  }

  void _setStartPeriod(String value) {
    setState(() {
      _startPeriod = int.parse(value);
      if (_endPeriod < _startPeriod) _endPeriod = _startPeriod;
    });
  }

  void _setEndPeriod(String value) {
    setState(() {
      _endPeriod = int.parse(value);
      if (_startPeriod > _endPeriod) _startPeriod = _endPeriod;
    });
  }

  Future<void> _pickDate() async {
    final termBegin = _termBegin;
    final now = DateTime.now();
    final firstDate =
        termBegin?.subtract(const Duration(days: 30)) ?? now.subtract(const Duration(days: 365));
    final lastDate =
        termBegin?.add(const Duration(days: 400)) ?? now.add(const Duration(days: 365));

    var initialDate = _date ?? now;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showAdaptiveTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final semesterId = _semesterId;

    final problem = switch (true) {
      _ when name.isEmpty => '请填写课程名称',
      _ when semesterId == null => '课表尚未加载，暂时无法保存',
      _ when _isOneOff && _date == null => '请选择上课日期',
      _ when !_isOneOff && _weeks.isEmpty => '请至少选择一周',
      _ when _effectiveWeekdays.isEmpty => '请至少选择一个星期',
      _ when _timeMode == 0 && _periods.isEmpty => '该学期没有可用的节次信息',
      _
          when _timeMode == 1 &&
              (_endTime.hour * 60 + _endTime.minute) <=
                  (_startTime.hour * 60 + _startTime.minute) =>
        '结束时间必须晚于开始时间',
      _ => null,
    };
    if (problem != null) {
      showAdaptiveFeedback(
        context: context,
        message: problem,
        style: AdaptiveFeedbackStyle.error,
      );
      return;
    }

    setState(() => _saving = true);
    await _schedule.saveCustomCourse(
      semesterId!,
      CustomCourse(
        id: _id ?? CustomCourse.newId(),
        semesterId: _originSemesterId ?? semesterId,
        name: name,
        location: _location.text.trim(),
        teachers: _teachers.text.trim(),
        // A one-off is placed by its own date; a stored column could only
        // disagree with it later.
        weekdays: _isOneOff ? const [] : _weekdays.toList()
          ..sort(),
        time: _timeMode == 0
            ? PeriodCourseTime(
                startPeriod: _startPeriod,
                endPeriod: _endPeriod,
              )
            : ClockCourseTime(
                startTime: _formatTime(_startTime),
                endTime: _formatTime(_endTime),
              ),
        weeks: _isOneOff ? const [] : _weeks.toList()
          ..sort(),
        date: _isOneOff ? _date : null,
        color: _color,
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final semesterId = _originSemesterId ?? _semesterId;
    final id = _id;
    if (semesterId == null || id == null) return;

    await _schedule.deleteCustomCourse(semesterId, id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.course == null ? '添加课程' : '编辑课程';
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar:
          useIosChrome ? IosNativeNavigationBar(title: title) : BlurredAppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          topInset + 12,
          16,
          AppShellMetrics.bottomContentPaddingOf(context),
        ),
        children: [
          _section(
            '学期',
            children: [
              _select(
                value: _semesterId,
                options: _semesterOptions(),
                placeholder: '选择学期',
                onChanged: _setSemester,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            '课程信息',
            children: [
              AdaptiveTextFieldGroup(
                items: [
                  AdaptiveTextFieldGroupItem(
                    controller: _name,
                    placeholder: '课程名称',
                  ),
                  AdaptiveTextFieldGroupItem(
                    controller: _location,
                    placeholder: '上课地点（可选）',
                  ),
                  AdaptiveTextFieldGroupItem(
                    controller: _teachers,
                    placeholder: '教师（可选）',
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _section(
            '课程时间',
            children: [
              _select(
                value: _scheduleMode.toString(),
                options: const [
                  AdaptiveSelectOption(value: '0', label: '按周重复'),
                  AdaptiveSelectOption(value: '1', label: '只上一次'),
                ],
                placeholder: '选择方式',
                onChanged: (value) => setState(() => _scheduleMode = int.parse(value)),
              ),
              const SizedBox(height: 12),
              if (_isOneOff)
                _dateTile()
              else ...[
                AdaptiveMultiSelect(
                  options: [
                    for (final week in _allWeeks)
                      AdaptiveSelectOption(
                        value: '$week',
                        label: '第 $week 周',
                      ),
                  ],
                  values: _weeks.map((week) => '$week').toSet(),
                  summary: _weeksSummary,
                  placeholder: '选择周数',
                  title: '选择周数',
                  onChanged: (values) => _setWeeks(values.map(int.parse)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _shortcut(
                            '全选',
                            _weeks.length == _totalWeeks,
                            () => _setWeeks(_allWeeks.toSet()),
                          ),
                          _shortcut(
                            '单周',
                            _weeks.isNotEmpty && _weeks.every((week) => week.isOdd),
                            () => _setWeeks(
                              _allWeeks.where((week) => week.isOdd).toSet(),
                            ),
                          ),
                          _shortcut(
                            '双周',
                            _weeks.isNotEmpty && _weeks.every((week) => week.isEven),
                            () => _setWeeks(
                              _allWeeks.where((week) => week.isEven).toSet(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // An action, not a state — the chips beside it describe what
                    // is selected, this one only clears.
                    TextButton(
                      onPressed: _weeks.isEmpty ? null : () => _setWeeks(const {}),
                      child: const Text('清空'),
                    ),
                  ],
                ),
                if (!_isOneOff) ...[
                  const SizedBox(height: 12),
                  AdaptiveMultiSelect(
                    options: [
                      for (var day = 1; day <= 7; day++)
                        AdaptiveSelectOption(
                          value: '$day',
                          label: _weekdayLabels[day - 1],
                        ),
                    ],
                    values: _weekdays.map((day) => '$day').toSet(),
                    summary: _weekdaySummary,
                    placeholder: '选择星期',
                    title: '选择星期',
                    onChanged: (values) => _setWeekdays(values.map(int.parse)),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),
          _section('时间段', children: _timeFields()),
          const SizedBox(height: 20),
          AdaptiveButton(
            onPressed: _saving ? null : _save,
            icon: Icons.check_rounded,
            sfSymbol: 'checkmark',
            label: '保存',
            role: AdaptiveButtonRole.prominent,
            loading: _saving,
            accessibilityLabel: '保存课程',
          ),
          if (widget.course != null) ...[
            const SizedBox(height: 8),
            AdaptiveConfirmationButton(
              label: '删除',
              confirmTitle: '删除这节课？',
              confirmLabel: '删除',
              icon: Icons.delete_outline,
              sfSymbol: 'trash',
              destructive: true,
              onConfirmed: _delete,
            ),
          ],
        ],
      ),
    );
  }

  List<AdaptiveSelectOption> _semesterOptions() {
    final info = _schedule.semesterInfo;
    if (info == null) return const [];
    final options = <AdaptiveSelectOption>[];
    for (final year in info.semesters.keys.toList()..sort()) {
      for (final term in info.semesters[year]!.entries) {
        options.add(
          AdaptiveSelectOption(
            value: term.value,
            label: '$year ${semesterTermDisplayName(term.key)}学期',
          ),
        );
      }
    }
    return options;
  }

  List<Widget> _timeFields() {
    if (_timeMode == 1) {
      return [
        _timeTile(isStart: true),
        const SizedBox(height: 12),
        _timeTile(isStart: false),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => setState(() => _timeMode = 0),
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('按节次'),
          ),
        ),
      ];
    }

    return [
      _periodRow(
        label: '开始',
        value: '$_startPeriod',
        options: [
          for (final period in _periods)
            AdaptiveSelectOption(
              value: '${period.number}',
              // The start of the period is what a start time is.
              label: '第 ${period.number} 节  ${period.startTime}',
            ),
        ],
        onChanged: _setStartPeriod,
      ),
      const SizedBox(height: 12),
      _periodRow(
        label: '结束',
        value: '$_endPeriod',
        options: [
          for (final period in _periods)
            AdaptiveSelectOption(
              value: '${period.number}',
              label: '第 ${period.number} 节  ${period.endTime}',
            ),
        ],
        onChanged: _setEndPeriod,
      ),
      const SizedBox(height: 4),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(
          onPressed: () => setState(() {
            // Entering custom times starts from what the periods already say.
            final parsedStart = _parseTime(_periodOf(_startPeriod)?.startTime);
            final parsedEnd = _parseTime(_periodOf(_endPeriod)?.endTime);
            if (parsedStart != null) _startTime = parsedStart;
            if (parsedEnd != null) _endTime = parsedEnd;
            _timeMode = 1;
          }),
          icon: const Icon(Icons.schedule_outlined, size: 18),
          label: const Text('自定义时间'),
        ),
      ),
    ];
  }

  /// A period dropdown beside the label that says which end of the range it
  /// is — the field itself only ever shows the period.
  Widget _periodRow({
    required String label,
    required String value,
    required List<AdaptiveSelectOption> options,
    required ValueChanged<String> onChanged,
  }) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 12),
        Expanded(
          child: AdaptiveSelect(
            options: options,
            value: value,
            placeholder: '选择节次',
            width: double.infinity,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _timeTile({required bool isStart}) {
    final value = isStart ? _startTime : _endTime;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(isStart ? Icons.play_arrow_outlined : Icons.stop_outlined),
      title: Text(isStart ? '开始时间' : '结束时间'),
      trailing: Text(
        _formatTime(value),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      onTap: () => unawaited(_pickTime(isStart: isStart)),
    );
  }

  Widget _dateTile() {
    final theme = Theme.of(context);
    final date = _date;
    final week = date == null ? null : teachingWeekOf(date, _schedule.termBegin);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_outlined),
      title: const Text('上课日期'),
      subtitle: Text(
        date == null
            ? '未选择'
            : '${_formatDate(date)} ${_weekdayLabels[date.weekday - 1]}'
                '${week == null ? '' : ' · 第 $week 周'}',
      ),
      trailing: Text(
        '选择',
        style: TextStyle(color: theme.colorScheme.primary),
      ),
      onTap: _pickDate,
    );
  }

  Widget _section(String title, {required List<Widget> children}) {
    final theme = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _select({
    required String? value,
    required List<AdaptiveSelectOption> options,
    required String placeholder,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: double.infinity,
      child: AdaptiveSelect(
        options: options,
        value: value,
        placeholder: placeholder,
        width: double.infinity,
        onChanged: onChanged,
      ),
    );
  }

  Widget _shortcut(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onTap(),
    );
  }
}

const List<String> _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String _formatDate(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}'
    '-${date.day.toString().padLeft(2, '0')}';

String _formatTime(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parseTime(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}
