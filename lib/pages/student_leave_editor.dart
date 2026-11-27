import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, XFile;

import '../models/student_leave.dart';
import '../services/campus/campus_errors.dart';
import '../services/student_leave_attachments.dart';
import '../services/student_leave_service.dart';
import '../services/student_leave_submission.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_date_picker.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_progress_indicator.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

Future<bool?> openStudentLeaveEditor(
  BuildContext context,
  StudentLeaveService service, {
  StudentLeave? editing,
  Map<String, String> initial = const {},
}) =>
    pushAdaptivePage<bool>(
      context,
      builder: (_) => _LeaveEditor(service: service, editing: editing, initial: initial),
    );

String _leaveError(Object error) => switch (error) {
      CampusRequestException e => e.message,
      FormatException e => e.message,
      LeaveSaveUncertain e => e.toString(),
      _ => '无法完成操作，请检查网络后重试',
    };

class _LeaveEditor extends StatefulWidget {
  const _LeaveEditor({required this.service, this.editing, required this.initial});
  final StudentLeaveService service;
  final StudentLeave? editing;
  final Map<String, String> initial;

  @override
  State<_LeaveEditor> createState() => _LeaveEditorState();
}

class _LeaveEditorState extends State<_LeaveEditor> {
  final _fields = GlobalKey<FormState>();
  late final int rev = service.revision;
  StudentLeaveService get service => widget.service;
  late Future<void> startup;
  late LeaveForm form;
  Map<String, String> values = {};
  Map<String, String> properties = {};
  List<LeaveKind> kinds = [];
  List<XFile> proof = [], courseProof = [];
  bool requiresProof = false, busy = false, uncertain = false, invalidAccount = false;
  String instructions = '';
  String? error;
  String get property => values['QJXZ'] ?? '';
  String get type => values['QJLX'] ?? '';
  bool get edit => widget.editing != null;
  bool get needsCourseProof => form.undergraduate && values['YL6'] == '1';
  String value(String name) => values[name] ?? '';
  DateTime? date(String name) => DateTime.tryParse(value(name));
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  String get dateText {
    final start = date('QJKSRQ'), end = date('QJJSRQ');
    if (start == null || end == null) return '选择请假日期';
    final count = DateTime.utc(end.year, end.month, end.day)
            .difference(DateTime.utc(start.year, start.month, start.day))
            .inDays +
        1;
    return '${day(start)} 至 ${day(end)}（$count 天）';
  }

  @override
  void initState() {
    super.initState();
    service.addListener(accountChanged);
    startup = load();
  }

  @override
  void dispose() {
    service.removeListener(accountChanged);
    super.dispose();
  }

  void accountChanged() {
    if (rev == service.revision || invalidAccount) return;
    setState(() {
      invalidAccount = true;
      busy = false;
      values.clear();
      proof.clear();
      courseProof.clear();
    });
  }

  Future<void> load() async {
    final loaded = await service.openLeaveForm(rev, editing: widget.editing);
    final info = await service.applicationInfo(rev);
    final initial = {...loaded.values, ...widget.initial};
    final initialProperty = initial['QJXZ'] ?? '';
    final initialType = initial['QJLX'] ?? '';
    final options =
        initialProperty.isEmpty ? <LeaveKind>[] : await service.leaveTypes(initialProperty, rev);
    final requirements =
        initialType.isEmpty ? null : await service.leaveTypeRequirements(initialType, rev);
    final start = DateTime.tryParse(initial['QJKSRQ'] ?? '');
    final end = DateTime.tryParse(initial['QJJSRQ'] ?? '');
    if (widget.initial.containsKey('QJKSRQ') &&
        widget.initial.containsKey('QJJSRQ') &&
        start != null &&
        end != null) {
      initial['DZ_KCMC'] = await service.affectedCourses(start, end, rev);
    }
    service.check(rev);
    if (!mounted) return;
    form = loaded;
    values = initial;
    kinds = options;
    properties = {...info.properties};
    if (initialProperty.isNotEmpty) {
      properties.putIfAbsent(initialProperty, () => initial['QJXZ_DISPLAY'] ?? initialProperty);
    }
    requiresProof = requirements?.proofRequired ?? false;
    instructions = requirements?.instructions ?? '';
  }

  Future<void> changeProperty(String? v) async {
    if (v == null || v == property) return;
    setState(() {
      values.addAll({'QJXZ': v, 'QJXZ_DISPLAY': properties[v]!, 'QJLX': '', 'QJLX_DISPLAY': ''});
      clearDates();
      kinds = [];
      requiresProof = false;
      instructions = '';
      busy = true;
      error = null;
    });
    try {
      final result = await service.leaveTypes(v, rev);
      if (mounted && !invalidAccount) setState(() => kinds = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _leaveError(e);
          values.remove('QJXZ');
          values.remove('QJXZ_DISPLAY');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void clearDates() {
    for (final key in ['QJKSRQ', 'QJJSRQ', 'QJRQ', 'DZ_KCMC']) {
      values.remove(key);
    }
  }

  Future<void> changeKind(String? v) async {
    if (v == null || type == v) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final requirements = await service.leaveTypeRequirements(v, rev);
      if (!mounted || invalidAccount) return;
      setState(() {
        values.addAll({'QJLX': v, 'QJLX_DISPLAY': kinds.firstWhere((k) => k.id == v).label});
        clearDates();
        requiresProof = requirements.proofRequired;
        instructions = requirements.instructions;
      });
    } catch (e) {
      if (mounted) setState(() => error = _leaveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickDates() async {
    final kind = kinds.where((k) => k.id == type).firstOrNull;
    final now = DateTime.now();
    final min = kind?.earliestStart(now) ?? DateTime(now.year, now.month, now.day - 7);
    final start = date('QJKSRQ'), end = date('QJJSRQ');
    final firstDate = edit && start != null && start.isBefore(min) ? start : min;
    final maxYear = [now.year + 2, if (end != null) end.year + 1].reduce((a, b) => a > b ? a : b);
    final range = await showAdaptiveDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: DateTime(maxYear, 12, 31),
      initialDateRange:
          start != null && end != null && !start.isBefore(firstDate) && !end.isBefore(start)
              ? DateTimeRange(start: start, end: end)
              : null,
      title: '选择请假日期',
    );
    if (!mounted || invalidAccount || range == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final courses = await service.affectedCourses(range.start, range.end, rev);
      if (!mounted || invalidAccount) return;
      setState(() {
        values.remove('QJRQ');
        values.addAll({'QJKSRQ': day(range.start), 'QJJSRQ': day(range.end), 'DZ_KCMC': courses});
      });
    } catch (e) {
      if (mounted) setState(() => error = _leaveError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickRegion() async {
    final region = await showDialog<LeaveRegion>(
      context: context,
      builder: (_) => _RegionSearch(service: service, revision: rev),
    );
    if (region != null && mounted && !invalidAccount) {
      setState(() => values.addAll({'DZ_QJQX': region.code, 'DZ_QJQX_DISPLAY': region.label}));
    }
  }

  Future<void> pickFiles(bool course) async {
    try {
      final files = await ImagePicker().pickMultiImage();
      if (!mounted || invalidAccount || files.isEmpty) return;
      for (final f in files) {
        final dot = f.name.lastIndexOf('.');
        final extension =
            dot > 0 && dot < f.name.length - 1 ? f.name.substring(dot + 1).toLowerCase() : '';
        if (!StudentLeaveAttachments.extensions.contains(extension)) {
          throw FormatException(
            '该格式不支持作为${course ? '任课教师知情材料' : '证明材料'}，请选择图片、PDF 或学校支持的文档',
          );
        }
        if (await f.length() > StudentLeaveAttachments.maxProofBytes) {
          throw FormatException('每份${course ? '任课教师知情材料' : '证明材料'}须小于或等于 5 MiB');
        }
      }
      if (!mounted || invalidAccount) return;
      setState(() {
        (course ? courseProof : proof).addAll(files);
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = _leaveError(e));
    }
  }

  Future<Map<String, String>> upload() async {
    final attachments = StudentLeaveAttachments(service.client);
    final tokens = <String, String>{};
    for (final entry in [
      (false, requiresProof ? proof : <XFile>[]),
      (true, needsCourseProof ? courseProof : <XFile>[]),
    ]) {
      if (entry.$2.isEmpty) continue;
      service.check(rev);
      final files = <LeaveAttachmentFile>[];
      for (final f in entry.$2) {
        files.add(LeaveAttachmentFile(f.name, await f.readAsBytes()));
      }
      tokens[entry.$1 ? 'YL7' : 'ZMCL'] = await attachments.persist(
        files,
        courseProof: entry.$1,
        checkAccount: () => service.check(rev),
      );
    }
    return tokens;
  }

  String? missingRequirement() {
    if (type.isEmpty) return '请选择请假类型';
    if (date('QJKSRQ') == null || date('QJJSRQ') == null) return '请选择请假日期';
    if (value('DZ_QJQX').isEmpty) return '请选择请假去向';
    if (requiresProof && proof.isEmpty && value('ZMCL').isEmpty) return '请添加证明材料';
    if (needsCourseProof && courseProof.isEmpty && value('YL7').isEmpty) return '请添加任课教师知情材料';
    return null;
  }

  Future<void> save() async {
    if (busy || uncertain || invalidAccount) return;
    final valid = _fields.currentState!.validate();
    final missing = missingRequirement();
    if (!valid || missing != null) {
      setState(() => error = missing ?? '请检查带有提示的字段');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final confirm = await showAdaptiveAlertDialog<bool>(
        context: context,
        title: edit ? '保存请假修改？' : '提交请假申请？',
        message: [
          value('QJLX_DISPLAY'),
          dateText,
          '${value('DZ_QJQX_DISPLAY')} ${value('DZ_XXDZ')}',
          value('QJSY'),
          value('YL6_DISPLAY'),
          if (requiresProof) ...proof.map((f) => f.name),
          if (needsCourseProof) ...courseProof.map((f) => f.name),
        ].where((line) => line.trim().isNotEmpty).join('\n'),
        actions: [
          const AdaptiveAlertAction(label: '取消', value: false),
          AdaptiveAlertAction(label: edit ? '保存修改' : '确认提交', value: true, isDefault: true),
        ],
      );
      if (!mounted || invalidAccount || confirm != true) return;
      final changes = {
        for (final e in values.entries)
          if (e.value != form.values[e.key]) e.key: e.value,
      };
      final result = await service.saveLeaveForm(form, changes, uploadAttachments: upload);
      String message = result.message;
      try {
        await service.refresh();
      } catch (_) {
        message = '$message，请刷新请假记录';
      }
      if (!mounted || invalidAccount) return;
      showAdaptiveFeedback(
        context: context,
        message: message,
        style: AdaptiveFeedbackStyle.success,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted && !invalidAccount) {
        setState(() {
          error = _leaveError(e);
          uncertain = e is LeaveSaveUncertain;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = edit ? '编辑请假' : '填写请假申请';
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: context.tpColors.canvas,
        appBar: AdaptiveNavigationScaffold.adaptiveBar(
          ios: () => IosNativeNavigationBar(
            title: title,
            leadingItems: [
              IosNativeNavigationBarItem(
                id: 'back',
                title: '返回',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回',
                enabled: !busy,
                placementGroup: 'leading-main',
              ),
            ],
            onItemPressed: (_) {
              if (!busy) unawaited(maybePopAdaptivePage<bool>(context));
            },
          ),
          material: () => BlurredAppBar(title: Text(title)),
        ),
        body: invalidAccount
            ? const Center(child: Text('账号已切换，请返回请假记录。'))
            : FutureBuilder<void>(
                future: startup,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: AdaptiveActivityIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_leaveError(snapshot.error!)),
                          TextButton(
                            onPressed: () => setState(() => startup = load()),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  }
                  return SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Expanded(
                          child: AbsorbPointer(
                            absorbing: busy || uncertain,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: TpPageBody(child: applicationFields()),
                            ),
                          ),
                        ),
                        submitBar(),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget applicationFields() => Form(
        key: _fields,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dropdown('请假性质', property, properties, changeProperty),
            dropdown(
              '请假类型',
              type,
              {
                for (final k in kinds) k.id: k.label,
                if (type.isNotEmpty) type: value('QJLX_DISPLAY'),
              },
              changeKind,
            ),
            if (instructions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(instructions, style: Theme.of(context).textTheme.bodySmall),
              ),
            OutlinedButton.icon(
              onPressed: type.isEmpty ? null : pickDates,
              icon: const Icon(TpIcons.calendar),
              label: Text(dateText),
            ),
            field('QJSY', '请假事由', lines: 2, limit: 1000),
            section('请假去向'),
            OutlinedButton.icon(
              onPressed: pickRegion,
              icon: const Icon(TpIcons.location),
              label: Text(value('DZ_QJQX_DISPLAY').isEmpty ? '选择省市区' : value('DZ_QJQX_DISPLAY')),
            ),
            field('DZ_XXDZ', '详细地址'),
            section('联系方式'),
            TpBentoGrid(
              breakpoint: 560,
              primaryFlex: 1,
              secondaryFlex: 1,
              verticalGap: 0,
              primaryColumn: [
                field('YL1', '联系电话', keyboard: TextInputType.phone),
                field('YL2', '联系邮箱', keyboard: TextInputType.emailAddress),
              ],
              secondaryColumn: [
                field('YL4', '紧急联系人'),
                field('YL5', '紧急联系电话', keyboard: TextInputType.phone),
              ],
            ),
            section('课程与材料'),
            if (date('QJKSRQ') != null)
              Text(value('DZ_KCMC').isEmpty ? '所选日期没有课程' : value('DZ_KCMC')),
            field('YL3', '涉及课程或其他培养环节', limit: 500),
            dropdown(
              '是否涉及课程',
              value('YL6'),
              courseChoices,
              (v) {
                if (v != null) {
                  setState(() => values.addAll({'YL6': v, 'YL6_DISPLAY': courseChoices[v]!}));
                }
              },
              required: true,
            ),
            if (requiresProof)
              ...fileField(false)
            else if (value('ZMCL').isNotEmpty)
              const Text('已保留原有证明材料'),
            if (needsCourseProof) ...fileField(true),
          ],
        ),
      );

  Future<void> returnToHistory() async {
    setState(() => busy = true);
    try {
      await service.refresh();
    } on CampusRequestException {
      // The user can refresh again from their records; never resubmit this form.
    } finally {
      if (mounted) {
        setState(() => busy = false);
        Navigator.of(context).pop();
      }
    }
  }

  Widget submitBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TpPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              FilledButton(
                onPressed: busy
                    ? null
                    : uncertain
                        ? returnToHistory
                        : save,
                child: Text(
                  busy
                      ? '处理中…'
                      : uncertain
                          ? '返回查看请假记录'
                          : edit
                              ? '保存修改'
                              : '提交请假申请',
                ),
              ),
            ],
          ),
        ),
      );

  static const courseChoices = {'0': '不涉及课程', '1': '涉及课程，已获得任课老师知情同意', '2': '涉及课程，未获得任课老师知情同意'};
  Widget section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
  Widget dropdown(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String?> onChanged, {
    bool required = false,
  }) {
    final validValue = options.containsKey(selected) ? selected : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FormField<String>(
        key: ValueKey((label, selected, options.length)),
        initialValue: validValue,
        validator: (v) =>
            required && (v == null || v.isEmpty) ? '请选择$label' : null,
        builder: (field) {
          final colors = context.tpColors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AdaptiveSelect(
                label: label,
                width: double.infinity,
                enabled: options.isNotEmpty,
                value: field.value,
                placeholder: '请选择$label',
                options: [
                  for (final e in options.entries)
                    AdaptiveSelectOption(value: e.key, label: e.value),
                ],
                onChanged: (v) {
                  field.didChange(v);
                  onChanged(v);
                },
              ),
              if (field.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: TpTokens.space1),
                  child: Text(
                    field.errorText!,
                    style: TpTypography.itemMeta(colors).copyWith(
                      color: colors.dangerRed,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
  Widget field(String code, String label, {TextInputType? keyboard, int lines = 1, int? limit}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          key: ValueKey(code),
          initialValue: value(code),
          decoration: InputDecoration(labelText: label),
          minLines: lines,
          maxLines: lines,
          keyboardType: keyboard,
          maxLength: limit,
          onChanged: (v) => values[code] = v.trim(),
          validator: (v) => v == null || v.trim().isEmpty ? '请填写$label' : null,
        ),
      );
  List<Widget> fileField(bool course) {
    final selected = course ? courseProof : proof, key = course ? 'YL7' : 'ZMCL';
    final label = course ? '任课教师知情材料' : '证明材料';
    return [
      if (value(key).isNotEmpty) Text(selected.isEmpty ? '已保留原有$label' : '所选文件将替换原有$label'),
      for (final f in selected)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(TpIcons.attach),
          title: Text(f.name),
          trailing: IconButton(
            tooltip: '移除 ${f.name}',
            icon: const Icon(TpIcons.close),
            onPressed: () => setState(() => selected.remove(f)),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => pickFiles(course),
          icon: const Icon(TpIcons.attach),
          label: Text('添加$label'),
        ),
      ),
      Text(
        '支持从相册选择图片证明；如需上传 PDF 等文档可在网页版提交',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}

class _RegionSearch extends StatefulWidget {
  const _RegionSearch({required this.service, required this.revision});
  final StudentLeaveService service;
  final int revision;
  @override
  State<_RegionSearch> createState() => _RegionSearchState();
}

class _RegionSearchState extends State<_RegionSearch> {
  final _controller = TextEditingController();
  String keyword = '';
  Future<List<LeaveRegion>>? result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void search() {
    final trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      setState(() => result = widget.service.leaveRegions(trimmed, widget.revision));
    }
  }

  void clear() {
    _controller.clear();
    setState(() {
      keyword = '';
      result = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('选择省市区'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '搜索地区名称',
                  hintText: '如：上海市、浦东新区',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (keyword.isNotEmpty)
                        IconButton(
                          tooltip: '清除搜索',
                          onPressed: clear,
                          icon: const Icon(TpIcons.close),
                        ),
                      IconButton(
                        tooltip: '搜索',
                        onPressed: search,
                        icon: const Icon(TpIcons.search),
                      ),
                    ],
                  ),
                ),
                onChanged: (v) => setState(() => keyword = v),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
              ),
              if (result != null)
                Flexible(
                  child: FutureBuilder<List<LeaveRegion>>(
                    future: result,
                    builder: (context, s) {
                      if (s.connectionState != ConnectionState.done) {
                        return const LinearProgressIndicator();
                      }
                      if (s.hasError) return Text(_leaveError(s.error!));
                      if (s.requireData.isEmpty) return const Text('未找到地区');
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          for (final area in s.requireData)
                            ListTile(
                              title: Text(area.label),
                              onTap: () => Navigator.of(context).pop(area),
                            ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        ],
      );
}
