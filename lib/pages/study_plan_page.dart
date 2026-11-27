import 'dart:async';

import 'package:flutter/material.dart';

import '../models/study_plan.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/campus_file_share.dart';
import '../services/service_provider.dart';
import '../services/study_plan_service.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/page_refresh.dart';

class StudyPlanPage extends StatefulWidget {
  const StudyPlanPage({super.key, this.service});
  final StudyPlanService? service;

  @override
  State<StudyPlanPage> createState() => _StudyPlanPageState();
}

class _StudyPlanPageState extends State<StudyPlanPage> {
  final _searchCtrl = TextEditingController();
  StudyPlanService? _service;
  var _full = false, _unfinished = false, _busy = false, _exporting = false;
  String _query = '';
  String? _error;
  int _request = 0, _accountRevision = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _service?.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = widget.service ??
        context
            .dependOnInheritedWidgetOfExactType<ServiceProvider>()
            ?.studyPlanService;
    if (_service == service) return;
    _service?.removeListener(_changed);
    _service = service?..addListener(_changed);
    _accountRevision = service?.accountRevision ?? 0;
    if (_isReady(service)) {
      unawaited(_load());
    }
  }

  bool _isReady(StudyPlanService? service) {
    if (service == null) return false;
    final id = service.account();
    return id.user?.isNotEmpty == true && id.ids?.isNotEmpty == true;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_service != null && _service!.accountRevision != _accountRevision) {
      _accountRevision = _service!.accountRevision;
      if (_isReady(_service)) {
        unawaited(_load());
      } else {
        setState(() {
          _busy = false;
          _error = null;
        });
      }
    }
  }

  String _friendlyError(Object e) => switch (e) {
        CampusRequestException(:final message) => message,
        FormatException(:final message) => message,
        _ => '培养计划读取失败，请重试',
      };

  Future<void> _load({bool refresh = false}) async {
    final service = _service;
    if (!_isReady(service)) return;
    final revision = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await service!.load(full: _full, refresh: refresh);
      if (_full && service.cached(full: false) == null) {
        try {
          await service.load(full: false);
        } catch (_) {
          // Summary card is supplemental when viewing the full plan.
        }
      }
    } catch (e) {
      if (mounted && revision == _request) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted && revision == _request) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final service = _service;
    if (service == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await service.exportPdf();
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
      showAdaptiveFeedback(
        context: context,
        message: message,
        style: CampusFileOpenStatus.savedOnly == result.status ||
                result.succeeded
            ? AdaptiveFeedbackStyle.success
            : AdaptiveFeedbackStyle.info,
      );
    } catch (e) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: _friendlyError(e),
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static int _statusRank(PlanCourseStatus s) => switch (s) {
        PlanCourseStatus.passed => 4,
        PlanCourseStatus.studying => 3,
        PlanCourseStatus.failed => 2,
        PlanCourseStatus.pending => 1,
        PlanCourseStatus.unknown => 0,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final ready = _isReady(_service);
    final plan = _service?.cached(full: _full);
    final summary = _service?.cached(full: false);
    final modules = summary?.categories
            .expand((c) => c.descendants)
            .where((c) => c.met != null)
            .toList() ??
        [];
    final statuses = <String, PlanCourseStatus>{};
    if (_full && summary != null) {
      for (final root in summary.categories) {
        for (final group in root.descendants) {
          for (final course in group.courses) {
            final current = statuses[course.code];
            if (current == null ||
                _statusRank(course.status) > _statusRank(current)) {
              statuses[course.code] = course.status;
            }
          }
        }
      }
    }
    final tiles =
        plan?.categories.map((c) => _tile(context, c, statuses)).whereType<Widget>().toList() ??
            [];
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: BlurredAppBar(
        title: const Text('培养计划'),
        actions: [
          PageRefreshButton(
            onRefresh: () => _load(refresh: true),
            enabled: ready,
            refreshing: _busy,
          ),
          if (!isDesktop())
            IconButton(
              tooltip: '刷新',
              icon: const Icon(TpIcons.refresh),
              onPressed: _busy || !ready ? null : () => _load(refresh: true),
            ),
          IconButton(
            tooltip: '导出 PDF',
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(TpIcons.document),
            onPressed: _exporting || !ready ? null : _export,
          ),
        ],
      ),
      body: !ready
          ? const CampusPrerequisiteView(
              icon: TpIcons.studyPlan,
              title: '培养计划',
              fallbackText: '请登录并绑定 IDS 后查看培养计划',
            )
          : PageRefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  TpTokens.pageHorizontalPadding,
                  topInset + TpTokens.space4,
                  TpTokens.pageHorizontalPadding,
                  AppShellMetrics.bottomContentPaddingOf(context),
                ),
                children: [
                  TpPageBody(
                    maxWidth: 880,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (summary != null && summary.categories.isNotEmpty) ...[
                          TpCard(
                            padding: const EdgeInsets.all(TpTokens.space4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '已完成 ${_n(summary.completed)} / ${_n(summary.requiredCredits)} 学分',
                                  style: TpTypography.cardTitle(colors),
                                ),
                                if (summary.completionPercent case final percent?) ...[
                                  const SizedBox(height: TpTokens.space2),
                                  LinearProgressIndicator(
                                    value: (percent / 100).clamp(0, 1),
                                    semanticsLabel: '学分完成度',
                                  ),
                                ],
                                if (modules.isNotEmpty) ...[
                                  const SizedBox(height: TpTokens.space2),
                                  Text(
                                    '达标模块 ${modules.where((m) => m.met == true).length} / ${modules.length}',
                                    style: TpTypography.itemMeta(colors),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: TpTokens.space3),
                        ],
                        SegmentedButton<bool>(
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
                        const SizedBox(height: TpTokens.space3),
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            labelText: '搜索模块、课程名或代码',
                            prefixIcon: const Icon(TpIcons.search),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: '清除搜索',
                                    icon: const Icon(TpIcons.close),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) =>
                              setState(() => _query = v.trim().toLowerCase()),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('仅看未完成'),
                          value: _unfinished,
                          onChanged: (v) => setState(() => _unfinished = v),
                        ),
                        if (_busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: TpTokens.space2),
                        ],
                        if (_error != null) ...[
                          TpStateCard.error(
                            title: '培养计划读取失败',
                            message: _error,
                            compact: true,
                            onPrimaryAction: () => _load(refresh: true),
                          ),
                          const SizedBox(height: TpTokens.space3),
                        ],
                        if (plan != null && tiles.isEmpty)
                          TpStateCard.empty(
                            icon: TpIcons.studyPlan,
                            title: plan.categories.isEmpty
                                ? '当前账号暂无培养计划'
                                : '没有符合条件的课程或模块',
                            compact: true,
                          ),
                        for (final tile in tiles)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: TpTokens.space2,
                            ),
                            child: TpCard(child: tile),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget? _tile(
    BuildContext context,
    PlanCategoryProgress group,
    Map<String, PlanCourseStatus> statuses, {
    bool parentMatches = false,
  }) {
    PlanCourseStatus status(PlanCourseItem course) =>
        statuses[course.code] ?? course.status;
    final matches = parentMatches || group.name.toLowerCase().contains(_query);
    final children = group.children
        .map((c) => _tile(context, c, statuses, parentMatches: matches))
        .whereType<Widget>()
        .toList();
    final courses = group.courses
        .where(
          (c) =>
              (!_unfinished || status(c) != PlanCourseStatus.passed) &&
              (matches ||
                  '${c.name} ${c.code}'.toLowerCase().contains(_query)),
        )
        .toList();
    if (children.isEmpty &&
        courses.isEmpty &&
        (!matches ||
            (_unfinished &&
                (group.met == true ||
                    group.courses.isNotEmpty ||
                    group.children.isNotEmpty)))) {
      return null;
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
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
                  if (c.requiredCourse != null)
                    c.requiredCourse! ? '必修' : '选修',
                  if (c.department.isNotEmpty) c.department,
                ].join(' · '),
              ),
              trailing: status(c) == PlanCourseStatus.unknown
                  ? null
                  : TpBadge(
                      label: status(c).label,
                      tone: switch (status(c)) {
                        PlanCourseStatus.passed => TpBadgeTone.success,
                        PlanCourseStatus.studying => TpBadgeTone.info,
                        PlanCourseStatus.failed => TpBadgeTone.danger,
                        PlanCourseStatus.pending => TpBadgeTone.warning,
                        PlanCourseStatus.unknown => TpBadgeTone.muted,
                      },
                    ),
            ),
        ],
      ),
    );
  }

  String _n(double? n) => n == null
      ? '—'
      : n == n.roundToDouble()
          ? n.round().toString()
          : n.toString();
}
