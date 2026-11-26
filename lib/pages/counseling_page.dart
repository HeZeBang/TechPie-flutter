import 'dart:async';

import 'package:flutter/material.dart';

import '../models/counseling_reservation.dart';
import '../models/feature.dart';
import '../services/campus/campus_errors.dart';
import '../services/campus/emap_client.dart';
import '../services/counseling_service.dart';
import '../theme/tp_tokens.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/egate_visit.dart';
import 'generic_webview_page.dart';

class CounselingPage extends StatelessWidget {
  const CounselingPage({super.key});
  @override
  Widget build(BuildContext context) => EgateVisit(
        title: '心理咨询',
        dropWhenInactive: true,
        builder: (client, studentId) => CounselingPanels(client: client, studentId: studentId),
      );
}

class CounselingPanels extends StatefulWidget {
  const CounselingPanels({super.key, required this.client, required this.studentId});
  final EmapClient client;
  final String studentId;
  @override
  State<CounselingPanels> createState() => _CounselingPanelsState();
}

class _CounselingPanelsState extends State<CounselingPanels> {
  late final service = CounselingService(widget.client, widget.studentId);
  String? selectedDate;
  int tab = 0;
  int _bookingRevision = 0;

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  void changeTab(int next) {
    setState(() {
      tab = next;
      selectedDate = null;
    });
  }

  void selectDate(String date) {
    setState(() {
      selectedDate = date;
    });
  }

  void _openWebFallback() {
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        adaptivePageRoute<void>(
          builder: (_) => const GenericWebViewPage(
            title: '校园心理咨询',
            url: CounselingService.webUrl,
            cookieType: CookieType.egateApp,
            closeDesktopWindowOnAccountChange: true,
          ),
        ),
      ),
    );
  }

  Future<void> _openBookingDialog(String date, CounselingSlot slot) async {
    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => _CounselingBookingDialog(
        service: service,
        date: date,
        slot: slot,
        onOpenWeb: _openWebFallback,
      ),
    );
    if (!mounted || booked != true) return;
    showAdaptiveFeedback(
      context: context,
      message: '心理咨询预约已提交',
      style: AdaptiveFeedbackStyle.success,
    );
    setState(() {
      _bookingRevision++;
      tab = 0;
      selectedDate = null;
    });
  }

  Widget scheduleList(List<CounselingSlot> items) => TpCard(
        child: Column(
          children: [
            if (items.isEmpty) const ListTile(title: Text('当日暂无排班')),
            for (final item in items)
              ListTile(
                title: Text([item.periodLabel, item.name].where((v) => v.isNotEmpty).join('　')),
                subtitle: Text(
                  [item.time, item.place, item.displayStatus, item.bio]
                      .where((v) => v.isNotEmpty)
                      .join('\n'),
                ),
                trailing: item.isBookable && selectedDate != null
                    ? TextButton(
                        onPressed: () => _openBookingDialog(selectedDate!, item),
                        child: const Text('预约'),
                      )
                    : null,
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('心理咨询')),
        body: EgateVisitBody(
          children: [
            AdaptiveSegmentedControl(
              value: tab,
              segments: const ['我的预约', '日期排班'],
              onChanged: changeTab,
            ),
            OutlinedButton.icon(
              onPressed: _openWebFallback,
              icon: const Icon(Icons.open_in_new),
              label: const Text('在校园网页中预约'),
            ),
            if (tab == 0)
              EgateQueryResult(
                key: ValueKey(('my', _bookingRevision)),
                load: service.myReservations,
                builder: (items) => TpCard(
                  child: Column(
                    children: [
                      if (items.isEmpty)
                        ListTile(
                          title: const Text('暂无预约'),
                          trailing:
                              TextButton(onPressed: () => changeTab(1), child: const Text('查看排班')),
                        ),
                      for (final b in items)
                        ListTile(
                          title: Text([b.date, b.period].where((v) => v.isNotEmpty).join('　')),
                          subtitle: Text(
                            [b.name, b.place, b.bio, b.contact]
                                .where((v) => v.isNotEmpty)
                                .join('\n'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (tab == 1)
              EgateQueryResult(
                load: service.dates,
                builder: (items) => items.isEmpty
                    ? const TpCard(child: ListTile(title: Text('暂无可预约日期')))
                    : Wrap(
                        spacing: TpTokens.space2,
                        children: [
                          for (final date in items)
                            ChoiceChip(
                              label: Text(date),
                              selected: selectedDate == date,
                              onSelected: (_) => selectDate(date),
                            ),
                        ],
                      ),
              ),
            if (tab == 1 && selectedDate != null)
              EgateQueryResult(
                key: ValueKey(selectedDate),
                load: () => service.slots(selectedDate!),
                builder: scheduleList,
              ),
          ],
        ),
      );
}

class _CounselingBookingDialog extends StatefulWidget {
  const _CounselingBookingDialog({
    required this.service,
    required this.date,
    required this.slot,
    required this.onOpenWeb,
  });

  final CounselingService service;
  final String date;
  final CounselingSlot slot;
  final VoidCallback onOpenWeb;

  @override
  State<_CounselingBookingDialog> createState() => _CounselingBookingDialogState();
}

class _CounselingBookingDialogState extends State<_CounselingBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  final phoneCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    phoneCtrl.dispose();
    noteCtrl.dispose();
    super.dispose();
  }

  String _maskPhone(String input) {
    final value = input.trim();
    if (value.length == 11) {
      return '${value.substring(0, 3)}****${value.substring(7)}';
    }
    return '****';
  }

  Future<void> _submit() async {
    if (busy) return;
    if (!_formKey.currentState!.validate()) return;
    final phone = phoneCtrl.text.trim();
    final confirm = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '确认提交心理咨询预约？',
      message: [
        '日期：${widget.date}',
        if (widget.slot.periodLabel.isNotEmpty || widget.slot.time.isNotEmpty)
          '时段：${[widget.slot.periodLabel, widget.slot.time].where((v) => v.isNotEmpty).join(' ')}',
        if (widget.slot.name.isNotEmpty) '咨询师：${widget.slot.name}',
        '手机号：${_maskPhone(phone)}',
      ].join('\n'),
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认预约', value: true, isDefault: true),
      ],
    );
    if (confirm != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.bookSlot(
        date: widget.date,
        slot: widget.slot,
        phone: phone,
        note: noteCtrl.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on CampusRequestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '预约提交失败，请检查网络或前往校园网页办理');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('预约心理咨询'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [
                  widget.date,
                  widget.slot.periodLabel,
                  widget.slot.name,
                ].where((v) => v.isNotEmpty).join(' · '),
              ),
              const SizedBox(height: TpTokens.space3),
              TextFormField(
                key: const ValueKey('counseling-phone'),
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: '手机号（11 位）'),
                validator: (v) =>
                    CounselingService.validPhone(v ?? '') ? null : '请输入 11 位中国大陆手机号',
              ),
              const SizedBox(height: TpTokens.space2),
              TextFormField(
                key: const ValueKey('counseling-note'),
                controller: noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '咨询简述（选填）'),
              ),
              const SizedBox(height: TpTokens.space2),
              Text(
                '仅本次访问内存保留，离开页面或换号自动清空',
                style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () {
                  Navigator.of(context).pop(false);
                  widget.onOpenWeb();
                },
          child: const Text('网页完整预约'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(busy ? '提交中…' : '提交预约'),
        ),
      ],
    );
  }
}
