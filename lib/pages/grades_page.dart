import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/grade_record.dart';
import '../services/campus/campus_errors.dart';
import '../services/grade_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_checkbox.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/page_refresh.dart';

class GradesPage extends StatelessWidget {
  const GradesPage({super.key, this.service});
  final GradeService? service;

  @override
  Widget build(BuildContext context) {
    final grades = service ??
        context.dependOnInheritedWidgetOfExactType<ServiceProvider>()?.gradeService;
    if (grades == null) {
      return Scaffold(
        backgroundColor: context.tpColors.canvas,
        appBar: const BlurredAppBar(title: Text('成绩与 GPA')),
        body: const CampusPrerequisiteView(
          icon: TpIcons.trophy,
          title: '成绩与 GPA',
          fallbackText: '请登录并绑定学校账号后查看成绩',
        ),
      );
    }
    return ListenableBuilder(
      listenable: grades,
      builder: (context, _) =>
          _GradesView(key: ValueKey(grades.generation), grades: grades),
    );
  }
}

class _TrialCourseEntry {
  const _TrialCourseEntry(this.id, this.grade);

  final int id;
  final CourseGrade grade;
}

class _GradesView extends StatefulWidget {
  const _GradesView({super.key, required this.grades});
  final GradeService grades;

  @override
  State<_GradesView> createState() => _GradesViewState();
}

class _GradesViewState extends State<_GradesView> {
  final _searchCtrl = TextEditingController();
  GradeScope scope = GradeScope.major;
  bool english = false, busy = false, simulating = false, _showSearch = false;
  String? term, error;
  String _query = '';
  int _request = 0;
  int _nextTrialId = 1;
  final Set<int> _omittedCourseIndices = <int>{};
  final Set<int> _omittedTrialIds = <int>{};
  final List<_TrialCourseEntry> _hypothetical = <_TrialCourseEntry>[];

  @override
  void initState() {
    super.initState();
    if (widget.grades.ready) unawaited(refresh(clearTrial: false));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> refresh({bool clearTrial = false}) async {
    final rev = ++_request;
    setState(() {
      busy = true;
      error = null;
      if (clearTrial) {
        _omittedCourseIndices.clear();
        _omittedTrialIds.clear();
        _hypothetical.clear();
        simulating = false;
      }
    });
    final grades = widget.grades;
    try {
      if (english) {
        if (grades.semesters.isEmpty) await grades.loadEnglishTerms();
        if (!mounted || rev != _request) return;
        term ??= grades.semesters.keys.firstOrNull;
        if (term != null) await grades.loadEnglish(term!);
      } else {
        await grades.refresh(scope);
        if (!mounted || rev != _request) return;
        if (!grades.courses(scope).any((g) => g.semester == term)) {
          term = null;
        }
      }
    } catch (e) {
      if (mounted && rev == _request) {
        error = e is CampusRequestException ? e.message : '成绩读取失败，请重试';
      }
    } finally {
      if (mounted && rev == _request) setState(() => busy = false);
    }
  }

  Future<void> addCourse() async {
    final generation = widget.grades.generation;
    final grade = await showDialog<CourseGrade>(
      context: context,
      builder: (_) => const _TrialDialog(),
    );
    if (grade != null && mounted && generation == widget.grades.generation) {
      setState(() => _hypothetical.add(_TrialCourseEntry(_nextTrialId++, grade)));
    }
  }

  void _resetSimulation() {
    setState(() {
      _omittedCourseIndices.clear();
      _omittedTrialIds.clear();
      _hypothetical.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final service = widget.grades;
    final all = service.courses(scope);
    final query = _query.trim().toLowerCase();
    final termCourses = all.where((g) => term == null || g.semester == term).toList();
    final indexedShown = <(int, CourseGrade)>[
      for (var i = 0; i < termCourses.length; i++)
        if (query.isEmpty ||
            '${termCourses[i].courseName} ${termCourses[i].courseCode} ${termCourses[i].semester}'
                .toLowerCase()
                .contains(query))
          (i, termCourses[i]),
    ];
    final summary = GradeSummary.of(termCourses);
    final activeCourses = simulating
        ? [
            for (var i = 0; i < termCourses.length; i++)
              if (!_omittedCourseIndices.contains(i)) termCourses[i],
            for (final entry in _hypothetical)
              if (!_omittedTrialIds.contains(entry.id)) entry.grade,
          ]
        : termCourses;
    final activeSummary = simulating ? GradeSummary.of(activeCourses) : summary;
    final gpaDelta = (simulating && summary.gpa != null && activeSummary.gpa != null)
        ? activeSummary.gpa! - summary.gpa!
        : null;

    final terms = english
        ? service.semesters
        : {
            for (final g in all)
              if (g.semester.isNotEmpty) g.semester: g.semester,
          };
    final validTermValue = term != null && terms.containsKey(term)
        ? term
        : (english ? null : '');
    final updated = service.updated(scope);
    final theme = Theme.of(context);
    final englishRows = service.english(validTermValue ?? '').where((g) {
      if (query.isEmpty) return true;
      return '${g.exam} ${g.semester} ${g.score}'.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: BlurredAppBar(
        title: const Text('成绩与 GPA'),
        actions: [
          if (!english && service.ready)
            IconButton(
              tooltip: _showSearch ? '收起搜索' : '搜索课程',
              icon: Icon(_showSearch ? TpIcons.close : TpIcons.search),
              onPressed: () => setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchCtrl.clear();
                  _query = '';
                }
              }),
            ),
          PageRefreshButton(
            onRefresh: () => refresh(clearTrial: false),
            enabled: service.ready,
            refreshing: busy,
          ),
          if (!isDesktop())
            IconButton(
              tooltip: '刷新',
              onPressed: busy || !service.ready
                  ? null
                  : () => refresh(clearTrial: false),
              icon: const Icon(TpIcons.refresh),
            ),
        ],
      ),
      body: !service.ready
          ? const CampusPrerequisiteView(
              icon: TpIcons.trophy,
              title: '成绩与 GPA',
              fallbackText: '请登录并绑定学校账号后查看成绩',
            )
          : PageRefreshIndicator(
              onRefresh: () => refresh(clearTrial: false),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  TpTokens.pageHorizontalPadding,
                  TpTokens.space4,
                  TpTokens.pageHorizontalPadding,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  TpPageBody(
                    maxWidth: 880,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: TpTokens.space2,
                          runSpacing: TpTokens.space2,
                          children: [
                            for (final s in GradeScope.values)
                              ChoiceChip(
                                label: Text(s.label),
                                selected: !english && scope == s,
                                onSelected: (_) {
                                  setState(() {
                                    scope = s;
                                    english = false;
                                    term = null;
                                    simulating = false;
                                    _hypothetical.clear();
                                    _omittedCourseIndices.clear();
                                    _omittedTrialIds.clear();
                                  });
                                  unawaited(refresh(clearTrial: true));
                                },
                              ),
                            ChoiceChip(
                              label: const Text('英语成绩'),
                              selected: english,
                              onSelected: (_) {
                                setState(() {
                                  english = true;
                                  term = null;
                                  simulating = false;
                                  _hypothetical.clear();
                                  _omittedCourseIndices.clear();
                                  _omittedTrialIds.clear();
                                });
                                unawaited(refresh(clearTrial: true));
                              },
                            ),
                          ],
                        ),
                        if (!english && _showSearch) ...[
                          const SizedBox(height: TpTokens.space3),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  onChanged: (v) => setState(() => _query = v),
                                  decoration: InputDecoration(
                                    labelText: '搜索课程名称或代码',
                                    prefixIcon: const Icon(TpIcons.search),
                                    suffixIcon: _query.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: '清除搜索',
                                            onPressed: () {
                                              _searchCtrl.clear();
                                              setState(() => _query = '');
                                            },
                                            icon: const Icon(TpIcons.close),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (terms.isNotEmpty) ...[
                          const SizedBox(height: TpTokens.space2),
                          AdaptiveSelect(
                            width: double.infinity,
                            enabled: !busy,
                            value: validTermValue,
                            placeholder: '选择学期',
                            options: [
                              if (!english)
                                const AdaptiveSelectOption(
                                  value: '',
                                  label: '全部学期',
                                ),
                              for (final t in terms.entries)
                                AdaptiveSelectOption(
                                  value: t.key,
                                  label: t.value,
                                ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                term = v.isEmpty ? null : v;
                                _hypothetical.clear();
                                _omittedCourseIndices.clear();
                                _omittedTrialIds.clear();
                              });
                              if (english) unawaited(refresh());
                            },
                          ),
                        ],
                        if (busy) ...[
                          const SizedBox(height: TpTokens.space2),
                          const LinearProgressIndicator(),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: TpTokens.space3),
                          TpStateCard.error(
                            title: '成绩读取失败',
                            message: error,
                            compact: true,
                            onPrimaryAction: () => refresh(clearTrial: false),
                          ),
                        ],
                        if (!english) ...[
                          const SizedBox(height: TpTokens.space3),
                          TpCard(
                            padding: const EdgeInsets.all(TpTokens.space4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      simulating ? '预测 GPA' : '加权 GPA',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    if (gpaDelta != null && gpaDelta.abs() >= 0.005) ...[
                                      const SizedBox(width: TpTokens.space2),
                                      TpBadge(
                                        label:
                                            '${gpaDelta >= 0 ? '+' : ''}${gpaDelta.toStringAsFixed(2)}',
                                        tone: gpaDelta >= 0
                                            ? TpBadgeTone.success
                                            : TpBadgeTone.danger,
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  activeSummary.gpa?.toStringAsFixed(2) ?? '—',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    color: colors.brandInk,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: TpTokens.space1),
                                Text(
                                  '已获 ${activeSummary.earnedCredits} 学分 · 计入 GPA ${activeSummary.gradedCredits} 学分',
                                  style: TpTypography.itemTitle(colors),
                                ),
                                Text(
                                  '${activeSummary.courseCount} 门课程 · ${activeCourses.map((g) => g.semester).where((s) => s.isNotEmpty).toSet().length} 个学期',
                                  style: TpTypography.itemMeta(colors),
                                ),
                                if (updated != null)
                                  Text(
                                    '更新于 ${DateFormat('yyyy-MM-dd HH:mm').format(updated.toLocal())}',
                                    style: TpTypography.itemMeta(colors),
                                  ),
                                const Divider(height: TpTokens.space5),
                                AdaptiveSwitchRow(
                                  title: '本地 GPA 试算',
                                  value: simulating,
                                  onChanged: (v) => setState(() {
                                    simulating = v;
                                    _omittedCourseIndices.clear();
                                    _omittedTrialIds.clear();
                                    _hypothetical.clear();
                                  }),
                                ),
                                if (simulating)
                                  Wrap(
                                    spacing: TpTokens.space2,
                                    children: [
                                      TextButton.icon(
                                        onPressed: addCourse,
                                        icon: const Icon(TpIcons.add),
                                        label: const Text('添加假设课程'),
                                      ),
                                      if (_hypothetical.isNotEmpty ||
                                          _omittedCourseIndices.isNotEmpty)
                                        TextButton.icon(
                                          onPressed: _resetSimulation,
                                          icon: const Icon(TpIcons.reset),
                                          label: const Text('重置试算'),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: TpTokens.space3),
                          if (indexedShown.isEmpty &&
                              _hypothetical.isEmpty &&
                              !busy &&
                              error == null)
                            const TpStateCard.empty(
                              icon: TpIcons.trophy,
                              title: '暂无课程成绩',
                              compact: true,
                            ),
                          if (indexedShown.isNotEmpty || _hypothetical.isNotEmpty)
                            TpCard(
                              child: Column(
                                children: [
                                  for (final (idx, g) in indexedShown)
                                    _gradeRow(
                                      context,
                                      grade: g,
                                      simulating: simulating,
                                      included:
                                          !_omittedCourseIndices.contains(idx),
                                      onToggle: () => setState(() {
                                        if (!_omittedCourseIndices.remove(idx)) {
                                          _omittedCourseIndices.add(idx);
                                        }
                                      }),
                                    ),
                                  for (final entry in _hypothetical)
                                    _gradeRow(
                                      context,
                                      grade: entry.grade,
                                      simulating: simulating,
                                      included:
                                          !_omittedTrialIds.contains(entry.id),
                                      onToggle: () => setState(() {
                                        if (!_omittedTrialIds.remove(entry.id)) {
                                          _omittedTrialIds.add(entry.id);
                                        }
                                      }),
                                      onDelete: () => setState(() {
                                        _omittedTrialIds.remove(entry.id);
                                        _hypothetical.removeWhere(
                                          (e) => e.id == entry.id,
                                        );
                                      }),
                                    ),
                                ],
                              ),
                            ),
                        ] else ...[
                          const SizedBox(height: TpTokens.space3),
                          if (englishRows.isEmpty && !busy && error == null)
                            const TpStateCard.empty(
                              icon: TpIcons.trophy,
                              title: '该学期暂无英语成绩',
                              compact: true,
                            ),
                          if (englishRows.isNotEmpty)
                            TpCard(
                              child: Column(
                                children: [
                                  for (final g in englishRows)
                                    ListTile(
                                      title: Text(g.exam),
                                      subtitle: Text(
                                        [g.semester, g.status]
                                            .where((s) => s.isNotEmpty)
                                            .join(' · '),
                                      ),
                                      trailing: TpBadge(
                                        label: g.score,
                                        tone: TpBadgeTone.brand,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _gradeRow(
    BuildContext context, {
    required CourseGrade grade,
    required bool simulating,
    required bool included,
    required VoidCallback onToggle,
    VoidCallback? onDelete,
  }) {
    final colors = context.tpColors;
    return ListTile(
      leading: simulating
          ? AdaptiveCheckbox(
              value: included,
              semanticLabel: grade.courseName,
              onChanged: (_) => onToggle(),
            )
          : null,
      title: Row(
        children: [
          Expanded(child: Text(grade.courseName)),
          if (grade.isRetake) ...[
            const SizedBox(width: TpTokens.space2),
            const TpBadge(label: '重修/补考', tone: TpBadgeTone.warning),
          ],
        ],
      ),
      subtitle: Text(
        [
          grade.semester,
          grade.courseCode,
          grade.courseType,
          '${grade.credits} 学分',
          if (grade.isRetake) '重修／补考',
          if (grade.passed != null) grade.passed! ? '通过' : '未通过',
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              grade.scoreText,
              if (grade.gradePoint != null) '绩点 ${grade.gradePoint}',
            ].where((s) => s.isNotEmpty).join('\n'),
            textAlign: TextAlign.end,
            style: TpTypography.itemTitle(colors).copyWith(
              color: grade.passed == false
                  ? colors.dangerRed
                  : colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: TpTokens.space1),
            IconButton(
              tooltip: '移除假设课程',
              icon: const Icon(TpIcons.delete, size: TpTokens.iconS),
              onPressed: onDelete,
            ),
          ],
        ],
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
  static const _gpaPresets = <double>[4.0, 3.7, 3.3, 3.0, 2.7, 2.3, 2.0];
  final _pointCtrl = TextEditingController();
  double? credits, point;
  String _courseName = '';

  @override
  void dispose() {
    _pointCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      credits?.isFinite == true &&
      credits! > 0 &&
      point?.isFinite == true &&
      point! >= 0 &&
      point! <= 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return AlertDialog(
      scrollable: true,
      title: const Text('添加假设课程'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '学分'),
              onChanged: (v) => setState(() => credits = double.tryParse(v.trim())),
            ),
          ),
          TextField(
            controller: _pointCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '预期绩点',
              helperText: '请输入 0.0 - 4.0 之间的绩点',
            ),
            onChanged: (v) => setState(() => point = double.tryParse(v.trim())),
          ),
          const SizedBox(height: TpTokens.space2),
          Wrap(
            spacing: TpTokens.space1,
            runSpacing: TpTokens.space1,
            children: [
              for (final preset in _gpaPresets)
                ChoiceChip(
                  label: Text(preset.toStringAsFixed(1)),
                  selected: point == preset,
                  onSelected: (_) => setState(() {
                    point = preset;
                    _pointCtrl.text = preset.toStringAsFixed(1);
                  }),
                ),
            ],
          ),
          const SizedBox(height: TpTokens.space3),
          TextField(
            decoration: const InputDecoration(labelText: '课程名称（选填）'),
            onChanged: (v) => _courseName = v.trim(),
          ),
          if ((credits != null || point != null) && !_valid) ...[
            const SizedBox(height: TpTokens.space2),
            Text(
              '请填写大于 0 的学分和 0–4 范围内的预期绩点',
              style: TpTypography.itemMeta(colors).copyWith(
                color: colors.dangerRed,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop(
                    context,
                    CourseGrade(
                      semester: '',
                      courseCode: '',
                      courseName:
                          _courseName.isEmpty ? '假设课程' : _courseName,
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
}
