import 'dart:async';

import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../models/pnp_and_minor.dart';
import '../services/campus/campus_errors.dart';
import '../services/pnp_minor_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/page_refresh.dart';
import 'generic_webview_page.dart';

class PnpMinorPage extends StatelessWidget {
  const PnpMinorPage({super.key, this.service});
  final PnpMinorService? service;

  @override
  Widget build(BuildContext context) {
    final data = service ??
        context
            .dependOnInheritedWidgetOfExactType<ServiceProvider>()
            ?.pnpMinor;
    if (data == null) {
      return Scaffold(
        backgroundColor: context.tpColors.canvas,
        appBar: const BlurredAppBar(title: Text('P/NP 与辅修')),
        body: const CampusPrerequisiteView(
          icon: TpIcons.pnpMinor,
          title: 'P/NP 与辅修',
          fallbackText: '请登录并绑定学校账号',
        ),
      );
    }
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) =>
          _Applications(key: ValueKey(data.generation), service: data),
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
  int _request = 0;

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
    final rev = ++_request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.refresh(tab, semester: term);
    } catch (e) {
      if (mounted && rev == _request) {
        error = e is CampusRequestException ? e.message : '教务数据读取失败';
      }
    } finally {
      if (mounted && rev == _request) setState(() => busy = false);
    }
  }

  Future<void> confirmRevoke(AcademicApplicationRow row) async {
    if (busy) return;
    final service = widget.service;
    final version = service.generation;
    final term = service.semesters[service.selected];
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '撤销这项申请？',
      message: [
        if (term != null) term,
        '将向教务系统申请撤销《${row.title}》的 P/NP 申请。',
      ].join('\n'),
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false, isDefault: true),
        AdaptiveAlertAction(label: '确认撤销', value: true, isDestructive: true),
      ],
    );
    if (confirmed != true ||
        !mounted ||
        busy ||
        version != service.generation) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final message = await service.revoke(row);
      if (mounted && version == service.generation) {
        showAdaptiveFeedback(
          context: context,
          message: message,
          style: AdaptiveFeedbackStyle.success,
        );
      }
    } catch (e) {
      if (mounted && version == service.generation) {
        final msg = e is CampusRequestException ? e.message : '撤销失败，请刷新核对';
        setState(() => error = msg);
        showAdaptiveFeedback(
          context: context,
          message: msg,
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final s = widget.service;
    final pnp = tab == AcademicApplicationTab.pnp;
    final window = s.windows[tab] ?? ApplicationWindow.unknown;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: BlurredAppBar(
        title: const Text('P/NP 与辅修'),
        actions: [
          PageRefreshButton(
            onRefresh: () => refresh(),
            enabled: s.ready,
            refreshing: busy,
          ),
          if (!isDesktop())
            IconButton(
              tooltip: '刷新',
              icon: const Icon(TpIcons.refresh),
              onPressed: busy || !s.ready ? null : () => refresh(),
            ),
        ],
      ),
      body: !s.ready
          ? const CampusPrerequisiteView(
              icon: TpIcons.pnpMinor,
              title: 'P/NP 与辅修',
              fallbackText: '请登录并绑定学校账号',
            )
          : PageRefreshIndicator(
              onRefresh: () => refresh(),
              child: ListView(
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
                        SegmentedButton<AcademicApplicationTab>(
                          segments: const [
                            ButtonSegment(
                              value: AcademicApplicationTab.pnp,
                              label: Text('P/NP'),
                            ),
                            ButtonSegment(
                              value: AcademicApplicationTab.minor,
                              label: Text('辅修'),
                            ),
                          ],
                          selected: {tab},
                          onSelectionChanged: (v) {
                            setState(() => tab = v.single);
                            unawaited(refresh());
                          },
                        ),
                        if (busy) ...[
                          const SizedBox(height: TpTokens.space2),
                          const LinearProgressIndicator(),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: TpTokens.space3),
                          TpStateCard.error(
                            title: '操作异常',
                            message: error,
                            compact: true,
                            onPrimaryAction: () => refresh(),
                          ),
                        ],
                        const SizedBox(height: TpTokens.space3),
                        TpCard(
                          child: ListTile(
                            title: Text(pnp ? 'P/NP 申请窗口' : '辅修报名窗口'),
                            subtitle: Text(window.label),
                            trailing: TpBadge(
                              label: window.label,
                              tone: switch (window) {
                                ApplicationWindow.open => TpBadgeTone.success,
                                ApplicationWindow.closed => TpBadgeTone.muted,
                                ApplicationWindow.unknown => TpBadgeTone.warning,
                              },
                            ),
                          ),
                        ),
                        if (pnp && s.semesters.isNotEmpty) ...[
                          const SizedBox(height: TpTokens.space2),
                          DropdownButton<String>(
                            isExpanded: true,
                            value: s.semesters.containsKey(s.selected)
                                ? s.selected
                                : null,
                            items: [
                              for (final e in s.semesters.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                            ],
                            onChanged:
                                busy ? null : (v) => refresh(term: v),
                          ),
                        ],
                        if (window != ApplicationWindow.closed) ...[
                          const SizedBox(height: TpTokens.space3),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: window == ApplicationWindow.open
                                ? FilledButton.icon(
                                    icon: const Icon(TpIcons.externalLink),
                                    label: Text(
                                      pnp ? '前往 EAMS 办理 P/NP' : '前往 EAMS 办理辅修报名',
                                    ),
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
                                    icon: const Icon(TpIcons.externalLink),
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
                        ],
                        for (final label in pnp
                            ? ['本学期申请', 'P/NP 历史申请']
                            : ['可报名专业', '我的辅修申请', '已退选', '辅修培养方案'])
                          if (s.sections.containsKey(label) ||
                              s.sectionErrors.containsKey(label)) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: TpTokens.space5,
                                bottom: TpTokens.space2,
                              ),
                              child: Text(
                                label,
                                style: TpTypography.cardTitle(colors),
                              ),
                            ),
                            if (s.sectionErrors[label] != null)
                              TpCard(
                                padding: const EdgeInsets.all(TpTokens.space3),
                                child: Text(
                                  '${s.sectionErrors[label]}（不影响其他板块显示）',
                                  style: TpTypography.itemMeta(colors),
                                ),
                              )
                            else if (s.sections[label]!.isEmpty)
                              TpCard(
                                padding: const EdgeInsets.all(TpTokens.space3),
                                child: Text(
                                  label == '辅修培养方案'
                                      ? '暂无已绑定的辅修培养方案'
                                      : '暂无记录',
                                  style: TpTypography.itemMeta(colors),
                                ),
                              ),
                            for (final r in s.sections[label] ??
                                const <AcademicApplicationRow>[])
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: TpTokens.space2,
                                ),
                                child: TpCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ListTile(
                                        title: Text(r.title),
                                        subtitle: r.fields.isEmpty
                                            ? null
                                            : Text(
                                                r.fields.entries
                                                    .map(
                                                      (f) =>
                                                          '${f.key} · ${f.value}',
                                                    )
                                                    .join('\n'),
                                              ),
                                      ),
                                      if (label == '本学期申请' && s.canRevoke(r))
                                        Align(
                                          alignment:
                                              AlignmentDirectional.centerEnd,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: colors.dangerRed,
                                            ),
                                            onPressed: busy
                                                ? null
                                                : () => confirmRevoke(r),
                                            child: const Text('撤销申请'),
                                          ),
                                        ),
                                    ],
                                  ),
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
}
