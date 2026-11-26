import 'dart:async';

import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../models/pnp_and_minor.dart';
import '../services/campus/campus_errors.dart';
import '../services/pnp_minor_service.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_page_navigation.dart';
import 'generic_webview_page.dart';

class PnpMinorPage extends StatelessWidget {
  const PnpMinorPage({super.key, this.service});
  final PnpMinorService? service;
  @override
  Widget build(BuildContext context) {
    final data = service ?? ServiceProvider.of(context).pnpMinor!;
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) => _Applications(key: ValueKey(data.generation), service: data),
    );
  }
}

class _Applications extends StatefulWidget {
  const _Applications({super.key, required this.service});
  final PnpMinorService service;
  @override
  State<_Applications> createState() => _ApplicationsState();
}

class _ApplicationsState extends State<_Applications> {
  AcademicApplicationTab tab = AcademicApplicationTab.pnp;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.service.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(refresh());
      });
    }
  }

  Future<void> refresh({String? term}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.refresh(tab, semester: term);
    } catch (e) {
      if (mounted) error = e is CampusRequestException ? e.message : '教务数据读取失败';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmRevoke(AcademicApplicationRow row) async {
    final service = widget.service;
    final version = service.generation;
    final term = service.semesters[service.selected];
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '撤销这项申请？',
      message: [if (term != null) term, '将向教务系统申请撤销《${row.title}》的 P/NP 申请。'].join('\n'),
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false, isDefault: true),
        AdaptiveAlertAction(label: '确认撤销', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true || !mounted || busy || version != service.generation) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final message = await service.revoke(row);
      if (mounted && version == service.generation) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } on CampusRequestException catch (e) {
      if (mounted) error = e.message;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final pnp = tab == AcademicApplicationTab.pnp;
    final window = s.windows[tab] ?? ApplicationWindow.unknown;
    return Scaffold(
      appBar: AppBar(
        title: const Text('P/NP 与辅修'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: busy || !s.ready ? null : refresh,
          ),
        ],
      ),
      body: !s.ready
          ? const Center(child: Text('请登录并绑定学校账号'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SegmentedButton<AcademicApplicationTab>(
                      segments: const [
                        ButtonSegment(value: AcademicApplicationTab.pnp, label: Text('P/NP')),
                        ButtonSegment(value: AcademicApplicationTab.minor, label: Text('辅修')),
                      ],
                      selected: {
                        tab,
                      },
                      onSelectionChanged: busy
                          ? null
                          : (v) {
                              setState(() => tab = v.single);
                              unawaited(refresh());
                            },
                    ),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      ListTile(
                        title: Text(error!),
                        trailing: TextButton(onPressed: refresh, child: const Text('重试')),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(pnp ? 'P/NP 申请窗口' : '辅修报名窗口'),
                      subtitle: Text(window.label),
                    ),
                    if (pnp && s.semesters.isNotEmpty)
                      DropdownButton<String>(
                        isExpanded: true,
                        value: s.semesters.containsKey(s.selected) ? s.selected : null,
                        items: [
                          for (final e in s.semesters.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: busy ? null : (v) => refresh(term: v),
                      ),
                    if (window != ApplicationWindow.closed)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: window == ApplicationWindow.open
                            ? FilledButton.icon(
                                icon: const Icon(Icons.open_in_new),
                                label: Text(pnp ? '前往 EAMS 办理 P/NP' : '前往 EAMS 办理辅修报名'),
                                onPressed: () => pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => GenericWebViewPage(
                                    title: pnp ? 'P/NP 申请' : '辅修报名',
                                    url:
                                        'https://eams.shanghaitech.edu.cn${pnp ? PnpMinorService.pnp : PnpMinorService.minor}.action',
                                    cookieType: CookieType.eams,
                                  ),
                                ),
                              )
                            : OutlinedButton.icon(
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('前往 EAMS 查看或办理'),
                                onPressed: () => pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => GenericWebViewPage(
                                    title: pnp ? 'P/NP 申请' : '辅修报名',
                                    url:
                                        'https://eams.shanghaitech.edu.cn${pnp ? PnpMinorService.pnp : PnpMinorService.minor}.action',
                                    cookieType: CookieType.eams,
                                  ),
                                ),
                              ),
                      ),
                    for (final label
                        in pnp ? ['本学期申请', 'P/NP 历史申请'] : ['可报名专业', '我的辅修申请', '已退选', '辅修培养方案'])
                      if (s.sections.containsKey(label) || s.sectionErrors.containsKey(label)) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 20, bottom: 4),
                          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
                        ),
                        if (s.sectionErrors[label] != null)
                          Text('${s.sectionErrors[label]}（不影响其他板块显示）')
                        else if (s.sections[label]!.isEmpty)
                          Text(label == '辅修培养方案' ? '暂无已绑定的辅修培养方案' : '暂无记录'),
                        for (final r in s.sections[label] ?? const <AcademicApplicationRow>[])
                          Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  title: Text(r.title),
                                  subtitle: r.fields.isEmpty
                                      ? null
                                      : Text(
                                          r.fields.entries
                                              .map((f) => '${f.key} · ${f.value}')
                                              .join('\n'),
                                        ),
                                ),
                                if (label == '本学期申请' && s.canRevoke(r))
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(context).colorScheme.error,
                                      ),
                                      onPressed: busy ? null : () => confirmRevoke(r),
                                      child: const Text('撤销申请'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                  ],
                ),
              ),
            ),
    );
  }
}
