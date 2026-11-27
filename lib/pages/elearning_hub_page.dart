import 'dart:async';

import 'package:flutter/material.dart';

import '../models/elearning_models.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/campus_session.dart';
import '../services/elearning_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';
import 'elearning_course_detail_page.dart';

class ElearningHubPage extends StatelessWidget {
  const ElearningHubPage({super.key});

  @override
  Widget build(BuildContext context) => BlackboardSessionView(
        builder: (context, service) => _Hub(
          key: ValueKey((service, service.client.session.identity())),
          service: service,
        ),
      );
}

class _Hub extends StatefulWidget {
  const _Hub({super.key, required this.service});
  final ElearningService service;

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> {
  final _searchCtrl = TextEditingController();
  final GlobalKey<BlackboardListState<BlackboardCourse>> _coursesKey =
      GlobalKey();
  final GlobalKey<BlackboardListState<BlackboardAnnouncement>>
      _announcementsKey = GlobalKey();
  String query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colors.canvas,
        appBar: BlurredAppBar(
          title: const Text('Blackboard 课程'),
          actions: [
            Builder(
              builder: (tabContext) => IconButton(
                tooltip: '刷新',
                icon: const Icon(TpIcons.refresh),
                onPressed: () {
                  final idx = DefaultTabController.of(tabContext).index;
                  if (idx == 0) {
                    _coursesKey.currentState?.triggerRefresh();
                  } else {
                    _announcementsKey.currentState?.triggerRefresh();
                  }
                },
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: '我的课程'), Tab(text: '公告')],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.pageHorizontalPadding,
                    TpTokens.space3,
                    TpTokens.pageHorizontalPadding,
                    TpTokens.space2,
                  ),
                  child: TpPageBody(
                    maxWidth: 880,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        labelText: '搜索课程名称或代码',
                        prefixIcon: const Icon(TpIcons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜索',
                                icon: const Icon(TpIcons.close),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => query = '');
                                },
                              ),
                      ),
                      onChanged: (value) =>
                          setState(() => query = value.trim().toLowerCase()),
                    ),
                  ),
                ),
                Expanded(
                  child: BlackboardList<BlackboardCourse>(
                    key: _coursesKey,
                    load: () => widget.service.courses(),
                    refresh: () => widget.service.courses(refresh: true),
                    cached: widget.service.cachedCourses,
                    empty: '暂无课程',
                    buildRows: (context, items) {
                      final terms = <String, List<BlackboardCourse>>{};
                      for (final course in items.where(
                        (c) =>
                            '${c.name} ${c.code}'.toLowerCase().contains(query),
                      )) {
                        (terms[course.term.isEmpty ? '其他学期' : course.term] ??=
                                [])
                            .add(course);
                      }
                      return [
                        if (terms.isEmpty)
                          const TpStateCard.empty(
                            icon: TpIcons.search,
                            title: '没有匹配的课程',
                            compact: true,
                          ),
                        for (final term in terms.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: TpTokens.space3,
                              bottom: TpTokens.space2,
                            ),
                            child: Text(
                              term.key,
                              style: TpTypography.cardTitle(colors),
                            ),
                          ),
                          TpCard(
                            child: Column(
                              children: [
                                for (final course in term.value)
                                  ListTile(
                                    title: Text(course.name),
                                    subtitle: Text(course.code),
                                    trailing: const Icon(
                                      TpIcons.chevronRight,
                                      size: TpTokens.iconS,
                                    ),
                                    onTap: () => openBlackboardCourse(
                                      context,
                                      widget.service,
                                      course,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ];
                    },
                  ),
                ),
              ],
            ),
            BlackboardList<BlackboardAnnouncement>(
              key: _announcementsKey,
              load: () => widget.service.announcements(),
              cached: widget.service.cachedAnnouncements,
              empty: '暂无公告',
              buildRows: announcementRows,
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> announcementRows(
  BuildContext context,
  List<BlackboardAnnouncement> items,
) =>
    [
      for (final notice in items)
        Padding(
          padding: const EdgeInsets.only(bottom: TpTokens.space2),
          child: TpCard(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(notice.title),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SelectableText(notice.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];

Future<void> openBlackboardCourse(
  BuildContext context,
  ElearningService service,
  BlackboardCourse course,
) =>
    pushAdaptivePage<void>(
      context,
      builder: (_) => ElearningCourseDetailPage(
        course: course,
        owner: service.client.session.identity(),
      ),
    );

class BlackboardSessionView extends StatelessWidget {
  const BlackboardSessionView({super.key, this.owner, required this.builder});
  final CampusIdentity? owner;
  final Widget Function(BuildContext, ElearningService) builder;

  @override
  Widget build(BuildContext context) {
    final provider = ServiceProvider.of(context);
    return ListenableBuilder(
      listenable:
          Listenable.merge([provider.authService, provider.thirdPartyAuthService]),
      builder: (context, _) {
        final service = provider.campusClients?.blackboard;
        final current = service?.client.session.identity();
        if (service == null ||
            current?.ids == null ||
            current?.user == null ||
            (owner != null && owner != current)) {
          return Scaffold(
            backgroundColor: context.tpColors.canvas,
            appBar: const BlurredAppBar(title: Text('Blackboard 课程')),
            body: CampusPrerequisiteView(
              icon: TpIcons.graduation,
              title: 'Blackboard 课程',
              fallbackText: '请使用已绑定 IDS 的原账号打开课程',
              message: owner != null
                  ? '当前登录或绑定的 IDS 账号与打开课程时不一致，请切换回原账号或重新打开课程。'
                  : 'Blackboard 课程复用已绑定的校园 IDS 登录态。',
            ),
          );
        }
        return builder(context, service);
      },
    );
  }
}

class BlackboardList<T> extends StatefulWidget {
  const BlackboardList({
    super.key,
    required this.load,
    this.refresh,
    required this.empty,
    required this.buildRows,
    this.cached = const [],
    this.header = const [],
  });

  final Future<List<T>> Function() load;
  final Future<List<T>> Function()? refresh;
  final List<T> cached;
  final String empty;
  final List<Widget> Function(BuildContext, List<T>) buildRows;
  final List<Widget> header;

  @override
  State<BlackboardList<T>> createState() => BlackboardListState<T>();
}

class BlackboardListState<T> extends State<BlackboardList<T>> {
  late Future<List<T>> response = widget.load();
  int _refreshRevision = 0;

  int get refreshRevision => _refreshRevision;

  Future<List<T>> _reload() {
    _refreshRevision++;
    return (widget.refresh ?? widget.load)();
  }

  void triggerRefresh() {
    if (!mounted) return;
    setState(() => response = _reload());
  }

  String _errorMessage(Object? error) => switch (error) {
        CampusRequestException(:final message) => message,
        _ => '读取失败，请重试',
      };

  @override
  Widget build(BuildContext context) => FutureBuilder<List<T>>(
        future: response,
        builder: (context, snapshot) {
          final items = snapshot.data ?? widget.cached;
          final loading = snapshot.connectionState != ConnectionState.done;
          return RefreshIndicator.adaptive(
            onRefresh: () async {
              setState(() => response = _reload());
              try {
                await response;
              } catch (_) {/* The list displays the retry action. */}
            },
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                TpTokens.pageHorizontalPadding,
                TpTokens.space3,
                TpTokens.pageHorizontalPadding,
                AppShellMetrics.bottomContentPaddingOf(context),
              ),
              children: [
                TpPageBody(
                  maxWidth: 880,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (loading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: TpTokens.space2),
                      ],
                      if (snapshot.hasError) ...[
                        TpStateCard.error(
                          title: items.isEmpty
                              ? _errorMessage(snapshot.error)
                              : '${_errorMessage(snapshot.error)}（显示上次保存的内容）',
                          compact: true,
                          onPrimaryAction: triggerRefresh,
                        ),
                        const SizedBox(height: TpTokens.space3),
                      ],
                      ...widget.header,
                      if (!loading &&
                          !snapshot.hasError &&
                          items.isEmpty &&
                          widget.header.isEmpty)
                        TpStateCard.empty(
                          icon: TpIcons.graduation,
                          title: widget.empty,
                          compact: true,
                        ),
                      if (items.isNotEmpty) ...widget.buildRows(context, items),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class BlackboardTimetableLink extends StatelessWidget {
  const BlackboardTimetableLink(this.courseName, {super.key});
  final String courseName;

  @override
  Widget build(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ServiceProvider>();
    final service = provider?.campusClients?.blackboard;
    if (service == null || provider == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable:
          Listenable.merge([provider.authService, provider.thirdPartyAuthService]),
      builder: (context, _) {
        final user = service.client.session.identity();
        if (user.user == null || user.ids == null) {
          return const SizedBox.shrink();
        }
        return _CourseMatch(
          key: ValueKey((service, user)),
          service: service,
          name: courseName,
        );
      },
    );
  }
}

class _CourseMatch extends StatefulWidget {
  const _CourseMatch({super.key, required this.service, required this.name});
  final ElearningService service;
  final String name;

  @override
  State<_CourseMatch> createState() => _CourseMatchState();
}

class _CourseMatchState extends State<_CourseMatch> {
  late final load = widget.service.courses();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<BlackboardCourse>>(
        future: load,
        builder: (context, data) {
          final course = matchBlackboardCourse(
            widget.name,
            data.data ?? widget.service.cachedCourses,
          );
          return course == null
              ? const SizedBox.shrink()
              : TextButton.icon(
                  icon: const Icon(TpIcons.graduation),
                  onPressed: () =>
                      openBlackboardCourse(context, widget.service, course),
                  label: const Text('打开 Blackboard 课件与公告'),
                );
        },
      );
}
