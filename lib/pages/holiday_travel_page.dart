import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/holiday_travel.dart';
import '../services/campus/campus_errors.dart';
import '../services/holiday_travel_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/design_system/design_system.dart';
import 'emap_history_page.dart';

class HolidayTravelPage extends StatelessWidget {
  const HolidayTravelPage({super.key, this.service});
  final HolidayTravelService? service;

  @override
  Widget build(BuildContext context) {
    final data = service ?? ServiceProvider.of(context).holidayTravelService!;
    return EmapHistoryPage(
      title: '节假日离返校',
      service: data,
      refresh: data.refresh,
      webUrl:
          'https://egate.shanghaitech.edu.cn/xsfw/sys/jjrlfxapp/*default/index.do',
      webLabel: '在学校网页登记离返校',
      content: (loaded) => _Registrations(service: data, loaded: loaded),
    );
  }
}

class _Registrations extends StatefulWidget {
  const _Registrations({required this.service, required this.loaded});
  final HolidayTravelService service;
  final bool loaded;

  @override
  State<_Registrations> createState() => _RegistrationsState();
}

class _RegistrationsState extends State<_Registrations> {
  bool history = false;
  bool composing = false;
  bool preparing = false;
  bool submitting = false;
  bool abroad = false;
  String? message;
  HolidayTravel? source;
  DateTimeRange? dates;
  String _provinceCode = '';
  String _cityCode = '';
  String _districtCode = '';
  String _provinceLabel = '';
  String _cityLabel = '';
  String _districtLabel = '';
  final holidayCodeCtrl = TextEditingController();
  final provinceCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final districtCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final summary = TextEditingController();

  @override
  void dispose() {
    holidayCodeCtrl.dispose();
    provinceCtrl.dispose();
    cityCtrl.dispose();
    districtCtrl.dispose();
    addressCtrl.dispose();
    phoneCtrl.dispose();
    summary.dispose();
    super.dispose();
  }

  void _clearDraftControllers() {
    holidayCodeCtrl.clear();
    provinceCtrl.clear();
    cityCtrl.clear();
    districtCtrl.clear();
    addressCtrl.clear();
    phoneCtrl.clear();
    summary.clear();
    _provinceCode = '';
    _cityCode = '';
    _districtCode = '';
    _provinceLabel = '';
    _cityLabel = '';
    _districtLabel = '';
  }

  void _startFresh() {
    setState(() {
      composing = true;
      history = false;
      preparing = false;
      abroad = false;
      source = null;
      dates = null;
      message = null;
      _clearDraftControllers();
    });
  }

  void _cancelCompose() {
    setState(() {
      composing = false;
      preparing = false;
      source = null;
      dates = null;
      message = null;
      _clearDraftControllers();
    });
  }

  void _syncSummaryFromFields() {
    final region = [
      provinceCtrl.text.trim(),
      cityCtrl.text.trim(),
      districtCtrl.text.trim(),
    ].where((v) => v.isNotEmpty).join(' ');
    final lines = [
      if (dates != null)
        '离校日期：${dateLabel(dates!.start)}\n预计返校日期：${dateLabel(dates!.end)}',
      if (region.isNotEmpty) '省市区：$region',
      if (addressCtrl.text.trim().isNotEmpty) '详细地址：${addressCtrl.text.trim()}',
      '是否出国/出境：${abroad ? '是' : '否'}',
      if (phoneCtrl.text.trim().isNotEmpty) '紧急联系人电话：${phoneCtrl.text.trim()}',
    ];
    summary.text = lines.join('\n');
    setState(() {});
  }

  Future<void> reuse(HolidayTravel record) async {
    final service = widget.service;
    final revision = service.revision;
    setState(() {
      preparing = true;
      composing = true;
      history = false;
      abroad = record['YL8'] == '1';
      source = record;
      dates = null;
      message = null;
      _clearDraftControllers();
    });
    var details = record;
    try {
      details = await service.loadDestination(record, revision);
    } catch (_) {
      if (!mounted || revision != service.revision) return;
      message = '表单详情暂时无法读取，可使用历史记录中的去向。';
    }
    if (!mounted || revision != service.revision) return;
    final defaults = details.destinationDefaults();
    _provinceCode = defaults['QXSF'] ?? '';
    _cityCode = defaults['QXCS'] ?? '';
    _districtCode = defaults['QXQX'] ?? '';
    _provinceLabel = details.fields['QXSF_DISPLAY'] ??
        details.fields['YL5_DISPLAY'] ??
        _provinceCode;
    _cityLabel = details.fields['QXCS_DISPLAY'] ??
        details.fields['YL6_DISPLAY'] ??
        _cityCode;
    _districtLabel = details.fields['QXQX_DISPLAY'] ??
        details.fields['YL7_DISPLAY'] ??
        _districtCode;
    provinceCtrl.text = _provinceLabel;
    cityCtrl.text = _cityLabel;
    districtCtrl.text = _districtLabel;
    addressCtrl.text = defaults['QXDZ'] ?? '';
    phoneCtrl.text = defaults['JJLXRDH'] ?? '';
    final fields = details.reviewFields.entries.where((e) => e.value.isNotEmpty);
    setState(() {
      preparing = false;
      summary.text = fields.map((e) => '${e.key}：${e.value}').join('\n');
    });
  }

  String dateLabel(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _resolveRegionValue(
    TextEditingController ctrl,
    String label,
    String code,
  ) {
    final raw = ctrl.text.trim();
    if (raw == label && code.isNotEmpty) return code;
    return raw;
  }

  String _maskPhone(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 7) {
      return '${trimmed.substring(0, 3)}****${trimmed.substring(trimmed.length - 4)}';
    }
    return trimmed.isEmpty ? '' : '****';
  }

  Future<void> chooseDates() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: dates,
      helpText: '选择本次离校与预计返校日期',
    );
    if (!mounted || selected == null) return;
    if (!HolidayTravel.validDates(selected.start, selected.end)) {
      setState(() => message = '离校日期不能晚于预计返校日期');
      return;
    }
    setState(() {
      dates = selected;
      message = null;
    });
  }

  Future<void> copy() async {
    try {
      final range = dates;
      final text = [
        if (range != null)
          '离校日期：${dateLabel(range.start)}\n预计返校日期：${dateLabel(range.end)}',
        summary.text.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        showAdaptiveFeedback(context: context, message: '已复制登记摘要');
      }
    } on PlatformException {
      if (mounted) setState(() => message = '复制失败，请在摘要中选择并复制文字。');
    }
  }

  Future<void> submitDepartureForm() async {
    if (submitting || preparing) return;
    final range = dates;
    if (range == null) {
      setState(() => message = '请选择本次离校与预计返校日期');
      return;
    }
    if (!HolidayTravel.validDates(range.start, range.end)) {
      setState(() => message = '离校日期不能晚于预计返校日期');
      return;
    }
    final address = addressCtrl.text.trim();
    if (address.isEmpty) {
      setState(() => message = '请填写详细去向地址');
      return;
    }
    final phone = phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => message = '请填写紧急联系人电话');
      return;
    }

    final service = widget.service;
    final revision = service.revision;
    final regionDisplay = [
      provinceCtrl.text.trim(),
      cityCtrl.text.trim(),
      districtCtrl.text.trim(),
    ].where((v) => v.isNotEmpty).join(' ');
    final confirm = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '确认提交离校登记？',
      message: [
        if (holidayCodeCtrl.text.trim().isNotEmpty)
          '节假日代码：${holidayCodeCtrl.text.trim()}',
        '离校日期：${dateLabel(range.start)}',
        '预计返校：${dateLabel(range.end)}',
        if (regionDisplay.isNotEmpty) '去向地区：$regionDisplay',
        '详细地址：$address',
        '是否出国/境：${abroad ? '是' : '否'}',
        '紧急联系人：${_maskPhone(phone)}',
      ].join('\n'),
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认提交', value: true, isDefault: true),
      ],
    );
    if (confirm != true || !mounted || revision != service.revision) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      submitting = true;
      message = null;
    });
    try {
      await service.submitDeparture(
        holidayCode: holidayCodeCtrl.text.trim(),
        departure: range.start,
        expectedReturn: range.end,
        province: _resolveRegionValue(
          provinceCtrl,
          _provinceLabel,
          _provinceCode,
        ),
        city: _resolveRegionValue(cityCtrl, _cityLabel, _cityCode),
        district:
            _resolveRegionValue(districtCtrl, _districtLabel, _districtCode),
        address: address,
        emergencyPhone: phone,
        abroad: abroad,
        expectedRevision: revision,
      );
      var refreshWarning = false;
      try {
        await service.refresh();
      } catch (_) {
        refreshWarning = true;
      }
      if (!mounted || revision != service.revision) return;
      showAdaptiveFeedback(
        context: context,
        message: refreshWarning ? '离校登记已提交，历史记录刷新失败，请下拉刷新' : '离校登记已提交',
        style: refreshWarning
            ? AdaptiveFeedbackStyle.info
            : AdaptiveFeedbackStyle.success,
      );
      setState(() {
        composing = false;
        history = true;
        _clearDraftControllers();
      });
    } on CampusRequestException catch (e) {
      if (mounted && revision == service.revision) {
        setState(() => message = e.message);
      }
    } on FormatException catch (e) {
      if (mounted && revision == service.revision) {
        setState(() => message = e.message);
      }
    } catch (_) {
      if (mounted && revision == service.revision) {
        setState(() => message = '离校登记提交失败，请检查网络或前往校园网页办理');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> confirmReturn(HolidayTravel record) async {
    if (submitting || preparing || record['WID'].isEmpty) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: '选择实际返校日期',
    );
    if (picked == null || !mounted) return;
    final service = widget.service;
    final revision = service.revision;
    final confirm = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '确认提交返校登记？',
      message: [
        if (record.holiday.isNotEmpty) '节假日：${record.holiday}',
        '返校日期：${dateLabel(picked)}',
      ].join('\n'),
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认提交', value: true, isDefault: true),
      ],
    );
    if (confirm != true || !mounted || revision != service.revision) return;

    setState(() {
      submitting = true;
      message = null;
    });
    try {
      await service.submitReturn(
        recordId: record['WID'],
        returnDate: picked,
        expectedRevision: revision,
      );
      var refreshWarning = false;
      try {
        await service.refresh();
      } catch (_) {
        refreshWarning = true;
      }
      if (!mounted || revision != service.revision) return;
      showAdaptiveFeedback(
        context: context,
        message: refreshWarning ? '返校登记已提交，请刷新核对记录' : '返校登记已提交',
        style: refreshWarning
            ? AdaptiveFeedbackStyle.info
            : AdaptiveFeedbackStyle.success,
      );
    } on CampusRequestException catch (e) {
      if (mounted && revision == service.revision) {
        setState(() => message = e.message);
      }
    } on FormatException catch (e) {
      if (mounted && revision == service.revision) {
        setState(() => message = e.message);
      }
    } catch (_) {
      if (mounted && revision == service.revision) {
        setState(() => message = '返校登记提交失败，请前往校园网页核对');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final records = widget.service.history;
    final dated = records.where((r) => r.registrationDate != null).toList()
      ..sort((a, b) => b.registrationDate!.compareTo(a.registrationDate!));
    final latest = records.length == 1 ? records.single : dated.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveSegmentedControl(
          value: history ? 1 : 0,
          segments: const ['登记摘要', '历史记录'],
          onChanged: (idx) => setState(() => history = idx == 1),
        ),
        const SizedBox(height: TpTokens.sectionGap),
        if (history) ...[
          if (message != null) ...[
            TpStateCard.error(title: message!, compact: true),
            const SizedBox(height: TpTokens.space2),
          ],
          if (widget.loaded && records.isEmpty)
            const TpStateCard.empty(
              icon: TpIcons.luggage,
              title: '暂无离返校登记',
              compact: true,
            ),
          for (final r in records)
            Padding(
              padding: const EdgeInsets.only(bottom: TpTokens.space2),
              child: TpCard(
                title: r.holiday.isEmpty ? '离返校登记' : r.holiday,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      title: [r['DJXN'], r.status]
                              .where((v) => v.isNotEmpty)
                              .isEmpty
                          ? null
                          : Text(
                              [r['DJXN'], r.status]
                                  .where((v) => v.isNotEmpty)
                                  .join(' · '),
                            ),
                      subtitle: Text(
                        [
                          if (r['LXRQ'].isNotEmpty) '离校　${r['LXRQ']}',
                          if (r['YJFXRQ'].isNotEmpty) '预计返校　${r['YJFXRQ']}',
                          if (r.region.isNotEmpty) '去向　${r.region}',
                          if (r['DJRQ'].isNotEmpty) '登记日期　${r['DJRQ']}',
                        ].join('\n'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        TpTokens.space2,
                        0,
                        TpTokens.space2,
                        TpTokens.space2,
                      ),
                      child: Wrap(
                        spacing: TpTokens.space2,
                        children: [
                          TextButton(
                            onPressed: (preparing || submitting)
                                ? null
                                : () => reuse(r),
                            child: const Text('复用此记录的去向'),
                          ),
                          if (r['WID'].isNotEmpty)
                            TextButton(
                              onPressed: (preparing || submitting)
                                  ? null
                                  : () => confirmReturn(r),
                              child: const Text('确认返校'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ] else if (composing) ...[
          TpCard(
            title: source == null
                ? '新建离校登记'
                : (source!.holiday.isEmpty
                    ? '登记去向'
                    : '沿用${source!.holiday}去向'),
            trailing: TextButton(
              onPressed: submitting ? null : _cancelCompose,
              child: const Text('取消编辑'),
            ),
            padding: const EdgeInsets.all(TpTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (preparing)
                  const LinearProgressIndicator()
                else ...[
                  if (message != null) ...[
                    TpCard(
                      color: colors.opaqueDangerContainer,
                      borderColor: colors.dangerRed.withValues(alpha: 0.35),
                      padding: const EdgeInsets.all(TpTokens.space3),
                      child: Text(
                        message!,
                        style: TpTypography.itemMeta(colors)
                            .copyWith(color: colors.dangerRed),
                      ),
                    ),
                    const SizedBox(height: TpTokens.space3),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: submitting ? null : chooseDates,
                      icon: const Icon(TpIcons.calendar),
                      label: Text(
                        dates == null
                            ? '添加本次离返校日期'
                            : '${dateLabel(dates!.start)} 至 ${dateLabel(dates!.end)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: TpTokens.space2),
                  TextField(
                    key: const ValueKey('holiday-code'),
                    controller: holidayCodeCtrl,
                    decoration: const InputDecoration(
                      labelText: '节假日代码（选填）',
                      hintText: '留空或由学校当前批次自动匹配',
                    ),
                  ),
                  const SizedBox(height: TpTokens.space2),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('holiday-province'),
                          controller: provinceCtrl,
                          onChanged: (_) => _syncSummaryFromFields(),
                          decoration:
                              const InputDecoration(labelText: '省/直辖市'),
                        ),
                      ),
                      const SizedBox(width: TpTokens.space2),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('holiday-city'),
                          controller: cityCtrl,
                          onChanged: (_) => _syncSummaryFromFields(),
                          decoration: const InputDecoration(labelText: '市'),
                        ),
                      ),
                      const SizedBox(width: TpTokens.space2),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('holiday-district'),
                          controller: districtCtrl,
                          onChanged: (_) => _syncSummaryFromFields(),
                          decoration: const InputDecoration(labelText: '区/县'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TpTokens.space2),
                  TextField(
                    key: const ValueKey('holiday-address'),
                    controller: addressCtrl,
                    onChanged: (_) => _syncSummaryFromFields(),
                    decoration: const InputDecoration(labelText: '详细去向地址'),
                  ),
                  const SizedBox(height: TpTokens.space2),
                  TextField(
                    key: const ValueKey('holiday-phone'),
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => _syncSummaryFromFields(),
                    decoration: const InputDecoration(
                      labelText: '紧急联系人电话',
                      helperText: '仅用于本次页面填报，不写入本地缓存与日志。',
                    ),
                  ),
                  AdaptiveSwitchRow(
                    title: '是否出国/出境',
                    value: abroad,
                    enabled: !submitting,
                    onChanged: (v) {
                      abroad = v;
                      _syncSummaryFromFields();
                    },
                  ),
                  const SizedBox(height: TpTokens.space2),
                  TextField(
                    key: const ValueKey('holiday-summary'),
                    controller: summary,
                    minLines: 3,
                    maxLines: 8,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '本次登记摘要',
                      hintText: '填写本次去向',
                      helperText: '可直接点击提交离校登记，也可复制后到校园网页核对填报。',
                    ),
                  ),
                  const SizedBox(height: TpTokens.space3),
                  Wrap(
                    spacing: TpTokens.space2,
                    runSpacing: TpTokens.space2,
                    children: [
                      FilledButton.icon(
                        onPressed: submitting ? null : submitDepartureForm,
                        icon: const Icon(TpIcons.checkCircle),
                        label: Text(submitting ? '提交中…' : '提交离校登记'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            summary.text.trim().isEmpty ? null : copy,
                        icon: const Icon(TpIcons.copy),
                        label: const Text('复制摘要'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ] else if (widget.loaded)
          TpCard(
            padding: const EdgeInsets.all(TpTokens.space4),
            child: Wrap(
              spacing: TpTokens.space2,
              runSpacing: TpTokens.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (records.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(TpIcons.repeat),
                    label: Text(latest == null ? '选择历史去向' : '复用上次登记去向'),
                    onPressed: () {
                      if (latest != null) {
                        unawaited(reuse(latest));
                      } else {
                        setState(() => history = true);
                      }
                    },
                  ),
                FilledButton.icon(
                  icon: const Icon(TpIcons.edit),
                  label: const Text('新建离校登记'),
                  onPressed: _startFresh,
                ),
                if (records.isEmpty) const Text('暂无历史记录，可直接新建离校登记'),
              ],
            ),
          ),
      ],
    );
  }
}
