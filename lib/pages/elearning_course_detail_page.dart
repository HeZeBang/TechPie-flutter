import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/elearning_models.dart';
import '../models/feature.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/campus_file_share.dart';
import '../services/campus/campus_session.dart';
import '../services/elearning_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_progress_indicator.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'elearning_hub_page.dart';
import 'generic_webview_page.dart';

Future<void> _web(BuildContext context, String title, Uri uri) =>
    pushAdaptivePage<void>(
      context,
      builder: (_) => GenericWebViewPage(
        title: title,
        url: uri.toString(),
        cookieType: CookieType.elearning,
      ),
    );

class ElearningCourseDetailPage extends StatelessWidget {
  const ElearningCourseDetailPage({
    super.key,
    required this.course,
    required this.owner,
  });

  final BlackboardCourse course;
  final CampusIdentity owner;

  @override
  Widget build(BuildContext context) {
    return BlackboardSessionView(
      owner: owner,
      builder: (context, s) => _CourseDetailScaffold(
        course: course,
        service: s,
      ),
    );
  }
}

class _CourseDetailScaffold extends StatefulWidget {
  const _CourseDetailScaffold({
    required this.course,
    required this.service,
  });

  final BlackboardCourse course;
  final ElearningService service;

  @override
  State<_CourseDetailScaffold> createState() => _CourseDetailScaffoldState();
}

class _CourseDetailScaffoldState extends State<_CourseDetailScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTabChanged);
  int _tabIndex = 0;

  void _onTabChanged() {
    if (!mounted || _tabIndex == _tabs.index) return;
    setState(() => _tabIndex = _tabs.index);
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _openWeb() {
    unawaited(
      _web(
        context,
        widget.course.name,
        widget.service.web(
          '/webapps/blackboard/execute/launcher',
          {'type': 'Course', 'id': widget.course.id, 'url': ''},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final course = widget.course;
    final s = widget.service;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: course.name,
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '返回',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回',
              placementGroup: 'leading-main',
            ),
          ],
          trailingItems: const [
            IosNativeNavigationBarItem(
              id: 'web',
              sfSymbol: 'safari',
              accessibilityLabel: '打开 Blackboard 网页',
              placementGroup: 'trailing-main',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            } else if (id == 'web') {
              _openWeb();
            }
          },
        ),
        material: () => BlurredAppBar(
          title: Text(course.name),
          actions: [
            IconButton(
              icon: const Icon(TpIcons.externalLink),
              tooltip: '打开 Blackboard 网页',
              onPressed: _openWeb,
            ),
          ],
        ),
      ),
      body: Column(
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
              child: AdaptiveSegmentedControl(
                value: _tabIndex,
                segments: const ['课件', '成绩', '公告与小组'],
                onChanged: _tabs.animateTo,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _Contents(service: s, course: course.id),
                _Grades(service: s, course: course.id),
                _News(service: s, course: course.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Grades extends StatefulWidget {
  const _Grades({required this.service, required this.course});
  final ElearningService service;
  final String course;

  @override
  State<_Grades> createState() => _GradesState();
}

class _GradesState extends State<_Grades> {
  bool receipts = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TpTokens.pageHorizontalPadding,
            TpTokens.space1,
            TpTokens.pageHorizontalPadding,
            TpTokens.space2,
          ),
          child: TpPageBody(
            maxWidth: 880,
            child: AdaptiveSegmentedControl(
              value: receipts ? 1 : 0,
              segments: const ['成绩明细', '提交确认'],
              onChanged: (idx) => setState(() => receipts = idx == 1),
            ),
          ),
        ),
        Expanded(
          child: receipts
              ? BlackboardList<BlackboardReceiptPage>(
                  load: () async {
                    final page = await s.submissionReceipts(widget.course);
                    return page.total == 0 ? [] : [page];
                  },
                  empty: '本课程暂无提交确认',
                  buildRows: (context, pages) {
                    final page = pages.single;
                    return [
                      for (final receipt in page.receipts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: TpTokens.space2),
                          child: TpCard(
                            child: Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                title: Text(receipt.assignment),
                                subtitle: Text(receipt.date),
                                children: [
                                  ListTile(
                                    title: const Text('确认编号'),
                                    subtitle: SelectableText(receipt.number),
                                  ),
                                  if (receipt.submission.isNotEmpty ||
                                      receipt.size.isNotEmpty)
                                    ListTile(
                                      title: const Text('提交'),
                                      subtitle: Text(
                                        [
                                          if (receipt.submission.isNotEmpty)
                                            receipt.submission,
                                          if (receipt.size.isNotEmpty)
                                            receipt.size,
                                        ].join(' · '),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (page.receipts.length < page.total)
                        TpCard(
                          child: ListTile(
                            title: Text(
                              '已显示 ${page.receipts.length} 条，共 ${page.total} 条',
                            ),
                            subtitle: const Text('前往 Blackboard 查看完整列表'),
                            trailing: const Icon(TpIcons.externalLink),
                            onTap: () =>
                                _web(context, '我的成绩', s.myGradesUrl(widget.course)),
                          ),
                        ),
                    ];
                  },
                )
              : BlackboardList<BlackboardGrade>(
                  load: () => s.grades(widget.course),
                  empty: '暂无成绩',
                  buildRows: (context, items) => [
                    TpCard(
                      child: Column(
                        children: [
                          for (final g in items)
                            ListTile(
                              title: Text(g.title),
                              subtitle: Text(
                                [
                                  if (g.score.isEmpty) '暂无分数' else g.score,
                                  if (g.possible.isNotEmpty) '满分 ${g.possible}',
                                  if (g.status.isNotEmpty) g.status,
                                ].join(' · '),
                              ),
                              trailing: g.attemptUrl == null
                                  ? null
                                  : const Icon(TpIcons.externalLink),
                              onTap: g.attemptUrl == null
                                  ? null
                                  : () => _web(context, '成绩尝试明细', g.attemptUrl!),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _News extends StatefulWidget {
  const _News({required this.service, required this.course});
  final ElearningService service;
  final String course;

  @override
  State<_News> createState() => _NewsState();
}

class _NewsState extends State<_News> {
  bool groups = false;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TpTokens.pageHorizontalPadding,
              TpTokens.space1,
              TpTokens.pageHorizontalPadding,
              TpTokens.space2,
            ),
            child: TpPageBody(
              maxWidth: 880,
              child: AdaptiveSegmentedControl(
                value: groups ? 1 : 0,
                segments: const ['课程公告', '课程小组'],
                onChanged: (idx) => setState(() => groups = idx == 1),
              ),
            ),
          ),
          Expanded(
            child: groups
                ? BlackboardList<BlackboardGroup>(
                    load: () => widget.service.groups(widget.course),
                    empty: '暂无小组',
                    buildRows: (c, rows) => [
                      TpCard(
                        child: Column(
                          children: [
                            for (final group in rows)
                              ListTile(
                                title: Text(group.name),
                                subtitle: Text(group.description),
                              ),
                          ],
                        ),
                      ),
                    ],
                  )
                : BlackboardList<BlackboardAnnouncement>(
                    load: () => widget.service.announcements(widget.course),
                    empty: '暂无课程公告',
                    buildRows: announcementRows,
                  ),
          ),
        ],
      );
}

class _Contents extends StatefulWidget {
  const _Contents({
    required this.service,
    required this.course,
    this.parent,
    this.header = const [],
  });

  final ElearningService service;
  final String course;
  final String? parent;
  final List<Widget> header;

  @override
  State<_Contents> createState() => _ContentsState();
}

class _ContentsState extends State<_Contents> {
  int _folderRefreshTick = 0;

  @override
  Widget build(BuildContext context) => BlackboardList<BlackboardContent>(
        load: () => widget.service.contents(widget.course, widget.parent),
        refresh: () async {
          if (mounted) setState(() => _folderRefreshTick++);
          return widget.service.contents(widget.course, widget.parent);
        },
        empty: '此目录暂无内容',
        header: [
          for (final w in widget.header)
            w is _FolderAttachmentsSection
                ? _FolderAttachmentsSection(
                    key: ValueKey('${widget.parent}:$_folderRefreshTick'),
                    service: w.service,
                    course: w.course,
                    content: w.content,
                  )
                : w,
        ],
        buildRows: (context, items) => [
          TpCard(
            child: Column(
              children: [
                for (final node in items)
                  ListTile(
                    leading: Icon(
                      node.folder ? TpIcons.folder : TpIcons.document,
                      color: context.tpColors.brandInk,
                    ),
                    title: Text(node.title),
                    trailing: const Icon(
                      TpIcons.chevronRight,
                      size: TpTokens.iconS,
                    ),
                    onTap: () async {
                      final owner = widget.service.client.session.identity();
                      await pushAdaptivePage<void>(
                        context,
                        builder: (_) => BlackboardSessionView(
                          owner: owner,
                          builder: (context, s) => _ContentNodePage(
                            service: s,
                            course: widget.course,
                            node: node,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      );
}

class _ContentNodePage extends StatelessWidget {
  const _ContentNodePage({
    required this.service,
    required this.course,
    required this.node,
  });

  final ElearningService service;
  final String course;
  final BlackboardContent node;

  List<Widget> _headerWidgets(BuildContext context) => [
        if (node.body.isNotEmpty) ...[
          TpCard(
            padding: const EdgeInsets.all(TpTokens.space4),
            child: SelectableText(node.body),
          ),
          const SizedBox(height: TpTokens.space3),
        ],
        if (node.assignment) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              icon: const Icon(TpIcons.externalLink),
              onPressed: () => _web(
                context,
                '作业详情与提交记录',
                service.assignmentUrl(course, node.id),
              ),
              label: const Text('作业详情与提交记录'),
            ),
          ),
          const SizedBox(height: TpTokens.space3),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: node.title,
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '返回',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
        ),
        material: () => BlurredAppBar(title: Text(node.title)),
      ),
      body: node.folder
          ? _Contents(
              service: service,
              course: course,
              parent: node.id,
              header: [
                ..._headerWidgets(context),
                _FolderAttachmentsSection(
                  service: service,
                  course: course,
                  content: node.id,
                ),
              ],
            )
          : BlackboardList<BlackboardAttachment>(
              load: () => service.attachments(course, node.id),
              empty: '暂无附件',
              header: _headerWidgets(context),
              buildRows: (context, files) => [
                TpCard(
                  child: Column(
                    children: [
                      for (final file in files)
                        _AttachmentTile(
                          service: service,
                          course: course,
                          content: node.id,
                          file: file,
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _FolderAttachmentsSection extends StatefulWidget {
  const _FolderAttachmentsSection({
    super.key,
    required this.service,
    required this.course,
    required this.content,
  });

  final ElearningService service;
  final String course;
  final String content;

  @override
  State<_FolderAttachmentsSection> createState() =>
      _FolderAttachmentsSectionState();
}

class _FolderAttachmentsSectionState extends State<_FolderAttachmentsSection> {
  late Future<List<BlackboardAttachment>> _files =
      widget.service.attachments(widget.course, widget.content);

  void _retry() {
    setState(() {
      _files = widget.service.attachments(widget.course, widget.content);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<BlackboardAttachment>>(
        future: _files,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final msg = snapshot.error is CampusRequestException
                ? (snapshot.error! as CampusRequestException).message
                : '附件列表加载失败';
            return Padding(
              padding: const EdgeInsets.only(bottom: TpTokens.space3),
              child: TpStateCard.error(
                title: msg,
                compact: true,
                onPrimaryAction: _retry,
              ),
            );
          }
          final files = snapshot.data ?? const <BlackboardAttachment>[];
          if (files.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: TpTokens.space3),
            child: TpCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final file in files)
                    _AttachmentTile(
                      service: widget.service,
                      course: widget.course,
                      content: widget.content,
                      file: file,
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    required this.service,
    required this.course,
    required this.content,
    required this.file,
  });

  final ElearningService service;
  final String course, content;
  final BlackboardAttachment file;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool busy = false;

  bool get _canShare =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> open({bool share = false}) async {
    if (busy) return;
    final owner = widget.service.client.session.identity();
    setState(() => busy = true);
    try {
      final bytes = await widget.service
          .downloadBytes(widget.course, widget.content, widget.file);
      if (!mounted || owner != widget.service.client.session.identity()) return;
      final result = await CampusFileShare.openOrShare(
        scope: 'blackboard',
        filename: widget.file.name,
        bytes: bytes,
        preferShare: share,
      );
      if (mounted && !result.succeeded && result.path != null) {
        showAdaptiveFeedback(
          context: context,
          message: '附件已下载至 ${result.path}',
          style: AdaptiveFeedbackStyle.info,
        );
      }
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: '附件操作失败，请重试或使用 Blackboard 网页',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(widget.file.name),
        subtitle: const Text('下载并打开'),
        onTap: busy ? null : () => open(),
        leading: busy
            ? const AdaptiveActivityIndicator(size: 20, strokeWidth: 2)
            : const Icon(TpIcons.download),
        trailing: _canShare
            ? IconButton(
                tooltip: '分享附件',
                icon: const Icon(TpIcons.share),
                onPressed: busy ? null : () => open(share: true),
              )
            : null,
      );
}
