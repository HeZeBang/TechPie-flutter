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
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_page_navigation.dart';
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
    final s = service ?? ServiceProvider.of(context).certificates!;
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
  const _Certificates({super.key, required this.service, this.onShareFile});
  final AcademicCertificateService service;
  final CertificateFileShareFn? onShareFile;
  @override
  State<_Certificates> createState() => _CertificatesState();
}

class _CertificatesState extends State<_Certificates> {
  var kind = CertificateKind.transcript;
  bool busy = false;
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
      builder: (context) => _FormDialog(form: form, kind: kind, service: s, generation: generation),
    );
    if (!mounted || values == null || generation != s.generation) return;
    final summary = form.fields.map((f) {
      final v = values[f.name] ?? f.value;
      return '${f.label} · ${f.options[v] ?? v}';
    }).join('\n');
    final accepted = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '提交${kind.label}申请？',
      message: summary,
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认提交', value: true),
      ],
    );
    if (!mounted || accepted != true || generation != s.generation) return;
    await run(() async {
      final result = await s.apply(kind, form, values);
      if (!mounted || generation != s.generation) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      await s.refresh(kind);
    });
  }

  bool get _canShareCertificate =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> present(CertificateDownload download, {bool share = false}) => run(() async {
        final service = widget.service;
        final generation = service.generation;
        bool current() => mounted && service.generation == generation;
        final bytes = await service.pdf(download);
        if (!current()) return;
        final result = await (widget.onShareFile ?? CampusFileShare.openOrShare)(
          scope: 'certificates',
          filename: 'certificate-${kind.name}.pdf',
          bytes: bytes,
          mimeType: 'application/pdf',
          preferShare: share,
        );
        if (mounted && current() && !result.succeeded && result.path != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('已保存到 ${result.path}')));
        }
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final rows = s.records[kind];
    final native = s.canApply(kind);
    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩单与证明'),
        actions: [
          IconButton(
            tooltip: '在 EAMS 网页中办理',
            icon: const Icon(Icons.open_in_new),
            onPressed: s.ready ? web : null,
          ),
          IconButton(
            tooltip: '刷新记录',
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
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final k in CertificateKind.values)
                          ChoiceChip(
                            label: Text(k.label),
                            selected: k == kind,
                            onSelected: busy
                                ? null
                                : (v) {
                                    if (!v) return;
                                    setState(() => kind = k);
                                    unawaited(refresh());
                                  },
                          ),
                      ],
                    ),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      ListTile(
                        title: Text(error!),
                        trailing: TextButton(onPressed: refresh, child: const Text('重试')),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        icon: Icon(native ? Icons.add : Icons.open_in_new),
                        onPressed: busy
                            ? null
                            : native
                                ? apply
                                : web,
                        label: Text(native ? '新申请' : '在 EAMS 网页中办理'),
                      ),
                    ),
                    if (rows != null && rows.isEmpty) const ListTile(title: Text('暂无申请记录')),
                    for (final row in rows ?? <AcademicCertificate>[])
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final field in row.fields.entries)
                                Text('${field.key} · ${field.value}'),
                              for (final download in row.downloads)
                                Wrap(
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.picture_as_pdf_outlined),
                                      label: Text(download.label),
                                      onPressed: busy ? null : () => present(download),
                                    ),
                                    if (_canShareCertificate)
                                      IconButton(
                                        tooltip: '分享${download.label}',
                                        icon: const Icon(Icons.share_outlined),
                                        onPressed:
                                            busy ? null : () => present(download, share: true),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
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
    if (widget.generation != widget.service.generation && mounted) Navigator.of(context).pop();
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
                          minLines: field.multiline ? 3 : 1,
                          maxLines: field.multiline ? 6 : 1,
                          decoration: InputDecoration(labelText: field.label),
                          onChanged: (v) {
                            values[field.name] = v;
                            if (error != null) setState(() => error = null);
                          },
                        )
                      : DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue:
                              field.options.containsKey(field.value) ? field.value : null,
                          decoration: InputDecoration(labelText: field.label),
                          items: [
                            for (final opt in field.options.entries)
                              DropdownMenuItem(value: opt.key, child: Text(opt.value)),
                          ],
                          onChanged: (v) {
                            values[field.name] = v ?? '';
                            if (error != null) setState(() => error = null);
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
