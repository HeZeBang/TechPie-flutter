import 'package:flutter/material.dart';

import '../models/student_leave.dart';
import '../services/campus/campus_errors.dart';
import '../services/student_leave_service.dart';
import '../theme/theme.dart';
import '../widgets/design_system/design_system.dart';
import 'student_leave_editor.dart';

export 'student_leave_editor.dart' show openStudentLeaveEditor;

/// Mounted inside the account-scoped history so draft selections expire with it.
class StudentLeaveApplication extends StatefulWidget {
  const StudentLeaveApplication({super.key, required this.service, required this.schoolFormButton});
  final StudentLeaveService service;

  final Widget schoolFormButton;

  @override
  State<StudentLeaveApplication> createState() => _StudentLeaveApplicationState();
}

class _StudentLeaveApplicationState extends State<StudentLeaveApplication> {
  late final revision = widget.service.revision;
  Future<LeaveApplicationInfo>? info;
  String? property;
  Future<List<LeaveKind>>? types;
  LeaveKind? kind;
  DateTimeRange? dates;
  Future<String>? courses;

  void loadInfo() {
    final pending = widget.service.applicationInfo(revision);
    setState(() {
      info = pending;
    });
  }

  void selectProperty(String? value) {
    if (value == null) return;
    setState(() {
      property = value;
      types = widget.service.leaveTypes(value, revision);
      kind = null;
      dates = null;
      courses = null;
    });
  }

  Future<void> selectDates() async {
    final currentKind = kind;
    if (currentKind == null) return;
    final today = DateTime.now();
    final maxYear = [
      today.year + 2,
      if (dates != null) dates!.end.year + 1,
    ].reduce((a, b) => a > b ? a : b);
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: dates,
      firstDate: currentKind.earliestStart(today),
      lastDate: DateTime(maxYear, 12, 31),
      helpText: '选择请假日期',
    );
    if (!mounted || selected == null || widget.service.revision != revision) return;
    setState(() {
      dates = selected;
      courses = widget.service.affectedCourses(selected.start, selected.end, revision);
    });
  }

  Widget retry(Object? error, VoidCallback action) => Row(
        children: [
          Expanded(child: Text(error is CampusRequestException ? error.message : '查询失败')),
          TextButton(onPressed: action, child: const Text('重试')),
        ],
      );

  @override
  Widget build(BuildContext context) => TpCard(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: const Text('请假申请'),
            subtitle: const Text('查看申请资格、假种和请假期间的课程'),
            onExpansionChanged: (open) {
              if (open && info == null) {
                loadInfo();
              }
            },
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (info != null)
                FutureBuilder<LeaveApplicationInfo>(
                  future: info,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.hasError) {
                      return retry(
                        snapshot.error,
                        loadInfo,
                      );
                    }
                    final data = snapshot.requireData;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('本学期已请假 ${data.daysUsed} 天'),
                        const SizedBox(height: 8),
                        if (!data.eligible)
                          Text(data.reason.isEmpty ? '当前无法申请请假' : data.reason)
                        else ...[
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: '请假性质'),
                            items: [
                              for (final entry in data.properties.entries)
                                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                            ],
                            onChanged: selectProperty,
                          ),
                          if (types != null)
                            FutureBuilder<List<LeaveKind>>(
                              future: types,
                              builder: (context, result) {
                                if (result.connectionState != ConnectionState.done) {
                                  return const LinearProgressIndicator();
                                }
                                if (result.hasError) {
                                  return retry(result.error, () => selectProperty(property));
                                }
                                if (result.requireData.isEmpty) {
                                  return const Text('当前性质下没有可选假种');
                                }
                                return DropdownButtonFormField<LeaveKind>(
                                  key: ValueKey(property),
                                  decoration: const InputDecoration(labelText: '请假类型'),
                                  items: [
                                    for (final item in result.requireData)
                                      DropdownMenuItem(value: item, child: Text(item.label)),
                                  ],
                                  onChanged: (value) => setState(() {
                                    kind = value;
                                    dates = null;
                                    courses = null;
                                  }),
                                );
                              },
                            ),
                          if (kind != null)
                            OutlinedButton.icon(
                              icon: const Icon(TpIcons.calendar),
                              onPressed: selectDates,
                              label: Text(
                                dates == null
                                    ? '选择请假日期'
                                    : '${_day(dates!.start)} 至 ${_day(dates!.end)}',
                              ),
                            ),
                          if (courses != null)
                            FutureBuilder<String>(
                              future: courses,
                              builder: (context, result) {
                                if (result.connectionState != ConnectionState.done) {
                                  return const LinearProgressIndicator();
                                }
                                if (result.hasError) {
                                  return retry(
                                    result.error,
                                    () => setState(() {
                                      courses = widget.service
                                          .affectedCourses(dates!.start, dates!.end, revision);
                                    }),
                                  );
                                }
                                return Text(
                                  result.requireData.isEmpty
                                      ? '所选日期没有课程'
                                      : '涉及课程：${result.requireData}',
                                );
                              },
                            ),
                          if (dates != null && kind != null)
                            FilledButton(
                              onPressed: () => openStudentLeaveEditor(
                                context,
                                widget.service,
                                initial: {
                                  'QJXZ': property!,
                                  'QJXZ_DISPLAY': data.properties[property!]!,
                                  'QJLX': kind!.id,
                                  'QJLX_DISPLAY': kind!.label,
                                  'QJKSRQ': _day(dates!.start),
                                  'QJJSRQ': _day(dates!.end),
                                },
                              ),
                              child: const Text('填写申请'),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              widget.schoolFormButton,
            ],
          ),
        ),
      );

  String _day(DateTime date) => date.toIso8601String().substring(0, 10);
}
