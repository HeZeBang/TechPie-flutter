import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/academic_certificate.dart';
import '../models/feature.dart';
import '../services/academic_certificate_service.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/campus_file_share.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_progress_indicator.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/campus_prerequisite_view.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/page_refresh.dart';
import 'generic_webview_page.dart';

typedef CertificateFileShareFn = Future<CampusFileOpenResult> Function({
  required String scope,
  required String filename,
  required List<int> bytes,
  String? mimeType,
  bool preferShare,
});

class AcademicCertificatesPage extends StatelessWidget {
  const AcademicCertificatesPage({super.key, this.service, this.onShareFile});
  final AcademicCertificateService? service;
  final CertificateFileShareFn? onShareFile;

  @override
  Widget build(BuildContext context) {
    final s = service ??
        context
            .dependOnInheritedWidgetOfExactType<ServiceProvider>()
            ?.certificates;
    if (s == null) {
      return Scaffold(
        backgroundColor: context.tpColors.canvas,
        appBar: AdaptiveNavigationScaffold.adaptiveBar(
          ios: () => IosNativeNavigationBar(
            title: '成绩单与证明',
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
          material: () => const BlurredAppBar(title: Text('成绩单与证明')),
        ),
        body: const CampusPrerequisiteView(
          icon: TpIcons.document,
          title: '成绩单与证明',
          fallbackText: '请登录并绑定学校账号',
        ),
      );
    }
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _Certificates(
        key: ValueKey(s.generation),
        service: s,
        onShareFile: onShareFile,
      ),
    );
  }
}

class _Certificates extends StatefulWidget {
  const _Certificates({
    super.key,
    required this.service,
    this.onShareFile,
  });

  final AcademicCertificateService service;
  final CertificateFileShareFn? onShareFile;

  @override
  State<_Certificates> createState() => _CertificatesState();
}

class _CertificatesState extends State<_Certificates> {
  var kind = CertificateKind.transcript;
  bool busy = false;
  String? _activeDownloadKey;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.service.ready) unawaited(refresh());
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = switch (e) {
            CampusRequestException(:final message) => message,
            FormatException(:final message) => message,
            _ => '请求失败，请重试',
          },
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() => run(() => widget.service.refresh(kind));

  void web() => pushAdaptivePage<void>(
        context,
        builder: (_) => GenericWebViewPage(
          title: kind.label,
          url: kind.entry.toString(),
          cookieType: CookieType.eams,
        ),
      );

  Future<void> apply() async {
    final s = widget.service;
    final generation = s.generation;
    CertificateForm? opened;
    await run(() async {
      opened = await s.openForm(kind);
    });
    final form = opened;
    if (form == null || !mounted || generation != s.generation) return;
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) =>
          _FormDialog(form: form, kind: kind, service: s, generation: generation),
    );
    if (!mounted || values == null || generation != s.generation) return;
    final submitted = form.values(values);
    final summary = form.fields.map((f) {
      final v = f.readOnly ? f.value : (submitted[f.name] ?? f.value);
      return '${f.label} · ${f.options[v] ?? v}';
    }).join('\n');
    final accepted = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '提交${kind.label}申请？',
      message: summary,
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认提交', value: true, isDefault: true),
      ],
    );
    if (!mounted || accepted != true || generation != s.generation) return;
    await run(() async {
      final result = await s.apply(kind, form, submitted);
      if (!mounted || generation != s.generation) return;
      showAdaptiveFeedback(
        context: context,
        message: result,
        style: AdaptiveFeedbackStyle.success,
      );
      await s.refresh(kind);
    });
  }

  bool get _canShareCertificate =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> present(
    CertificateDownload download, {
    required String keyId,
    required String filename,
    bool share = false,
  }) =>
      run(() async {
        setState(() => _activeDownloadKey = keyId);
        try {
          final service = widget.service;
          final generation = service.generation;
          bool current() => mounted && service.generation == generation;
          final bytes = await service.pdf(download);
          if (!current()) return;
          final result =
              await (widget.onShareFile ?? CampusFileShare.openOrShare)(
            scope: 'certificates',
            filename: filename,
            bytes: bytes,
            mimeType: 'application/pdf',
            preferShare: share,
          );
          if (mounted && current() && !result.succeeded && result.path != null) {
            showAdaptiveFeedback(
              context: context,
              message: '已保存到 ${result.path}',
              style: AdaptiveFeedbackStyle.success,
            );
          }
        } finally {
          if (mounted) setState(() => _activeDownloadKey = null);
        }
      });

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final s = widget.service;
    final rows = s.records[kind];
    final native = s.canApply(kind);
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '成绩单与证明',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '返回',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回',
              placementGroup: 'leading-main',
            ),
          ],
          trailingItems: [
            IosNativeNavigationBarItem(
              id: 'web',
              sfSymbol: 'safari',
              accessibilityLabel: '在 EAMS 网页中办理',
              enabled: s.ready,
              placementGroup: 'trailing-main',
            ),
            IosNativeNavigationBarItem(
              id: 'refresh',
              sfSymbol: 'arrow.clockwise',
              accessibilityLabel: '刷新记录',
              enabled: !busy && s.ready,
              placementGroup: 'trailing-main',
            ),
          ],
          onItemPressed: (id) {
            switch (id) {
              case 'back':
                unawaited(maybePopAdaptivePage<void>(context));
              case 'web':
                web();
              case 'refresh':
                unawaited(refresh());
            }
          },
        ),
        material: () => BlurredAppBar(
          title: const Text('成绩单与证明'),
          actions: [
            IconButton(
              tooltip: '在 EAMS 网页中办理',
              icon: const Icon(TpIcons.externalLink),
              onPressed: s.ready ? web : null,
            ),
            PageRefreshButton(
              onRefresh: refresh,
              enabled: s.ready,
              refreshing: busy,
            ),
            if (!isDesktop())
              IconButton(
                tooltip: '刷新记录',
                icon: const Icon(TpIcons.refresh),
                onPressed: busy || !s.ready ? null : refresh,
              ),
          ],
        ),
      ),
      body: !s.ready
          ? const CampusPrerequisiteView(
              icon: TpIcons.document,
              title: '成绩单与证明',
              fallbackText: '请登录并绑定学校账号',
            )
          : PageRefreshIndicator(
              onRefresh: refresh,
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
                        AdaptiveSegmentedControl(
                          value: CertificateKind.values.indexOf(kind),
                          segments: [
                            for (final k in CertificateKind.values) k.label,
                          ],
                          enabled: !busy,
                          onChanged: (idx) {
                            final next = CertificateKind.values[idx];
                            if (next == kind) return;
                            setState(() => kind = next);
                            unawaited(refresh());
                          },
                        ),
                        if (busy && _activeDownloadKey == null) ...[
                          const SizedBox(height: TpTokens.space2),
                          const LinearProgressIndicator(),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: TpTokens.space3),
                          TpStateCard.error(
                            title: '操作失败',
                            message: error,
                            compact: true,
                            onPrimaryAction: refresh,
                          ),
                        ],
                        const SizedBox(height: TpTokens.space3),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FilledButton.icon(
                            icon: Icon(
                              native ? TpIcons.add : TpIcons.externalLink,
                            ),
                            onPressed: busy
                                ? null
                                : native
                                    ? apply
                                    : web,
                            label: Text(native ? '新申请' : '在 EAMS 网页中办理'),
                          ),
                        ),
                        const SizedBox(height: TpTokens.space3),
                        if (rows != null && rows.isEmpty)
                          const TpStateCard.empty(
                            icon: TpIcons.document,
                            title: '暂无申请记录',
                            compact: true,
                          ),
                        for (var rIdx = 0; rIdx < (rows?.length ?? 0); rIdx++)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: TpTokens.space3,
                            ),
                            child: TpCard(
                              padding: const EdgeInsets.all(TpTokens.space4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final field
                                      in rows![rIdx].fields.entries)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: TpTokens.space1,
                                      ),
                                      child: Text(
                                        '${field.key} · ${field.value}',
                                        style: TpTypography.itemTitle(colors)
                                            .copyWith(fontSize: 14),
                                      ),
                                    ),
                                  for (var dIdx = 0;
                                      dIdx < rows[rIdx].downloads.length;
                                      dIdx++)
                                    Builder(
                                      builder: (context) {
                                        final download =
                                            rows[rIdx].downloads[dIdx];
                                        final keyId = '$rIdx:$dIdx:${download.url}';
                                        final filename =
                                            rows[rIdx].downloads.length == 1
                                                ? 'certificate-${kind.name}.pdf'
                                                : 'certificate-${kind.name}-${dIdx + 1}.pdf';
                                        final downloading =
                                            _activeDownloadKey == keyId;
                                        return Wrap(
                                          spacing: TpTokens.space1,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            TextButton.icon(
                                              icon: downloading
                                                  ? const AdaptiveActivityIndicator(
                                                      size: 16,
                                                      strokeWidth: 2,
                                                    )
                                                  : const Icon(
                                                      TpIcons.document,
                                                    ),
                                              label: Text(download.label),
                                              onPressed: busy
                                                  ? null
                                                  : () => present(
                                                        download,
                                                        keyId: keyId,
                                                        filename: filename,
                                                      ),
                                            ),
                                            if (_canShareCertificate)
                                              IconButton(
                                                tooltip:
                                                    '分享${download.label}',
                                                icon:
                                                    const Icon(TpIcons.share),
                                                onPressed: busy
                                                    ? null
                                                    : () => present(
                                                          download,
                                                          keyId: keyId,
                                                          filename: filename,
                                                          share: true,
                                                        ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _FormDialog extends StatefulWidget {
  const _FormDialog({
    required this.kind,
    required this.form,
    required this.service,
    required this.generation,
  });

  final CertificateKind kind;
  final CertificateForm form;
  final AcademicCertificateService service;
  final int generation;

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final values = <String, String>{};
  String? error;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(accountChanged);
  }

  void accountChanged() {
    if (widget.generation != widget.service.generation && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('申请${widget.kind.label}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in widget.form.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: TpTokens.space3),
                  child: field.options.isEmpty
                      ? TextFormField(
                          initialValue: field.value,
                          readOnly: field.readOnly,
                          enabled: !field.readOnly,
                          minLines: field.multiline ? 3 : 1,
                          maxLines: field.multiline ? 6 : 1,
                          decoration: InputDecoration(labelText: field.label),
                          onChanged: field.readOnly
                              ? null
                              : (v) {
                                  values[field.name] = v;
                                  if (error != null) {
                                    setState(() => error = null);
                                  }
                                },
                        )
                      : AdaptiveSelect(
                          label: field.label,
                          width: double.infinity,
                          enabled: !field.readOnly,
                          value: field.options.containsKey(
                                  values[field.name] ?? field.value,
                                )
                              ? (values[field.name] ?? field.value)
                              : null,
                          placeholder: '请选择${field.label}',
                          options: [
                            for (final opt in field.options.entries)
                              AdaptiveSelectOption(
                                value: opt.key,
                                label: opt.value,
                              ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              values[field.name] = v;
                              error = null;
                            });
                          },
                        ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TpTypography.itemMeta(context.tpColors)
                      .copyWith(color: context.tpColors.dangerRed),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                widget.form.values(values);
                Navigator.pop(context, values);
              } on FormatException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('核对申请'),
          ),
        ],
      );
}
