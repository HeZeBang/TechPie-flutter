import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/elearning_models.dart';
import '../models/feature.dart';
import '../services/campus/campus_file_share.dart';
import '../services/campus/campus_session.dart';
import '../services/elearning_service.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'elearning_hub_page.dart';
import 'generic_webview_page.dart';

Future<void> _web(BuildContext context, String title, Uri uri) => pushAdaptivePage<void>(
      context,
      builder: (_) =>
          GenericWebViewPage(title: title, url: uri.toString(), cookieType: CookieType.elearning),
    );

class ElearningCourseDetailPage extends StatelessWidget {
  const ElearningCourseDetailPage({super.key, required this.course, required this.owner});
  final BlackboardCourse course;
  final CampusIdentity owner;
  @override
  Widget build(BuildContext context) => BlackboardSessionView(
        owner: owner,
        builder: (context, s) => DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(course.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: '打开 Blackboard 网页',
                  onPressed: () => _web(
                    context,
                    course.name,
                    s.web(
                      '/webapps/blackboard/execute/launcher',
                      {'type': 'Course', 'id': course.id, 'url': ''},
                    ),
                  ),
                ),
              ],
              bottom: const TabBar(tabs: [Tab(text: '课件'), Tab(text: '成绩'), Tab(text: '公告与小组')]),
            ),
            body: TabBarView(
              children: [
                _Contents(service: s, course: course.id),
                _Grades(service: s, course: course.id),
                _News(service: s, course: course.id),
              ],
            ),
          ),
        ),
      );
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
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('成绩明细')),
              ButtonSegment(value: true, label: Text('提交确认')),
            ],
            selected: {receipts},
            onSelectionChanged: (v) => setState(() => receipts = v.first),
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
                        ExpansionTile(
                          title: Text(receipt.assignment),
                          subtitle: Text(receipt.date),
                          children: [
                            ListTile(
                              title: const Text('确认编号'),
                              subtitle: SelectableText(receipt.number),
                            ),
                            if (receipt.submission.isNotEmpty || receipt.size.isNotEmpty)
                              ListTile(
                                title: const Text('提交'),
                                subtitle: Text(
                                  [
                                    if (receipt.submission.isNotEmpty) receipt.submission,
                                    if (receipt.size.isNotEmpty) receipt.size,
                                  ].join(' · '),
                                ),
                              ),
                          ],
                        ),
                      if (page.receipts.length < page.total)
                        ListTile(
                          title: Text('已显示 ${page.receipts.length} 条，共 ${page.total} 条'),
                          subtitle: const Text('前往 Blackboard 查看完整列表'),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => _web(context, '我的成绩', s.myGradesUrl(widget.course)),
                        ),
                    ];
                  },
                )
              : BlackboardList<BlackboardGrade>(
                  load: () => s.grades(widget.course),
                  empty: '暂无成绩',
                  buildRows: (context, items) => [
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
                        trailing: g.attemptUrl == null ? null : const Icon(Icons.open_in_new),
                        onTap: g.attemptUrl == null
                            ? null
                            : () => _web(context, '成绩尝试明细', g.attemptUrl!),
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
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('课程公告')),
                ButtonSegment(value: true, label: Text('课程小组')),
              ],
              selected: {
                groups,
              },
              onSelectionChanged: (v) => setState(() => groups = v.first),
            ),
          ),
          Expanded(
            child: groups
                ? BlackboardList<BlackboardGroup>(
                    load: () => widget.service.groups(widget.course),
                    empty: '暂无小组',
                    buildRows: (c, rows) => [
                      for (final group in rows)
                        ListTile(title: Text(group.name), subtitle: Text(group.description)),
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

class _Contents extends StatelessWidget {
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
  Widget build(BuildContext context) => BlackboardList<BlackboardContent>(
        load: () => service.contents(course, parent),
        empty: '此目录暂无内容',
        header: header,
        buildRows: (context, items) => [
          for (final node in items)
            ListTile(
              leading: Icon(node.folder ? Icons.folder_outlined : Icons.description_outlined),
              title: Text(node.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final owner = service.client.session.identity();
                await pushAdaptivePage<void>(
                  context,
                  builder: (_) => BlackboardSessionView(
                    owner: owner,
                    builder: (context, s) => _ContentNodePage(
                      service: s,
                      course: course,
                      node: node,
                    ),
                  ),
                );
              },
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(node.title)),
        body: node.folder
            ? _Contents(
                service: service,
                course: course,
                parent: node.id,
                header: [
                  if (node.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(node.body),
                    ),
                  if (node.assignment)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () => _web(
                          context,
                          '作业详情与提交记录',
                          service.assignmentUrl(course, node.id),
                        ),
                        label: const Text('作业详情与提交记录'),
                      ),
                    ),
                  _FolderAttachmentsSection(
                    service: service,
                    course: course,
                    content: node.id,
                  ),
                ],
              )
            : Column(
                children: [
                  if (node.body.isNotEmpty)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(node.body),
                      ),
                    ),
                  if (node.assignment)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _web(
                        context,
                        '作业详情与提交记录',
                        service.assignmentUrl(course, node.id),
                      ),
                      label: const Text('作业详情与提交记录'),
                    ),
                  Expanded(
                    child: BlackboardList<BlackboardAttachment>(
                      load: () => service.attachments(course, node.id),
                      empty: '暂无附件',
                      buildRows: (context, files) => [
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

class _FolderAttachmentsSection extends StatefulWidget {
  const _FolderAttachmentsSection({
    required this.service,
    required this.course,
    required this.content,
  });

  final ElearningService service;
  final String course;
  final String content;

  @override
  State<_FolderAttachmentsSection> createState() => _FolderAttachmentsSectionState();
}

class _FolderAttachmentsSectionState extends State<_FolderAttachmentsSection> {
  late final Future<List<BlackboardAttachment>> _files =
      widget.service.attachments(widget.course, widget.content);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<BlackboardAttachment>>(
        future: _files,
        builder: (context, snapshot) {
          final files = snapshot.data ?? const <BlackboardAttachment>[];
          if (files.isEmpty) return const SizedBox.shrink();
          return Column(
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
      final bytes = await widget.service.downloadBytes(widget.course, widget.content, widget.file);
      if (!mounted || owner != widget.service.client.session.identity()) return;
      final result = await CampusFileShare.openOrShare(
        scope: 'blackboard',
        filename: widget.file.name,
        bytes: bytes,
        preferShare: share,
      );
      if (mounted && !result.succeeded && result.path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('附件已下载至 ${result.path}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('附件操作失败，请重试或使用 Blackboard 网页')));
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
        leading:
            busy ? const CircularProgressIndicator() : const Icon(Icons.file_download_outlined),
        trailing: _canShare
            ? IconButton(
                tooltip: '分享附件',
                icon: const Icon(Icons.share_outlined),
                onPressed: busy ? null : () => open(share: true),
              )
            : null,
      );
}
