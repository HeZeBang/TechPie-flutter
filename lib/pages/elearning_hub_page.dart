import 'package:flutter/material.dart';

import '../models/elearning_models.dart';
import '../services/campus/campus_session.dart';
import '../services/elearning_service.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'elearning_course_detail_page.dart';

class ElearningHubPage extends StatelessWidget {
  const ElearningHubPage({super.key});
  @override
  Widget build(BuildContext context) => BlackboardSessionView(
        builder: (context, service) =>
            _Hub(key: ValueKey((service, service.client.session.identity())), service: service),
      );
}

class _Hub extends StatefulWidget {
  const _Hub({super.key, required this.service});
  final ElearningService service;
  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> {
  String query = '';
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Blackboard 课程'),
            bottom: const TabBar(tabs: [Tab(text: '我的课程'), Tab(text: '公告')]),
          ),
          body: TabBarView(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '搜索课程名称或代码',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => query = value.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: BlackboardList<BlackboardCourse>(
                      load: () => widget.service.courses(),
                      refresh: () => widget.service.courses(refresh: true),
                      cached: widget.service.cachedCourses,
                      empty: '暂无课程',
                      buildRows: (context, items) {
                        final terms = <String, List<BlackboardCourse>>{};
                        for (final course in items
                            .where((c) => '${c.name} ${c.code}'.toLowerCase().contains(query))) {
                          (terms[course.term.isEmpty ? '其他学期' : course.term] ??= []).add(course);
                        }
                        return [
                          if (terms.isEmpty) const ListTile(title: Text('没有匹配的课程')),
                          for (final term in terms.entries) ...[
                            ListTile(
                              title: Text(term.key, style: Theme.of(context).textTheme.titleSmall),
                            ),
                            for (final course in term.value)
                              ListTile(
                                title: Text(course.name),
                                subtitle: Text(course.code),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => openBlackboardCourse(context, widget.service, course),
                              ),
                          ],
                        ];
                      },
                    ),
                  ),
                ],
              ),
              BlackboardList<BlackboardAnnouncement>(
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

List<Widget> announcementRows(BuildContext context, List<BlackboardAnnouncement> items) => [
      for (final notice in items)
        ExpansionTile(
          title: Text(notice.title),
          children: [
            Padding(padding: const EdgeInsets.all(16), child: SelectableText(notice.text)),
          ],
        ),
    ];

Future<void> openBlackboardCourse(
  BuildContext context,
  ElearningService service,
  BlackboardCourse course,
) =>
    pushAdaptivePage<void>(
      context,
      builder: (_) =>
          ElearningCourseDetailPage(course: course, owner: service.client.session.identity()),
    );

class BlackboardSessionView extends StatelessWidget {
  const BlackboardSessionView({super.key, this.owner, required this.builder});
  final CampusIdentity? owner;
  final Widget Function(BuildContext, ElearningService) builder;
  @override
  Widget build(BuildContext context) {
    final provider = ServiceProvider.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([provider.authService, provider.thirdPartyAuthService]),
      builder: (context, _) {
        final service = provider.campusClients?.blackboard;
        final current = service?.client.session.identity();
        if (service == null ||
            current?.ids == null ||
            current?.user == null ||
            (owner != null && owner != current)) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('请使用已绑定 IDS 的原账号打开课程')),
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
  State<BlackboardList<T>> createState() => _BlackboardListState<T>();
}

class _BlackboardListState<T> extends State<BlackboardList<T>> {
  late Future<List<T>> response = widget.load();
  Future<List<T>> _reload() => (widget.refresh ?? widget.load)();
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
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (loading) const LinearProgressIndicator(),
                if (snapshot.hasError)
                  ListTile(
                    title: Text(items.isEmpty ? '读取失败' : '读取失败，显示上次保存的内容'),
                    trailing: TextButton(
                      onPressed: () => setState(() => response = _reload()),
                      child: const Text('重试'),
                    ),
                  ),
                ...widget.header,
                if (!loading && !snapshot.hasError && items.isEmpty && widget.header.isEmpty)
                  ListTile(title: Text(widget.empty)),
                if (items.isNotEmpty) ...widget.buildRows(context, items),
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
    final provider = context.dependOnInheritedWidgetOfExactType<ServiceProvider>();
    final service = provider?.campusClients?.blackboard;
    if (service == null || provider == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([provider.authService, provider.thirdPartyAuthService]),
      builder: (context, _) {
        final user = service.client.session.identity();
        if (user.user == null || user.ids == null) return const SizedBox.shrink();
        return _CourseMatch(key: ValueKey((service, user)), service: service, name: courseName);
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
          final course =
              matchBlackboardCourse(widget.name, data.data ?? widget.service.cachedCourses);
          return course == null
              ? const SizedBox.shrink()
              : TextButton.icon(
                  icon: const Icon(Icons.school_outlined),
                  onPressed: () => openBlackboardCourse(context, widget.service, course),
                  label: const Text('打开 Blackboard 课件与公告'),
                );
        },
      );
}
