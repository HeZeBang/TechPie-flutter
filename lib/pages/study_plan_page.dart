import 'dart:async';

import 'package:flutter/material.dart';

import '../models/study_plan.dart';
import '../services/campus/campus_file_share.dart';
import '../services/service_provider.dart';
import '../services/study_plan_service.dart';

class StudyPlanPage extends StatefulWidget {
  const StudyPlanPage({super.key, this.service});
  final StudyPlanService? service;
  @override
  State<StudyPlanPage> createState() => _StudyPlanPageState();
}

class _StudyPlanPageState extends State<StudyPlanPage> {
  StudyPlanService? _service;
  var _full = false, _unfinished = false, _busy = false, _exporting = false;
  String _query = '';
  String? _error;
  int _request = 0, _accountRevision = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = widget.service ?? ServiceProvider.of(context).studyPlanService;
    if (_service == service) return;
    _service?.removeListener(_changed);
    _service = service?..addListener(_changed);
    _accountRevision = service?.accountRevision ?? 0;
    unawaited(_load());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_service!.accountRevision != _accountRevision) {
      _accountRevision = _service!.accountRevision;
      unawaited(_load());
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final revision = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service!.load(full: _full, refresh: refresh);
    } catch (e) {
      if (mounted && revision == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && revision == _request) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final bytes = await _service!.exportPdf();
      final result = await CampusFileShare.openOrShare(
        scope: 'study_plan',
        filename: 'study-plan.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      final message = switch (result.status) {
        CampusFileOpenStatus.opened => '已打开培养计划 PDF',
        CampusFileOpenStatus.shared => '已打开或分享培养计划 PDF',
        CampusFileOpenStatus.downloaded => '已开始下载培养计划 PDF',
        CampusFileOpenStatus.savedOnly => '已保存到 ${result.path ?? '本地'}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _service?.cached(full: _full);
    final summary = _service?.cached(full: false);
    final modules =
        summary?.categories.expand((c) => c.descendants).where((c) => c.met != null).toList() ?? [];
    final statuses = <String, PlanCourseStatus>{
      if (_full && summary != null)
        for (final root in summary.categories)
          for (final group in root.descendants)
            for (final course in group.courses) course.code: course.status,
    };
    final tiles =
        plan?.categories.map((c) => _tile(c, statuses)).whereType<Widget>().toList() ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('培养计划'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () => _load(refresh: true),
          ),
          IconButton(
            tooltip: '导出 PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exporting || _service == null ? null : _export,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (summary != null && summary.categories.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已完成 ${_n(summary.completed)} / ${_n(summary.requiredCredits)} 学分',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (summary.completionPercent case final percent?) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (percent / 100).clamp(0, 1),
                          semanticsLabel: '学分完成度',
                        ),
                      ],
                      if (modules.isNotEmpty)
                        Text(
                          '达标模块 ${modules.where((m) => m.met == true).length} / ${modules.length}',
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('完成进度')),
                  ButtonSegment(value: true, label: Text('完整方案')),
                ],
                selected: {_full},
                onSelectionChanged: (next) {
                  setState(() => _full = next.single);
                  unawaited(_load());
                },
              ),
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: '搜索模块、课程名或代码',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅看未完成'),
              value: _unfinished,
              onChanged: (v) => setState(() => _unfinished = v),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _load(refresh: true),
                  child: const Text('重试'),
                ),
              ),
            if (plan != null && tiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(plan.categories.isEmpty ? '当前账号暂无培养计划' : '没有符合条件的课程或模块'),
              ),
            ...tiles,
          ],
        ),
      ),
    );
  }

  Widget? _tile(
    PlanCategoryProgress group,
    Map<String, PlanCourseStatus> statuses, {
    bool parentMatches = false,
  }) {
    PlanCourseStatus status(PlanCourseItem course) => statuses[course.code] ?? course.status;
    final matches = parentMatches || group.name.toLowerCase().contains(_query);
    final children = group.children
        .map((c) => _tile(c, statuses, parentMatches: matches))
        .whereType<Widget>()
        .toList();
    final courses = group.courses.where(
      (c) =>
          (!_unfinished || status(c) != PlanCourseStatus.passed) &&
          (matches || '${c.name} ${c.code}'.toLowerCase().contains(_query)),
    );
    if (children.isEmpty &&
        courses.isEmpty &&
        (!matches ||
            (_unfinished &&
                (group.met == true || group.courses.isNotEmpty || group.children.isNotEmpty)))) {
      return null;
    }
    return ExpansionTile(
      key: PageStorageKey((_full, group.depth, group.name, _query)),
      initiallyExpanded: _query.isNotEmpty,
      title: Text(group.name),
      subtitle: group.requiredCredits == null
          ? null
          : Text(
              '完成 ${_n(group.completed)} / ${_n(group.requiredCredits)} 学分${group.actual == null ? '' : ' · 实修 ${_n(group.actual)}'}',
            ),
      children: [
        ...children,
        for (final c in courses)
          ListTile(
            title: Text(c.name),
            subtitle: Text(
              [
                c.code,
                if (c.credits != null) '${_n(c.credits)} 学分',
                if (c.term.isNotEmpty) c.term,
                if (c.requiredCourse != null) c.requiredCourse! ? '必修' : '选修',
                if (c.department.isNotEmpty) c.department,
                if (status(c) != PlanCourseStatus.unknown) status(c).label,
              ].join(' · '),
            ),
          ),
      ],
    );
  }

  String _n(double? n) => n == null
      ? '—'
      : n == n.roundToDouble()
      ? n.round().toString()
      : n.toString();
}
