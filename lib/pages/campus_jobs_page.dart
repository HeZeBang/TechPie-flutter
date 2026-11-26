import 'dart:async';

import 'package:flutter/material.dart';

import '../models/campus_job.dart';
import '../models/feature.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/emap_client.dart';
import '../services/campus_job_service.dart';
import '../theme/tp_tokens.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/egate_visit.dart';
import 'generic_webview_page.dart';

class CampusJobsPage extends StatelessWidget {
  const CampusJobsPage({super.key});
  @override
  Widget build(BuildContext context) => EgateVisit(
        title: '校园岗位',
        dropWhenInactive: true,
        builder: (client, studentId) => CampusJobPanels(client: client, studentId: studentId),
      );
}

class CampusJobPanels extends StatefulWidget {
  const CampusJobPanels({super.key, required this.client, required this.studentId});
  final EmapClient client;
  final String studentId;
  @override
  State<CampusJobPanels> createState() => _CampusJobPanelsState();
}

class _CampusJobPanelsState extends State<CampusJobPanels> with WidgetsBindingObserver {
  late final service = CampusJobService(widget.client, widget.studentId);
  var program = CampusJobProgram.workStudy;
  int panel = 0;
  bool showPay = false;
  CampusJobOpening? selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (showPay && state != AppLifecycleState.resumed) setState(() => showPay = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    service.dispose();
    super.dispose();
  }

  void load(int next, CampusJobProgram target) {
    setState(() {
      panel = next;
      program = target;
      showPay = false;
      selected = null;
    });
  }

  void openWeb([CampusJobProgram? target]) {
    final current = target ?? program;
    unawaited(
      pushAdaptivePage<void>(
        context,
        builder: (_) => GenericWebViewPage(
          title: current.label,
          url: current.webUrl,
          cookieType: CookieType.egateApp,
        ),
      ),
    );
  }

  void toggleDetail(CampusJobOpening opening) {
    setState(() {
      selected = identical(selected, opening) ? null : opening;
    });
  }

  Future<void> _openApplyDialog(CampusJobOpening job) async {
    final currentProgram = program;
    final submittedMessage = await showDialog<String>(
      context: context,
      builder: (_) => _JobApplyDialog(
        service: service,
        program: currentProgram,
        job: job,
        onWeb: () => openWeb(currentProgram),
      ),
    );
    if (!mounted || submittedMessage == null) return;
    showAdaptiveFeedback(
      context: context,
      message: submittedMessage,
      style: AdaptiveFeedbackStyle.success,
    );
    load(1, currentProgram);
  }

  Widget fields(Map<String, String> values) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in values.entries)
            if (entry.value.isNotEmpty) Text('${entry.key}　${entry.value}'),
        ],
      );

  Widget jobCard(CampusJobOpening job) => TpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(job.title),
              subtitle: fields({
                '单位': job.unit.isEmpty ? job.unitCode : job.unit,
                '学年': job.year,
                '学期': job.term,
                '类别': job.category,
              }),
              trailing: Icon(selected == job ? Icons.expand_less : Icons.expand_more),
              onTap: () => toggleDetail(job),
            ),
            if (selected == job)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TpTokens.space4,
                  vertical: TpTokens.space2,
                ),
                child: EgateQueryResult(
                  key: ObjectKey(job),
                  load: () => service.detail(program, job),
                  builder: (detail) {
                    final merged = job.merge(detail);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail == null)
                          const Text('详细要求请在校园网页查看')
                        else
                          fields({
                            '岗位': detail.title,
                            '单位': detail.unit,
                            '需求人数': detail.headcount,
                            '报酬标准': detail.rate,
                            '结算单位': detail.basis,
                            if (program == CampusJobProgram.teachingAssistant)
                              '每四周报酬': detail.fourWeekPay,
                            '月度上限': detail.monthlyLimit,
                          }),
                        const SizedBox(height: TpTokens.space2),
                        FilledButton.icon(
                          onPressed: () => _openApplyDialog(merged),
                          icon: const Icon(Icons.edit_document),
                          label: const Text('申请岗位'),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      );

  Widget record(CampusJobRecord item) => ListTile(
        title: Text(
          item.job.isNotEmpty ? item.job : (item.reference.isEmpty ? '岗位记录' : item.reference),
        ),
        subtitle: fields({
          '单位': item.unit,
          '申请日期': item.applied,
          '审核状态': item.status,
          '申请理由': item.reason,
          '开始日期': item.start,
          '结束日期': item.end,
        }),
      );

  Widget payPanel(CampusJobEmployment data) {
    String amount(String value) => value.isEmpty
        ? ''
        : showPay
            ? value
            : '••••';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpCard(
          child: ListTile(
            title: const Text('累计发放'),
            subtitle: Text(
              data.totalError ?? (data.total.isEmpty ? '暂无金额' : amount(data.total)),
            ),
            trailing: data.totalError != null
                ? null
                : IconButton(
                    tooltip: showPay ? '隐藏金额' : '显示金额',
                    icon: Icon(showPay ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => showPay = !showPay),
                  ),
          ),
        ),
        const SizedBox(height: TpTokens.space3),
        TpCard(
          title: '上岗记录',
          child: Column(
            children: [
              if (data.positionsError != null)
                ListTile(title: Text(data.positionsError!))
              else if (data.positions.isEmpty)
                const ListTile(title: Text('暂无上岗记录')),
              ...data.positions.map(record),
            ],
          ),
        ),
        const SizedBox(height: TpTokens.space3),
        TpCard(
          title: '月度薪资',
          child: Column(
            children: [
              if (data.paymentsError != null)
                ListTile(title: Text(data.paymentsError!))
              else if (data.payments.isEmpty)
                const ListTile(title: Text('暂无发放记录')),
              for (final pay in data.payments)
                ListTile(
                  title: Text(pay.month.isEmpty ? '发放记录' : pay.month),
                  subtitle: fields({
                    '工时': pay.hours,
                    '报酬标准': amount(pay.rate),
                    '结算金额': amount(pay.calculated),
                    '实发金额': amount(pay.paid),
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('校园岗位')),
        body: EgateVisitBody(
          children: [
            AdaptiveSegmentedControl(
              value: program.index,
              segments: [for (final p in CampusJobProgram.values) p.label],
              onChanged: (i) => load(0, CampusJobProgram.values[i]),
            ),
            Wrap(
              spacing: TpTokens.space2,
              children: [
                for (final (i, label)
                    in ['可申请岗位', '我的申请', if (program == CampusJobProgram.workStudy) '在岗薪资'].indexed)
                  ChoiceChip(
                    selected: panel == i,
                    label: Text(label),
                    onSelected: (_) => load(i, program),
                  ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: openWeb,
              icon: const Icon(Icons.open_in_new),
              label: Text('前往${program.label}网页办理'),
            ),
            if (panel == 0)
              EgateQueryResult(
                key: ValueKey(program),
                load: () => service.openings(program),
                builder: (jobs) => jobs.isEmpty
                    ? const TpCard(child: ListTile(title: Text('暂无可申请岗位')))
                    : Column(
                        children: [
                          for (final job in jobs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: TpTokens.space2),
                              child: jobCard(job),
                            ),
                        ],
                      ),
              ),
            if (panel == 1)
              EgateQueryResult(
                key: ValueKey(program),
                load: () => service.applications(program),
                builder: (items) => TpCard(
                  child: Column(
                    children: [
                      if (items.isEmpty) const ListTile(title: Text('暂无申请记录')),
                      ...items.map(record),
                    ],
                  ),
                ),
              ),
            if (panel == 2) EgateQueryResult(load: service.employment, builder: payPanel),
          ],
        ),
      );
}

class _JobApplyDialog extends StatefulWidget {
  const _JobApplyDialog({
    required this.service,
    required this.program,
    required this.job,
    required this.onWeb,
  });

  final CampusJobService service;
  final CampusJobProgram program;
  final CampusJobOpening job;
  final VoidCallback onWeb;

  @override
  State<_JobApplyDialog> createState() => _JobApplyDialogState();
}

class _JobApplyDialogState extends State<_JobApplyDialog> {
  final _formKey = GlobalKey<FormState>();
  final reasonCtrl = TextEditingController();
  final introCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  bool acceptAdjustment = true;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    reasonCtrl.dispose();
    introCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy) return;
    if (!_formKey.currentState!.validate()) return;
    final ta = widget.program == CampusJobProgram.teachingAssistant;
    final confirm = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '确认提交岗位申请？',
      message: [
        '项目：${widget.program.label}',
        '岗位：${widget.job.title}',
        if (widget.job.unit.isNotEmpty) '单位：${widget.job.unit}',
        '申请理由：${reasonCtrl.text.trim()}',
      ].join('\n'),
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认提交', value: true, isDefault: true),
      ],
    );
    if (confirm != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = ta
          ? await widget.service.applyTeachingAssistant(
              job: widget.job,
              reason: reasonCtrl.text,
              intro: introCtrl.text,
            )
          : await widget.service.applyWorkStudy(
              job: widget.job,
              reason: reasonCtrl.text,
              phone: phoneCtrl.text,
              acceptAdjustment: acceptAdjustment,
              intro: introCtrl.text,
            );
      if (mounted) Navigator.of(context).pop(result);
    } on CampusRequestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '申请提交失败，请检查网络或前往网页申请');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ta = widget.program == CampusJobProgram.teachingAssistant;
    return AlertDialog(
      scrollable: true,
      title: Text('申请${widget.job.title}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ta ? '最多可申请 3 个助教岗位；申请理由不少于 20 字' : '请核对岗位与联系方式后提交申请',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: TpTokens.space3),
              if (!ta) ...[
                TextFormField(
                  key: const ValueKey('job-apply-phone'),
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '联系电话'),
                  validator: (v) => (v ?? '').trim().isEmpty ? '请填写联系电话' : null,
                ),
                const SizedBox(height: TpTokens.space2),
              ],
              TextFormField(
                key: const ValueKey('job-apply-reason'),
                controller: reasonCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(labelText: ta ? '申请理由（不少于 20 字）' : '申请理由'),
                validator: (v) {
                  final text = (v ?? '').trim();
                  if (text.isEmpty) return '请填写申请理由';
                  if (ta && text.length < 20) return '申请理由不少于 20 字';
                  return null;
                },
              ),
              const SizedBox(height: TpTokens.space2),
              TextFormField(
                key: const ValueKey('job-apply-intro'),
                controller: introCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '自我介绍（选填）'),
              ),
              if (!ta)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('服从跨部门调剂'),
                  value: acceptAdjustment,
                  onChanged: busy ? null : (v) => setState(() => acceptAdjustment = v),
                ),
              if (error != null) ...[
                const SizedBox(height: TpTokens.space2),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onWeb();
                },
          child: const Text('网页申请'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(busy ? '提交中…' : '提交申请'),
        ),
      ],
    );
  }
}
