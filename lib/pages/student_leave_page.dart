import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../models/student_leave.dart';
import '../services/campus/campus_errors.dart';
import '../services/service_provider.dart';
import '../services/student_leave_management.dart';
import '../services/student_leave_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/design_system/design_system.dart';
import 'emap_history_page.dart';
import 'generic_webview_page.dart';
import 'student_leave_application.dart';

class StudentLeavePage extends StatelessWidget {
  const StudentLeavePage({super.key, this.service});
  final StudentLeaveService? service;

  @override
  Widget build(BuildContext context) {
    final data = service ?? ServiceProvider.of(context).studentLeaveService!;
    return EmapHistoryPage(
      title: '学生请假',
      service: data,
      refresh: data.refresh,
      webUrl: 'https://egate.shanghaitech.edu.cn/xsfw/sys/ydxsqjxs/index.html#/',
      primaryAction: (button) => StudentLeaveApplication(service: data, schoolFormButton: button),
      webLabel: '到学校网页提交材料或管理申请',
      content: (loaded) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SchoolApprovals(service: data),
          const SizedBox(height: TpTokens.space4),
          if (loaded && data.history.isEmpty) const Text('暂无请假记录'),
          for (final (i, record) in data.history.indexed)
            _LeaveCard(key: ValueKey((i, record.id, record.status)), record: record, service: data),
        ],
      ),
    );
  }
}

class _LeaveCard extends StatefulWidget {
  const _LeaveCard({super.key, required this.record, required this.service});
  final StudentLeave record;
  final StudentLeaveService service;
  @override
  State<_LeaveCard> createState() => _LeaveCardState();
}

class _LeaveCardState extends State<_LeaveCard> {
  Future<StudentLeave>? detail;
  Future<Set<LeaveRecordAction>>? actions;
  bool busy = false;

  void load(bool expanded) => setState(() {
        final service = widget.service;
        detail = expanded ? service.detail(widget.record, service.revision) : null;
        actions = expanded ? service.availableActions(widget.record, service.revision) : null;
      });

  Future<void> perform(LeaveRecordAction action) async {
    if (busy) return;
    final service = widget.service;
    final record = widget.record;
    final revision = service.revision;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    var acknowledged = false;
    try {
      switch (action) {
        case LeaveRecordAction.edit:
          final saved = await openStudentLeaveEditor(context, service, editing: record);
          if (mounted && saved == true) load(true);
          return;
        case LeaveRecordAction.print:
          final url = await service.officialPrintForm(record, revision);
          if (!mounted || revision != service.revision) return;
          await pushAdaptivePage<void>(
            context,
            builder: (_) => GenericWebViewPage(
              title: '官方请假单',
              url: url.toString(),
              cookieType: CookieType.egateApp,
              closeDesktopWindowOnAccountChange: true,
            ),
          );
          return;
        case LeaveRecordAction.withdraw:
        case LeaveRecordAction.delete:
          final deleting = action == LeaveRecordAction.delete;
          final label = deleting ? '删除草稿' : '撤回申请';
          final period =
              [record['QJKSRQ'], record['QJJSRQ']].where((d) => d.isNotEmpty).toSet().join(' 至 ');
          final summary = [record.type, period].where((s) => s.isNotEmpty).join(' · ');
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text('$label？'),
              content: Text('$summary\n${deleting ? '删除后无法恢复这条记录。' : '撤回后，申请会回到草稿，可编辑或删除。'}'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('取消')),
                FilledButton(
                  style: deleting
                      ? FilledButton.styleFrom(backgroundColor: Theme.of(dialog).colorScheme.error)
                      : null,
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(label),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted || revision != service.revision) return;
          await service.changeLeaveState(record, action, revision);
          acknowledged = true;
          await service.refresh();
          if (revision != service.revision || !messenger.mounted) return;
          messenger.showSnackBar(SnackBar(content: Text(deleting ? '草稿已删除' : '申请已撤回')));
      }
    } catch (e) {
      if (!mounted || revision != service.revision) return;
      final message = acknowledged
          ? '学校已确认操作，历史记录刷新失败，请手动刷新'
          : e is CampusRequestException
              ? e.message
              : '操作结果待核对，请刷新历史记录';
      messenger.showSnackBar(SnackBar(content: Text(message)));
      load(true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget management() => FutureBuilder<Set<LeaveRecordAction>>(
        future: actions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(TpTokens.space2),
              child: TextButton(
                onPressed: busy ? null : () => load(true),
                child: const Text('重新读取可用操作'),
              ),
            );
          }
          final allowed = snapshot.data ?? const <LeaveRecordAction>{};
          if (allowed.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.all(12),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                if (allowed.contains(LeaveRecordAction.delete))
                  TextButton(
                    style:
                        TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: busy ? null : () => perform(LeaveRecordAction.delete),
                    child: const Text('删除草稿'),
                  ),
                if (allowed.contains(LeaveRecordAction.edit))
                  FilledButton(
                    onPressed: busy ? null : () => perform(LeaveRecordAction.edit),
                    child: const Text('编辑申请'),
                  ),
                if (allowed.contains(LeaveRecordAction.withdraw))
                  OutlinedButton(
                    onPressed: busy ? null : () => perform(LeaveRecordAction.withdraw),
                    child: const Text('撤回申请'),
                  ),
                if (allowed.contains(LeaveRecordAction.print))
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => perform(LeaveRecordAction.print),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('打印官方请假单'),
                  ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final dates = [r['QJKSRQ'], r['QJJSRQ']].where((v) => v.isNotEmpty).join(' 至 ');
    final description = [
      if (dates.isNotEmpty) dates,
      if (r['QJTS'].isNotEmpty) '${r['QJTS']} 天',
      if (r.status.isNotEmpty) r.status,
      if (r['XJZT_DISPLAY'].isNotEmpty) r['XJZT_DISPLAY'],
    ].join(' · ');
    final title = Text(r.type.isEmpty ? '请假申请' : r.type);
    final subtitle = description.isEmpty ? null : Text(description);
    return Padding(
      padding: const EdgeInsets.only(top: TpTokens.space2),
      child: TpCard(
        child: r.id.isEmpty
            ? ListTile(title: title, subtitle: subtitle)
            : ExpansionTile(
                title: title,
                subtitle: subtitle,
                onExpansionChanged: load,
                children: [
                  if (detail != null)
                    FutureBuilder<StudentLeave>(
                      future: detail,
                      builder: (_, snapshot) {
                        if (snapshot.hasError) {
                          final error = snapshot.error;
                          return ListTile(
                            title:
                                Text(error is CampusRequestException ? error.message : '读取请假详情失败'),
                            trailing: TextButton(
                              onPressed: () => setState(
                                () => detail = widget.service.detail(r, widget.service.revision),
                              ),
                              child: const Text('重试'),
                            ),
                          );
                        }
                        final d = snapshot.data;
                        if (d == null) return const LinearProgressIndicator();
                        final rows = {
                          '申请编号': d.id,
                          '审批状态': d.status,
                          '申请日期': d['SQRQ'],
                          '请假性质': d['QJXZ_DISPLAY'],
                          '请假事由': d['QJSY'],
                          '申请说明': d['SQSM'],
                          '请假去向': d['DZ_QJQX'],
                          '详细地址': d['DZ_XXDZ'],
                          '涉及课程': d['DZ_KCMC'],
                        };
                        return Column(
                          children: [
                            for (final e in rows.entries.where((e) => e.value.isNotEmpty))
                              ListTile(dense: true, title: Text(e.key), subtitle: Text(e.value)),
                          ],
                        );
                      },
                    ),
                  if (actions != null) management(),
                ],
              ),
      ),
    );
  }
}

class _SchoolApprovals extends StatefulWidget {
  const _SchoolApprovals({required this.service});
  final StudentLeaveService service;
  @override
  State<_SchoolApprovals> createState() => _SchoolApprovalsState();
}

class _SchoolApprovalsState extends State<_SchoolApprovals> {
  Future<List<LeaveApprovalRecord>>? history;
  LeaveApprovalRecord? selected;
  Future<LeaveApprovalDetail>? detail;
  late final revision = widget.service.revision;

  void reload() {
    setState(() {
      history = widget.service.approvalHistory(revision);
      selected = null;
      detail = null;
    });
  }

  void select(LeaveApprovalRecord record) {
    setState(() {
      selected = record;
      detail = widget.service.approvalDetail(record, revision);
    });
  }

  @override
  Widget build(BuildContext context) => TpCard(
        child: ExpansionTile(
          title: const Text('学校审批意见'),
          onExpansionChanged: (open) {
            if (open) {
              reload();
            } else {
              setState(() {
                history = null;
                selected = null;
                detail = null;
              });
            }
          },
          children: [
            if (history != null)
              FutureBuilder<List<LeaveApprovalRecord>>(
                future: history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) return _readError(snapshot.error, reload);
                  if (snapshot.requireData.isEmpty) return const ListTile(title: Text('暂无请假申请'));
                  return Column(
                    children: [
                      for (final record in snapshot.requireData) ...[
                        ListTile(
                          title: Text(record.title),
                          subtitle: record.period.isEmpty ? null : Text(record.period),
                          selected: selected == record,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => select(record),
                        ),
                        if (record == selected)
                          FutureBuilder<LeaveApprovalDetail>(
                            future: detail,
                            builder: (_, result) {
                              if (result.connectionState != ConnectionState.done) {
                                return const LinearProgressIndicator();
                              }
                              if (result.hasError) {
                                return _readError(result.error, () => select(record));
                              }
                              final item = result.requireData;
                              return Column(
                                children: [
                                  if (item.status.isNotEmpty)
                                    ListTile(
                                      dense: true,
                                      title: const Text('审批状态'),
                                      subtitle: Text(item.status),
                                    ),
                                  if (item.reason.isNotEmpty)
                                    ListTile(
                                      dense: true,
                                      title: const Text('请假事由'),
                                      subtitle: Text(item.reason),
                                    ),
                                  ListTile(
                                    dense: true,
                                    title: const Text('审批意见'),
                                    subtitle: Text(item.comment.isEmpty ? '暂无审批意见' : item.comment),
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    ],
                  );
                },
              ),
          ],
        ),
      );

  Widget _readError(Object? error, VoidCallback retry) => ListTile(
        title: Text(error is CampusRequestException ? error.message : '读取学校审批记录失败'),
        trailing: TextButton(onPressed: retry, child: const Text('重试')),
      );
}
