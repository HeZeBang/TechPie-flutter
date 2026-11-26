import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grade_record.dart';
import '../services/campus/campus_errors.dart';
import '../services/grade_service.dart';
import '../services/service_provider.dart';

class GradesPage extends StatelessWidget {
  const GradesPage({super.key, this.service});
  final GradeService? service;

  @override
  Widget build(BuildContext context) {
    final grades = service ?? ServiceProvider.of(context).gradeService!;
    return ListenableBuilder(
      listenable: grades,
      builder: (context, _) => _GradesView(key: ValueKey(grades.generation), grades: grades),
    );
  }
}

class _GradesView extends StatefulWidget {
  const _GradesView({super.key, required this.grades});
  final GradeService grades;
  @override
  State<_GradesView> createState() => _GradesViewState();
}

class _GradesViewState extends State<_GradesView> {
  GradeScope scope = GradeScope.major;
  bool english = false, busy = false, simulating = false;
  String? term, error;
  final omitted = <CourseGrade>{};
  final hypothetical = <CourseGrade>[];

  @override
  void initState() {
    super.initState();
    if (widget.grades.ready) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final grades = widget.grades;
    try {
      if (english) {
        if (grades.semesters.isEmpty) await grades.loadEnglishTerms();
        if (!mounted) return;
        term ??= grades.semesters.keys.firstOrNull;
        if (term != null) await grades.loadEnglish(term!);
      } else {
        await grades.refresh(scope);
        if (!mounted) return;
        if (!grades.courses(scope).any((g) => g.semester == term)) term = null;
        omitted.clear();
        hypothetical.clear();
        simulating = false;
      }
    } catch (e) {
      if (mounted) error = e is CampusRequestException ? e.message : '成绩读取失败，请重试';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addCourse() async {
    final generation = widget.grades.generation;
    final grade =
        await showDialog<CourseGrade>(context: context, builder: (_) => const _TrialDialog());
    if (grade != null && mounted && generation == widget.grades.generation) {
      setState(() => hypothetical.add(grade));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.grades;
    final all = service.courses(scope);
    final shown = all.where((g) => term == null || g.semester == term).toList();
    final summary = GradeSummary.of(shown);
    final activeCourses = simulating
        ? [...shown, ...hypothetical].where((g) => !omitted.contains(g)).toList()
        : shown;
    final activeSummary = simulating ? GradeSummary.of(activeCourses) : summary;
    final terms = english
        ? service.semesters
        : {
            for (final g in all)
              if (g.semester.isNotEmpty) g.semester: g.semester,
          };
    final updated = service.updated(scope);
    final theme = Theme.of(context);
    final englishRows = service.english(term ?? '');
    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩与 GPA'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: busy || !service.ready ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !service.ready
          ? const Center(child: Text('请登录并绑定学校账号后查看成绩'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final s in GradeScope.values)
                            ChoiceChip(
                              label: Text(s.label),
                              selected: !english && scope == s,
                              onSelected: busy
                                  ? null
                                  : (_) {
                                      setState(() {
                                        scope = s;
                                        english = false;
                                        term = null;
                                        simulating = false;
                                        hypothetical.clear();
                                        omitted.clear();
                                      });
                                      unawaited(refresh());
                                    },
                            ),
                          ChoiceChip(
                            label: const Text('英语成绩'),
                            selected: english,
                            onSelected: busy
                                ? null
                                : (_) {
                                    setState(() {
                                      english = true;
                                      term = null;
                                      simulating = false;
                                      hypothetical.clear();
                                      omitted.clear();
                                    });
                                    unawaited(refresh());
                                  },
                          ),
                        ],
                      ),
                      if (terms.isNotEmpty)
                        DropdownButton<String>(
                          isExpanded: true,
                          value: term ?? (english ? null : ''),
                          hint: const Text('选择学期'),
                          items: [
                            if (!english) const DropdownMenuItem(value: '', child: Text('全部学期')),
                            for (final t in terms.entries)
                              DropdownMenuItem(value: t.key, child: Text(t.value)),
                          ],
                          onChanged: busy
                              ? null
                              : (v) {
                                  setState(() {
                                    term = v == '' ? null : v;
                                    hypothetical.clear();
                                    omitted.clear();
                                  });
                                  if (english) unawaited(refresh());
                                },
                        ),
                      if (busy) const LinearProgressIndicator(),
                      if (error != null)
                        ListTile(
                          title: Text(error!),
                          trailing: TextButton(onPressed: refresh, child: const Text('重试')),
                        ),
                      if (!english) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  simulating ? '预测 GPA' : '加权 GPA',
                                  style: theme.textTheme.labelLarge,
                                ),
                                Text(
                                  activeSummary.gpa?.toStringAsFixed(2) ?? '—',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Text(
                                  '已获 ${activeSummary.earnedCredits} 学分 · 计入 GPA ${activeSummary.gradedCredits} 学分',
                                ),
                                Text(
                                  '${activeSummary.courseCount} 门课程 · ${activeCourses.map((g) => g.semester).where((s) => s.isNotEmpty).toSet().length} 个学期',
                                ),
                                if (updated != null)
                                  Text(
                                    '更新于 ${DateFormat('yyyy-MM-dd HH:mm').format(updated.toLocal())}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('本地 GPA 试算'),
                                  value: simulating,
                                  onChanged: busy
                                      ? null
                                      : (v) => setState(() {
                                            simulating = v;
                                            omitted.clear();
                                            hypothetical.clear();
                                          }),
                                ),
                                if (simulating)
                                  TextButton.icon(
                                    onPressed: addCourse,
                                    icon: const Icon(Icons.add),
                                    label: const Text('添加假设课程'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        for (final g in [...shown, ...hypothetical])
                          ListTile(
                            leading: simulating
                                ? Checkbox(
                                    value: !omitted.contains(g),
                                    onChanged: (_) => setState(() {
                                      if (!omitted.remove(g)) omitted.add(g);
                                    }),
                                  )
                                : null,
                            title: Text(g.courseName),
                            subtitle: Text(
                              [
                                g.semester,
                                g.courseCode,
                                g.courseType,
                                '${g.credits} 学分',
                                if (g.isRetake) '重修／补考',
                                if (g.passed != null) g.passed! ? '通过' : '未通过',
                              ].where((s) => s.isNotEmpty).join(' · '),
                            ),
                            trailing: Text(
                              [g.scoreText, if (g.gradePoint != null) '绩点 ${g.gradePoint}']
                                  .where((s) => s.isNotEmpty)
                                  .join('\n'),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        if (shown.isEmpty && !busy && error == null)
                          const ListTile(title: Text('暂无课程成绩')),
                      ] else ...[
                        for (final g in englishRows)
                          ListTile(
                            title: Text(g.exam),
                            subtitle: Text(
                              [g.semester, g.status].where((s) => s.isNotEmpty).join(' · '),
                            ),
                            trailing: Text(g.score),
                          ),
                        if (englishRows.isEmpty && !busy && error == null)
                          const ListTile(title: Text('该学期暂无英语成绩')),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TrialDialog extends StatefulWidget {
  const _TrialDialog();
  @override
  State<_TrialDialog> createState() => _TrialDialogState();
}

class _TrialDialogState extends State<_TrialDialog> {
  double? credits, point;
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('添加假设课程'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final isCredits in [true, false])
              TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: isCredits ? '学分' : '预期绩点'),
                onChanged: (v) => setState(() {
                  if (isCredits) {
                    credits = double.tryParse(v);
                  } else {
                    point = double.tryParse(v);
                  }
                }),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: credits?.isFinite == true &&
                    credits! > 0 &&
                    point?.isFinite == true &&
                    point! >= 0 &&
                    point! <= 4
                ? () => Navigator.pop(
                      context,
                      CourseGrade(
                        semester: '',
                        courseCode: '',
                        courseName: '假设课程',
                        courseType: '试算',
                        credits: credits!,
                        scoreText: '',
                        gradePoint: point,
                        passed: point! > 0,
                        isRetake: false,
                      ),
                    )
                : null,
            child: const Text('添加'),
          ),
        ],
      );
}
