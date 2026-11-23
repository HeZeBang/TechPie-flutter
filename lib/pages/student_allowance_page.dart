import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/student_allowance.dart';
import '../services/service_provider.dart';
import '../services/student_allowance_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/schedule_picker_sheet.dart';
import '../widgets/uni_auth_login.dart';
import 'third_party_accounts_page.dart';

class StudentAllowancePage extends StatelessWidget {
  const StudentAllowancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ServiceProvider.of(context).studentAllowanceService;
    final ios = isIos();
    final overlay = !ios && !usesLegacyIosChrome();
    final padding = EdgeInsets.fromLTRB(
      16,
      16 + (overlay ? adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top : 0),
      16,
      AppShellMetrics.bottomContentPaddingOf(context),
    );
    return Scaffold(
      extendBodyBehindAppBar: overlay,
      appBar: ios
          ? IosNativeNavigationBar(
              title: '学生津贴',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Home',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回首页',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
            )
          : const BlurredAppBar(title: Text('学生津贴')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListenableBuilder(
            listenable: service,
            builder: (context, _) {
              final access = service.access;
              if (access == StudentAllowanceAccess.ready) {
                return _AllowanceQuery(
                  // Changing accounts discards loaded amounts and in-flight UI
                  // state, including when another account is already bound.
                  key: ValueKey((service, service.accountRevision)),
                  service: service,
                  padding: padding,
                );
              }
              final needsLogin = access == StudentAllowanceAccess.signIn;
              return ListView(
                padding: padding,
                children: [
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            needsLogin ? '需要先登录 TechPie' : '需要绑定 IDS 账号',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text('学生津贴使用已绑定的校园 IDS 账号直接向学校财务系统查询。'),
                          const SizedBox(height: 16),
                          AdaptiveButton(
                            onPressed: needsLogin
                                ? () => unawaited(startUniAuthLogin(context))
                                : () => unawaited(
                                      pushAdaptivePage<void>(
                                        context,
                                        builder: (_) => const ThirdPartyAccountsPage(),
                                      ),
                                    ),
                            icon: needsLogin ? Icons.login : Icons.vpn_key_outlined,
                            sfSymbol: needsLogin ? 'person.crop.circle' : 'key.horizontal',
                            label: needsLogin ? '去登录' : '去绑定 IDS',
                            role: AdaptiveButtonRole.prominent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AllowanceQuery extends StatefulWidget {
  const _AllowanceQuery({super.key, required this.service, required this.padding});

  final StudentAllowanceService service;
  final EdgeInsets padding;

  @override
  State<_AllowanceQuery> createState() => _AllowanceQueryState();
}

class _AllowanceQueryState extends State<_AllowanceQuery> {
  static final _firstMonth = DateTime(2000);
  late DateTime _start;
  late DateTime _end;
  late DateTime _currentMonth;
  bool _loading = false;
  String? _error;
  StudentAllowanceReport? _report;

  @override
  void initState() {
    super.initState();
    // The finance site's payment months use China time, even when viewed abroad.
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    _currentMonth = DateTime(now.year, now.month);
    _start = DateTime(now.year, now.month - 11);
    _end = _currentMonth;
  }

  Future<void> _selectMonth({required bool start}) async {
    if (_loading) return;
    final label = start ? '开始月份' : '结束月份';
    var selected = start ? _start : _end;
    final value = await showSchedulePickerSheet<DateTime>(
      context: context,
      title: label,
      selection: () => selected,
      builder: (_) => SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.monthYear,
          initialDateTime: selected,
          minimumDate: _firstMonth,
          maximumDate: _currentMonth,
          minimumYear: _firstMonth.year,
          maximumYear: _currentMonth.year,
          onDateTimeChanged: (month) => selected = month,
        ),
      ),
    );
    if (!mounted || value == null || _loading) return;
    final month = DateTime(value.year, value.month);
    if (month == (start ? _start : _end)) return;
    setState(() {
      if (start) {
        _start = month;
        if (_end.isBefore(month)) _end = month;
      } else {
        _end = month;
        if (_start.isAfter(month)) _start = month;
      }
      _report = null;
      _error = null;
    });
  }

  Future<void> _query() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await widget.service.query(StudentAllowancePeriod(_start, _end));
      if (mounted) setState(() => _report = report);
    } on StudentAllowanceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '查询学生津贴失败，请重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;
    return ListView(
      padding: widget.padding,
      children: [
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('发放月份', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _loading ? null : () => _selectMonth(start: true),
                      child: Text('开始：${_monthText(_start)}'),
                    ),
                    OutlinedButton(
                      onPressed: _loading ? null : () => _selectMonth(start: false),
                      child: Text('结束：${_monthText(_end)}'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AdaptiveButton(
                  onPressed: _query,
                  icon: Icons.search,
                  sfSymbol: 'magnifyingglass',
                  label: '查询津贴',
                  accessibilityLabel: _loading ? '正在查询津贴' : '查询津贴',
                  loading: _loading,
                  role: AdaptiveButtonRole.prominent,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
          )
        else if (report != null) ...[
          if (report.total case final total?) _AllowanceTile(title: '查询区间合计', entry: total),
          if (report.months.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('所选月份没有津贴发放记录'),
            ),
          for (final entry in report.months)
            _AllowanceTile(title: _monthText(entry.month!), entry: entry),
        ] else if (!_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('按月份查询学校财务记录，结果仅在当前页面显示。'),
          ),
      ],
    );
  }
}

class _AllowanceTile extends StatelessWidget {
  const _AllowanceTile({required this.title, required this.entry});

  final String title;
  final StudentAllowanceEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card.outlined(
      child: ExpansionTile(
        title: Text(title),
        subtitle: Text('实发 ${_amountText(entry.netFen)}'),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('应发 ${_amountText(entry.grossFen)}'),
              Text('扣款 ${_amountText(entry.deductionsFen)}'),
              Text('扣税 ${_amountText(entry.taxFen)}'),
            ],
          ),
          for (final category in entry.categories) ...[
            const Divider(),
            Text(category.label, style: text.titleSmall),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('应发 ${_amountText(category.grossFen)}'),
                Text('实发 ${_amountText(category.netFen)}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _monthText(DateTime month) => '${month.year}年${month.month}月';

final _wholeAmount = NumberFormat.decimalPattern('en_US');

String _amountText(int? fen) {
  if (fen == null) return '—';
  final magnitude = fen.abs();
  return '${fen < 0 ? '-' : ''}¥${_wholeAmount.format(magnitude ~/ 100)}'
      '.${(magnitude % 100).toString().padLeft(2, '0')}';
}
