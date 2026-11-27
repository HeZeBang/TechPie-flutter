import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/academic_certificate.dart';
import '../../models/campus_job.dart';
import '../../models/course.dart';
import '../../models/elearning_models.dart';
import '../../models/feature.dart';
import '../../models/grade_record.dart';
import '../../models/holiday_travel.dart';
import '../../models/home_layout.dart';
import '../../models/oa_gym.dart';
import '../../models/pnp_and_minor.dart';
import '../../models/student_allowance.dart';
import '../../models/student_leave.dart';
import '../../models/study_plan.dart';
import '../../pages/campus_feature_navigation.dart';
import '../../pages/elearning_hub_page.dart';
import '../../services/academic_certificate_service.dart';
import '../../services/campus/campus_errors.dart';
import '../../services/campus_job_service.dart';
import '../../services/egate_app_service.dart';
import '../../services/grade_service.dart';
import '../../services/oa_gym_service.dart';
import '../../services/pnp_minor_service.dart';
import '../../services/service_provider.dart';
import '../../services/student_allowance_service.dart';
import '../../services/study_plan_service.dart';
import '../../theme/theme.dart';
import '../adaptive_progress_indicator.dart';
import '../design_system/design_system.dart';
import 'home_widget_chrome.dart';

/// Renders the Home dashboard widget for any customizable Campus Service [id].
///
/// All widgets read existing caches immediately without automatic network calls
/// on mount, only refreshing when the user explicitly taps a card's refresh
/// action, and clear ephemeral account-bound state on logout or switch.
Widget buildCampusServiceHomeWidget(
  BuildContext context,
  HomeWidgetId id, {
  List<Course> todayCourses = const [],
}) =>
    switch (id) {
      HomeWidgetId.campusGrades => const _GradesHomeWidget(),
      HomeWidgetId.campusStudyPlan => const _StudyPlanHomeWidget(),
      HomeWidgetId.campusBlackboard => const _BlackboardHomeWidget(),
      HomeWidgetId.campusElrcRecordings =>
        _ElrcRecordingsHomeWidget(todayCourses: todayCourses),
      HomeWidgetId.campusEcourse => const _EcourseHomeWidget(),
      HomeWidgetId.campusCourseCatalog => const _CourseCatalogHomeWidget(),
      HomeWidgetId.campusCertificates => const _CertificatesHomeWidget(),
      HomeWidgetId.campusOaGym => const _OaGymHomeWidget(),
      HomeWidgetId.campusStudentLeave => const _StudentLeaveHomeWidget(),
      HomeWidgetId.campusHolidayTravel => const _HolidayTravelHomeWidget(),
      HomeWidgetId.campusActivities => const _ActivitiesHomeWidget(),
      HomeWidgetId.campusJobs => const _JobsHomeWidget(),
      HomeWidgetId.campusStudentAllowance => const _StudentAllowanceHomeWidget(),
      HomeWidgetId.campusPnpMinor => const _PnpMinorHomeWidget(),
      _ => const SizedBox.shrink(),
    };

Feature? _findFeatureById(String featureId) {
  for (final feature in featureEntries) {
    if (feature.id == featureId) return feature;
  }
  return null;
}

void _openCampusWidgetFeature(BuildContext context, HomeWidgetId id) {
  final featureId = homeWidgetMetaFor(id).featureId;
  if (featureId == null) return;
  final feature = _findFeatureById(featureId);
  if (feature == null) return;
  unawaited(openCampusFeature(context, feature));
}

String _friendlyError(Object error) => switch (error) {
      CampusRequestException(:final message) => message,
      EgateAppException(:final message) => message,
      StudentAllowanceException(:final message) => message,
      OaGymException(:final message) => message,
      FormatException(:final message) when message.trim().isNotEmpty => message,
      _ => '刷新失败，点击进入查看详情',
    };

String _formatCredit(double? value) {
  if (value == null) return '—';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

TpBadgeTone _statusBadgeTone(String status) {
  if (status.contains('通过') ||
      status.contains('同意') ||
      status.contains('已确认') ||
      status.contains('完成') ||
      status.contains('可用') ||
      status.contains('开放')) {
    return TpBadgeTone.success;
  }
  if (status.contains('驳回') ||
      status.contains('拒绝') ||
      status.contains('不通过') ||
      status.contains('退回') ||
      status.contains('关闭')) {
    return TpBadgeTone.danger;
  }
  if (status.contains('待') || status.contains('审核') || status.contains('草稿')) {
    return TpBadgeTone.warning;
  }
  return TpBadgeTone.info;
}

String _compactNoticeText(ServiceProvider sp) {
  if (!sp.authService.isLoggedIn) return '登录 TechPie 后可查看实时数据';
  if (!sp.thirdPartyAuthService.hasIdsBinding) return '绑定校园 IDS 账号后可查看';
  return '暂未缓存数据，点击进入查看或刷新';
}

class _CampusServiceCard extends StatelessWidget {
  const _CampusServiceCard({
    required this.id,
    required this.child,
    this.badge,
    this.loading = false,
    this.errorText,
    this.onRefresh,
  });

  final HomeWidgetId id;
  final Widget child;
  final Widget? badge;
  final bool loading;
  final String? errorText;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final meta = homeWidgetMetaFor(id);

    return TpCard(
      key: ValueKey('home.widget-${id.key}'),
      title: meta.title,
      leadingIcon: homeWidgetIcon(id),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) badge!,
          if (onRefresh != null) ...[
            if (badge != null) const SizedBox(width: TpTokens.space1),
            SizedBox(
              width: 28,
              height: 28,
              child: loading
                  ? const Center(child: AdaptiveActivityIndicator(size: 16))
                  : IconButton(
                      key: ValueKey('home.widget-refresh-${id.key}'),
                      tooltip: '刷新${meta.title}',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 28, height: 28),
                      icon: Icon(
                        TpIcons.refresh,
                        size: TpTokens.iconXs,
                        color: colors.textSecondary,
                      ),
                      onPressed: onRefresh,
                    ),
            ),
          ] else ...[
            if (badge != null) const SizedBox(width: TpTokens.space1),
            Icon(
              TpIcons.chevronRight,
              size: TpTokens.iconS,
              color: colors.textMuted,
            ),
          ],
        ],
      ),
      onTap: () => _openCampusWidgetFeature(context, id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TpTokens.cardPaddingHorizontal,
                0,
                TpTokens.cardPaddingHorizontal,
                TpTokens.space2,
              ),
              child: Text(
                errorText!,
                style: TpTypography.itemMeta(colors).copyWith(
                  color: colors.dangerRed,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _CompactPromptBody extends StatelessWidget {
  const _CompactPromptBody({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TpTokens.cardPaddingHorizontal,
        TpTokens.space1,
        TpTokens.cardPaddingHorizontal,
        TpTokens.space4,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(TpTokens.radiusS),
            ),
            child: Icon(icon, size: TpTokens.iconS, color: colors.textMuted),
          ),
          const SizedBox(width: TpTokens.space3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TpTypography.itemTitle(colors).copyWith(fontSize: 13.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TpTypography.itemMeta(colors),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCell extends StatelessWidget {
  const _KpiCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TpTypography.itemMeta(colors)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TpTypography.numericDisplay(colors).copyWith(fontSize: 18),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _GradesHomeWidget extends StatefulWidget {
  const _GradesHomeWidget();

  @override
  State<_GradesHomeWidget> createState() => _GradesHomeWidgetState();
}

class _GradesHomeWidgetState extends State<_GradesHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh(GradeService service) async {
    if (_loading) return;
    final gen = service.generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refresh(GradeScope.all);
    } catch (e) {
      if (mounted && gen == service.generation) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.gradeService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null && service.ready;
        final allCourses = ready ? service.courses(GradeScope.all) : const <CourseGrade>[];
        final courses = allCourses.isNotEmpty
            ? allCourses
            : (ready ? service.courses(GradeScope.major) : const <CourseGrade>[]);
        final summary = courses.isEmpty ? null : GradeSummary.of(courses);
        final preview = courses.take(2).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusGrades,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(service)) : null,
          badge: summary?.gpa != null
              ? TpBadge(
                  label: 'GPA ${summary!.gpa!.toStringAsFixed(2)}',
                  tone: TpBadgeTone.brand,
                )
              : null,
          child: !ready || summary == null
              ? _CompactPromptBody(
                  icon: TpIcons.trophy,
                  title: ready ? '暂无缓存成绩' : '需要教务登录态',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space1,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space2,
                        ),
                        child: Row(
                          children: [
                            _KpiCell(
                              label: '平均绩点',
                              value: summary.gpa?.toStringAsFixed(2) ?? '—',
                            ),
                            _KpiCell(
                              label: '已获学分',
                              value: _formatCredit(summary.earnedCredits),
                            ),
                            _KpiCell(
                              label: '课程数',
                              value: '${summary.courseCount}',
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].courseName,
                          subtitle:
                              '${preview[i].semester} · ${_formatCredit(preview[i].credits)} 学分',
                          trailing: preview[i].scoreText.isEmpty
                              ? null
                              : TpBadge(
                                  label: preview[i].scoreText,
                                  tone: preview[i].passed == true
                                      ? TpBadgeTone.success
                                      : TpBadgeTone.muted,
                                ),
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _StudyPlanHomeWidget extends StatefulWidget {
  const _StudyPlanHomeWidget();

  @override
  State<_StudyPlanHomeWidget> createState() => _StudyPlanHomeWidgetState();
}

class _StudyPlanHomeWidgetState extends State<_StudyPlanHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh(StudyPlanService service) async {
    if (_loading) return;
    final rev = service.accountRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.load(full: false, refresh: true);
    } catch (e) {
      if (mounted && rev == service.accountRevision) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.studyPlanService;
    final colors = context.tpColors;

    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null &&
            sp.authService.isLoggedIn &&
            sp.thirdPartyAuthService.hasIdsBinding;
        final StudyPlanSnapshot? snapshot = ready
            ? (service.cached(full: false) ?? service.cached(full: true))
            : null;
        final pct = snapshot?.completionPercent;
        final categories = snapshot?.categories.take(3).toList() ?? const [];

        return _CampusServiceCard(
          id: HomeWidgetId.campusStudyPlan,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(service)) : null,
          badge: pct == null
              ? null
              : TpBadge(
                  label: '${pct.toStringAsFixed(0)}%',
                  tone: pct >= 100 ? TpBadgeTone.success : TpBadgeTone.brand,
                ),
          child: snapshot == null
              ? _CompactPromptBody(
                  icon: TpIcons.studyPlan,
                  title: ready ? '暂无培养计划缓存' : '需要绑定校园 IDS',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space1,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space2,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '已修 ${_formatCredit(snapshot.completed)} / ${_formatCredit(snapshot.requiredCredits)} 学分',
                              style: TpTypography.itemMeta(colors),
                            ),
                            if (pct != null) ...[
                              const SizedBox(height: TpTokens.space2),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(TpTokens.radiusPill),
                                child: LinearProgressIndicator(
                                  value: (pct / 100).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: colors.surfaceSubtle,
                                  color: colors.brand,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      for (var i = 0; i < categories.length; i++)
                        TpListRow(
                          title: categories[i].name,
                          subtitle:
                              '已修 ${_formatCredit(categories[i].completed)} / ${_formatCredit(categories[i].requiredCredits)} 学分',
                          trailing: categories[i].met == null
                              ? null
                              : TpBadge(
                                  label: categories[i].met! ? '已达标' : '进行中',
                                  tone: categories[i].met!
                                      ? TpBadgeTone.success
                                      : TpBadgeTone.muted,
                                ),
                          showDivider: i < categories.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _BlackboardHomeWidget extends StatefulWidget {
  const _BlackboardHomeWidget();

  @override
  State<_BlackboardHomeWidget> createState() => _BlackboardHomeWidgetState();
}

class _BlackboardHomeWidgetState extends State<_BlackboardHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh(ServiceProvider sp) async {
    final blackboard = sp.campusClients?.blackboard;
    if (_loading || blackboard == null) return;
    final identity = blackboard.client.session.identity();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await blackboard.courses(refresh: true);
      if (!mounted || blackboard.client.session.identity() != identity) return;
      await blackboard.announcements();
    } catch (e) {
      if (mounted && blackboard.client.session.identity() == identity) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final colors = context.tpColors;

    return ListenableBuilder(
      listenable: Listenable.merge([sp.authService, sp.thirdPartyAuthService]),
      builder: (context, _) {
        final blackboard = sp.campusClients?.blackboard;
        final ready = blackboard != null &&
            sp.authService.isLoggedIn &&
            sp.thirdPartyAuthService.hasIdsBinding;
        final courses = ready ? blackboard.cachedCourses : const <BlackboardCourse>[];
        final announcements = ready
            ? blackboard.cachedAnnouncements
            : const <BlackboardAnnouncement>[];
        final topTerm = courses.isNotEmpty && courses.first.term.isNotEmpty
            ? courses.first.term
            : null;
        final preview = courses.take(3).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusBlackboard,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(sp)) : null,
          badge: topTerm != null
              ? TpBadge(label: topTerm, tone: TpBadgeTone.info)
              : (courses.isNotEmpty
                  ? TpBadge(
                      label: '${courses.length} 门',
                      tone: TpBadgeTone.muted,
                    )
                  : null),
          child: courses.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.graduation,
                  title: ready ? '暂无 Blackboard 缓存课程' : '需要绑定校园 IDS',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].name,
                          subtitle: [
                            if (preview[i].term.isNotEmpty) preview[i].term,
                            if (preview[i].code.isNotEmpty) preview[i].code,
                          ].join(' · '),
                          showChevron: true,
                          showDivider:
                              i < preview.length - 1 || announcements.isNotEmpty,
                          onTap: () {
                            if (blackboard == null) return;
                            unawaited(
                              openBlackboardCourse(
                                context,
                                blackboard,
                                preview[i],
                              ),
                            );
                          },
                        ),
                      if (announcements.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            TpTokens.cardPaddingHorizontal,
                            TpTokens.space2,
                            TpTokens.cardPaddingHorizontal,
                            TpTokens.space1,
                          ),
                          child: Text(
                            '最新公告：${announcements.first.title}',
                            style: TpTypography.itemMeta(colors),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _ElrcRecordingsHomeWidget extends StatelessWidget {
  const _ElrcRecordingsHomeWidget({required this.todayCourses});

  final List<Course> todayCourses;

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([sp.authService, sp.thirdPartyAuthService]),
      builder: (context, _) {
        final ready =
            sp.authService.isLoggedIn && sp.thirdPartyAuthService.hasIdsBinding;
        final preview = todayCourses.take(2).toList();
        return _CampusServiceCard(
          id: HomeWidgetId.campusElrcRecordings,
          badge: TpBadge(
            label: ready ? 'IDS 已就绪' : '需绑定 IDS',
            tone: ready ? TpBadgeTone.success : TpBadgeTone.warning,
          ),
          child: !ready || preview.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.recordings,
                  title: ready ? '按课程查找和播放录播' : '需要绑定校园 IDS',
                  subtitle: ready
                      ? '支持按课程筛选课堂回放与倍速播放'
                      : _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          icon: TpIcons.recordings,
                          title: preview[i].name,
                          subtitle: preview[i].timeLabel,
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _EcourseHomeWidget extends StatelessWidget {
  const _EcourseHomeWidget();

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([sp.authService, sp.thirdPartyAuthService]),
      builder: (context, _) {
        final ready =
            sp.authService.isLoggedIn && sp.thirdPartyAuthService.hasIdsBinding;
        return _CampusServiceCard(
          id: HomeWidgetId.campusEcourse,
          badge: TpBadge(
            label: ready ? '免密直达' : '需绑定 IDS',
            tone: ready ? TpBadgeTone.info : TpBadgeTone.warning,
          ),
          child: _CompactPromptBody(
            icon: TpIcons.classroom,
            title: ready ? '打开 E 云课堂' : '绑定 IDS 后可免密进入',
            subtitle: '自动注入登录态浏览课程资源与回放',
          ),
        );
      },
    );
  }
}

class _CourseCatalogHomeWidget extends StatelessWidget {
  const _CourseCatalogHomeWidget();

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.courseCatalog;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null && service.owner != null;
        final history = ready ? service.history : const <String>[];
        final recent = history.take(4).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusCourseCatalog,
          badge: history.isEmpty
              ? null
              : TpBadge(
                  label: '${history.length} 条历史',
                  tone: TpBadgeTone.muted,
                ),
          child: recent.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.course,
                  title: ready ? '检索本科课程目录' : '需要绑定校园 IDS',
                  subtitle: ready
                      ? '按课程代码、名称、院系与教师检索'
                      : _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space1,
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: TpTokens.space2,
                        runSpacing: TpTokens.space2,
                        children: [
                          for (final keyword in recent)
                            TpBadge(label: keyword, tone: TpBadgeTone.info),
                        ],
                      ),
                      const SizedBox(height: TpTokens.space2),
                      Text(
                        '近期搜索关键词 · 点击进入课程目录',
                        style: TpTypography.itemMeta(context.tpColors),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _CertificatesHomeWidget extends StatefulWidget {
  const _CertificatesHomeWidget();

  @override
  State<_CertificatesHomeWidget> createState() =>
      _CertificatesHomeWidgetState();
}

class _CertificatesHomeWidgetState extends State<_CertificatesHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh(AcademicCertificateService service) async {
    if (_loading) return;
    final gen = service.generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refresh(CertificateKind.transcript);
      if (!mounted || gen != service.generation) return;
      await service.refresh(CertificateKind.ranking);
    } catch (e) {
      if (mounted && gen == service.generation) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _subtitleFor(AcademicCertificate cert) {
    final fields = cert.fields;
    final candidates = [
      fields['学年学期'],
      fields['申请状态'] ?? fields['审核状态'] ?? fields['状态'],
      fields['打印状态'],
      fields['统计时间'],
      fields['申请时间'] ?? fields['申请日期'],
    ].whereType<String>().where((v) => v.trim().isNotEmpty).toList();
    if (candidates.isNotEmpty) return candidates.take(2).join(' · ');
    return fields.values.take(2).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.certificates;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null && service.ready;
        final items = <(CertificateKind, AcademicCertificate)>[
          if (ready)
            for (final kind in CertificateKind.values)
              for (final record in service.records[kind] ?? const [])
                (kind, record),
        ];
        final preview = items.take(2).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusCertificates,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(service)) : null,
          badge: items.isEmpty
              ? null
              : TpBadge(label: '${items.length} 份', tone: TpBadgeTone.info),
          child: preview.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.document,
                  title: ready ? '暂无申请记录缓存' : '需要绑定校园 IDS',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].$1.label,
                          subtitle: _subtitleFor(preview[i].$2),
                          trailing: preview[i].$2.downloads.isNotEmpty
                              ? const TpBadge(
                                  label: 'PDF',
                                  tone: TpBadgeTone.success,
                                )
                              : null,
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _OaGymHomeWidget extends StatelessWidget {
  const _OaGymHomeWidget();

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final gym = sp.oaGymService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        gym,
      ]),
      builder: (context, _) {
        final ready =
            sp.authService.isLoggedIn && sp.thirdPartyAuthService.hasIdsBinding;
        final venueCount = gym.venues.length;
        return _CampusServiceCard(
          id: HomeWidgetId.campusOaGym,
          badge: venueCount > 0
              ? TpBadge(label: '$venueCount 场馆', tone: TpBadgeTone.success)
              : TpBadge(
                  label: gym.sessionReady
                      ? '已连接'
                      : (ready ? '预约入口' : '需绑定 IDS'),
                  tone: gym.sessionReady
                      ? TpBadgeTone.success
                      : (ready ? TpBadgeTone.info : TpBadgeTone.warning),
                ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              TpTokens.cardPaddingHorizontal,
              TpTokens.space1,
              TpTokens.cardPaddingHorizontal,
              TpTokens.space4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: TpTokens.space2,
                  runSpacing: TpTokens.space2,
                  children: [
                    for (final sport in OaSport.values)
                      TpBadge(label: sport.label, tone: TpBadgeTone.muted),
                  ],
                ),
                const SizedBox(height: TpTokens.space2),
                Text(
                  gym.timeSlots.isNotEmpty
                      ? '已加载 ${gym.timeSlots.length} 个预约时段 · 点击查询空闲场地'
                      : '查询各项目空闲时段并预约或取消场地',
                  style: TpTypography.itemMeta(context.tpColors),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StudentLeaveHomeWidget extends StatefulWidget {
  const _StudentLeaveHomeWidget();

  @override
  State<_StudentLeaveHomeWidget> createState() =>
      _StudentLeaveHomeWidgetState();
}

class _StudentLeaveHomeWidgetState extends State<_StudentLeaveHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    final service = ServiceProvider.of(context).studentLeaveService;
    if (_loading || service == null) return;
    final rev = service.revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refresh();
    } catch (e) {
      if (mounted && rev == service.revision) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _subtitleFor(StudentLeave record) {
    final period = [record['QJKSRQ'], record['QJJSRQ']]
        .where((v) => v.isNotEmpty)
        .toSet()
        .join(' 至 ');
    if (period.isNotEmpty) return period;
    return record['SQRQ'];
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.studentLeaveService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null && service.ready;
        final history = ready ? service.history : const <StudentLeave>[];
        final preview = history.take(2).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusStudentLeave,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh()) : null,
          badge: history.isEmpty
              ? null
              : TpBadge(
                  label: '${history.length} 条',
                  tone: TpBadgeTone.brand,
                ),
          child: preview.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.building,
                  title: ready ? '暂无请假记录' : '需要绑定校园 IDS',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].type.isEmpty
                              ? '请假申请'
                              : preview[i].type,
                          subtitle: _subtitleFor(preview[i]),
                          trailing: preview[i].status.isEmpty
                              ? null
                              : TpBadge(
                                  label: preview[i].status,
                                  tone: _statusBadgeTone(preview[i].status),
                                ),
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _HolidayTravelHomeWidget extends StatefulWidget {
  const _HolidayTravelHomeWidget();

  @override
  State<_HolidayTravelHomeWidget> createState() =>
      _HolidayTravelHomeWidgetState();
}

class _HolidayTravelHomeWidgetState extends State<_HolidayTravelHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    final service = ServiceProvider.of(context).holidayTravelService;
    if (_loading || service == null) return;
    final rev = service.revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refresh();
    } catch (e) {
      if (mounted && rev == service.revision) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _subtitleFor(HolidayTravel record) {
    final date = record.registrationDate;
    final dateText = date == null
        ? ''
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return [record.region, dateText].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.holidayTravelService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null && service.ready;
        final history = ready ? service.history : const <HolidayTravel>[];
        final preview = history.take(2).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusHolidayTravel,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh()) : null,
          badge: history.isEmpty
              ? null
              : TpBadge(
                  label: '${history.length} 条',
                  tone: TpBadgeTone.info,
                ),
          child: preview.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.luggage,
                  title: ready ? '暂无离返校登记' : '需要绑定校园 IDS',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].holiday.isEmpty
                              ? '节假日离返校'
                              : preview[i].holiday,
                          subtitle: _subtitleFor(preview[i]),
                          trailing: preview[i].status.isEmpty
                              ? null
                              : TpBadge(
                                  label: preview[i].status,
                                  tone: _statusBadgeTone(preview[i].status),
                                ),
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _ActivitiesHomeWidget extends StatefulWidget {
  const _ActivitiesHomeWidget();

  @override
  State<_ActivitiesHomeWidget> createState() => _ActivitiesHomeWidgetState();
}

class _ActivitiesHomeWidgetState extends State<_ActivitiesHomeWidget> {
  String? _ownerKey;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<EgateAppSignRecord> _records = const [];

  String _identityOf(ServiceProvider sp) {
    final user = sp.authService.session?.userId ?? '';
    final ids = sp.thirdPartyAuthService.idsAccount?.account ?? '';
    return '$user|$ids';
  }

  void _syncIdentity(ServiceProvider sp) {
    final current = _identityOf(sp);
    if (current == _ownerKey) return;
    _ownerKey = current;
    _loaded = false;
    _error = null;
    _records = const [];
  }

  Future<void> _refresh(ServiceProvider sp) async {
    if (_loading) return;
    final key = _identityOf(sp);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await sp.egateAppService.fetchSignHistory();
      if (!mounted || _identityOf(sp) != key) return;
      setState(() {
        _records = rows;
        _loaded = true;
      });
    } catch (e) {
      if (mounted && _identityOf(sp) == key) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        sp.egateAppService,
      ]),
      builder: (context, _) {
        _syncIdentity(sp);
        final ready =
            sp.authService.isLoggedIn && sp.thirdPartyAuthService.hasIdsBinding;
        final preview = _records.take(2).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusActivities,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(sp)) : null,
          badge: _loaded
              ? TpBadge(
                  label: '${_records.length} 场',
                  tone: TpBadgeTone.info,
                )
              : (ready
                  ? const TpBadge(label: '扫码签到', tone: TpBadgeTone.brand)
                  : null),
          child: !ready || !_loaded || preview.isEmpty
              ? _CompactPromptBody(
                  icon: TpIcons.scan,
                  title: !ready
                      ? '需要绑定校园 IDS'
                      : (_loaded ? '暂无活动签到记录' : '查看近期学生活动与签到'),
                  subtitle: _loaded
                      ? '参与学生活动后可在此查看签到记录'
                      : _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].activityName,
                          subtitle: [
                            preview[i].typeDisplay,
                            if (preview[i].date != null &&
                                preview[i].date!.isNotEmpty)
                              preview[i].date!,
                          ].join(' · '),
                          trailing: preview[i].statusDisplay.isEmpty
                              ? null
                              : TpBadge(
                                  label: preview[i].statusDisplay,
                                  tone:
                                      _statusBadgeTone(preview[i].statusDisplay),
                                ),
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _JobsHomeWidget extends StatefulWidget {
  const _JobsHomeWidget();

  @override
  State<_JobsHomeWidget> createState() => _JobsHomeWidgetState();
}

class _JobsHomeWidgetState extends State<_JobsHomeWidget> {
  String? _ownerKey;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  List<CampusJobOpening> _workStudy = const [];
  List<CampusJobOpening> _teachingAssistant = const [];

  String _identityOf(ServiceProvider sp) {
    final user = sp.authService.session?.userId ?? '';
    final ids = sp.thirdPartyAuthService.idsAccount?.account ?? '';
    return '$user|$ids';
  }

  void _syncIdentity(ServiceProvider sp) {
    final current = _identityOf(sp);
    if (current == _ownerKey) return;
    _ownerKey = current;
    _loaded = false;
    _error = null;
    _workStudy = const [];
    _teachingAssistant = const [];
  }

  Future<void> _refresh(ServiceProvider sp) async {
    final emap = sp.campusClients?.emap;
    final studentId = sp.thirdPartyAuthService.idsAccount?.account ?? '';
    if (_loading || emap == null || studentId.isEmpty) return;
    final key = _identityOf(sp);
    final service = CampusJobService(emap, studentId);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        service.openings(CampusJobProgram.workStudy),
        service.openings(CampusJobProgram.teachingAssistant),
      ]);
      if (!mounted || _identityOf(sp) != key) return;
      setState(() {
        _workStudy = results[0];
        _teachingAssistant = results[1];
        _loaded = true;
      });
    } catch (e) {
      if (mounted && _identityOf(sp) == key) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final colors = context.tpColors;
    return ListenableBuilder(
      listenable: Listenable.merge([sp.authService, sp.thirdPartyAuthService]),
      builder: (context, _) {
        _syncIdentity(sp);
        final emap = sp.campusClients?.emap;
        final studentId = sp.thirdPartyAuthService.idsAccount?.account ?? '';
        final ready = emap != null &&
            sp.authService.isLoggedIn &&
            sp.thirdPartyAuthService.hasIdsBinding &&
            studentId.isNotEmpty;
        final combined = [..._teachingAssistant, ..._workStudy];
        final preview = combined.take(2).toList();

        return _CampusServiceCard(
          id: HomeWidgetId.campusJobs,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(sp)) : null,
          badge: _loaded
              ? TpBadge(
                  label: '${combined.length} 岗位',
                  tone: combined.isEmpty
                      ? TpBadgeTone.muted
                      : TpBadgeTone.success,
                )
              : null,
          child: !ready || !_loaded
              ? _CompactPromptBody(
                  icon: TpIcons.briefcase,
                  title: ready ? '浏览校内助教与勤工助学岗位' : '需要绑定校园 IDS',
                  subtitle: ready
                      ? '点击刷新在招岗位数量，或进入查看申请与薪酬'
                      : _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space1,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space2,
                        ),
                        child: Text(
                          '助教 ${_teachingAssistant.length} · 勤工助学 ${_workStudy.length}',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ),
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].title,
                          subtitle: preview[i].unit,
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _StudentAllowanceHomeWidget extends StatefulWidget {
  const _StudentAllowanceHomeWidget();

  @override
  State<_StudentAllowanceHomeWidget> createState() =>
      _StudentAllowanceHomeWidgetState();
}

class _StudentAllowanceHomeWidgetState
    extends State<_StudentAllowanceHomeWidget> {
  int? _revision;
  bool _loading = false;
  String? _error;
  StudentAllowanceReport? _report;

  void _syncRevision(StudentAllowanceService service) {
    if (_revision == service.accountRevision &&
        service.access == StudentAllowanceAccess.ready) {
      return;
    }
    if (_revision != service.accountRevision ||
        service.access != StudentAllowanceAccess.ready) {
      _revision = service.accountRevision;
      _report = null;
      _error = null;
    }
  }

  Future<void> _refresh(StudentAllowanceService service) async {
    if (_loading) return;
    final rev = service.accountRevision;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await service.query(StudentAllowancePeriod(start, now));
      if (!mounted || rev != service.accountRevision) return;
      setState(() => _report = report);
    } catch (e) {
      if (mounted && rev == service.accountRevision) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatFen(int? fen) {
    if (fen == null) return '—';
    return '¥ ${(fen / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.studentAllowanceService;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        _syncRevision(service);
        final ready = service.access == StudentAllowanceAccess.ready;
        final totalFen = _report?.total?.netFen;
        final latestMonth =
            (_report != null && _report!.months.isNotEmpty)
                ? _report!.months.last
                : null;

        return _CampusServiceCard(
          id: HomeWidgetId.campusStudentAllowance,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(service)) : null,
          badge: totalFen == null
              ? null
              : TpBadge(
                  label: _formatFen(totalFen),
                  tone: TpBadgeTone.success,
                ),
          child: _report == null
              ? _CompactPromptBody(
                  icon: TpIcons.allowance,
                  title: switch (service.access) {
                    StudentAllowanceAccess.signIn => '请先登录 TechPie',
                    StudentAllowanceAccess.bindIds => '绑定校园 IDS 后查询',
                    StudentAllowanceAccess.ready => '按需查询近三个月学生津贴',
                  },
                  subtitle: '财务结果仅在内存展示，不会写入本地缓存',
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TpListRow(
                        title: '近三月实发合计',
                        subtitle: '共 ${_report!.months.length} 个发放月份记录',
                        trailing: TpBadge(
                          label: _formatFen(totalFen),
                          tone: TpBadgeTone.success,
                        ),
                        showDivider: latestMonth != null,
                      ),
                      if (latestMonth != null)
                        TpListRow(
                          title: latestMonth.month == null
                              ? '最近月份'
                              : '${latestMonth.month!.year}-${latestMonth.month!.month.toString().padLeft(2, '0')}',
                          subtitle: '${latestMonth.categories.length} 个补助项目',
                          trailing: TpBadge(
                            label: _formatFen(latestMonth.netFen),
                            tone: TpBadgeTone.info,
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PnpMinorHomeWidget extends StatefulWidget {
  const _PnpMinorHomeWidget();

  @override
  State<_PnpMinorHomeWidget> createState() => _PnpMinorHomeWidgetState();
}

class _PnpMinorHomeWidgetState extends State<_PnpMinorHomeWidget> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh(PnpMinorService service) async {
    if (_loading) return;
    final gen = service.generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await service.refresh(AcademicApplicationTab.pnp);
      if (!mounted || gen != service.generation) return;
      await service.refresh(AcademicApplicationTab.minor);
    } catch (e) {
      if (mounted && gen == service.generation) {
        setState(() => _error = _friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = ServiceProvider.of(context);
    final service = sp.pnpMinor;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sp.authService,
        sp.thirdPartyAuthService,
        if (service != null) service,
      ]),
      builder: (context, _) {
        final ready = service != null && service.ready;
        final pnpWin = ready ? service.windows[AcademicApplicationTab.pnp] : null;
        final minorWin =
            ready ? service.windows[AcademicApplicationTab.minor] : null;
        final rows = ready
            ? service.sections.values.expand((e) => e).toList()
            : const <AcademicApplicationRow>[];
        final preview = rows.take(2).toList();
        final anyOpen = pnpWin == ApplicationWindow.open ||
            minorWin == ApplicationWindow.open;

        return _CampusServiceCard(
          id: HomeWidgetId.campusPnpMinor,
          loading: _loading,
          errorText: _error,
          onRefresh: ready ? () => unawaited(_refresh(service)) : null,
          badge: anyOpen
              ? const TpBadge(label: '开放申请', tone: TpBadgeTone.success)
              : (rows.isNotEmpty
                  ? TpBadge(
                      label: '${rows.length} 条',
                      tone: TpBadgeTone.info,
                    )
                  : null),
          child: !ready || (pnpWin == null && minorWin == null && rows.isEmpty)
              ? _CompactPromptBody(
                  icon: TpIcons.pnpMinor,
                  title: ready ? '查看 P/NP 与辅修申请' : '需要绑定校园 IDS',
                  subtitle: _compactNoticeText(sp),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space1,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space2,
                        ),
                        child: Wrap(
                          spacing: TpTokens.space2,
                          runSpacing: TpTokens.space2,
                          children: [
                            TpBadge(
                              label: 'P/NP：${pnpWin?.label ?? '未加载'}',
                              tone: pnpWin == ApplicationWindow.open
                                  ? TpBadgeTone.success
                                  : TpBadgeTone.muted,
                            ),
                            TpBadge(
                              label: '辅修：${minorWin?.label ?? '未加载'}',
                              tone: minorWin == ApplicationWindow.open
                                  ? TpBadgeTone.success
                                  : TpBadgeTone.muted,
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < preview.length; i++)
                        TpListRow(
                          title: preview[i].title,
                          subtitle: preview[i].fields.values.take(2).join(' · '),
                          showDivider: i < preview.length - 1,
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
