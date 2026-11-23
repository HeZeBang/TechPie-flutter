import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/student_allowance.dart';
import '../services/service_provider.dart';
import '../services/student_allowance_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/schedule_picker_sheet.dart';
import '../widgets/uni_auth_login.dart';
import 'third_party_accounts_page.dart';

class StudentAllowancePage extends StatelessWidget {
  const StudentAllowancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final service = ServiceProvider.of(context).studentAllowanceService;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space4,
    );
    final padding = EdgeInsets.fromLTRB(
      TpTokens.pageHorizontalPadding,
      topInset,
      TpTokens.pageHorizontalPadding,
      AppShellMetrics.bottomContentPaddingOf(context),
    );
    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '学生津贴',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '首页',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回首页',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
        ),
        material: () => const BlurredAppBar(title: Text('学生津贴')),
      ),
      body: ListenableBuilder(
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
              TpPageBody(
                child: TpCard(
                  padding: const EdgeInsets.all(TpTokens.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: colors.brandSoft,
                              borderRadius:
                                  BorderRadius.circular(TpTokens.radiusS),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              TpIcons.allowance,
                              size: TpTokens.iconM,
                              color: colors.brand,
                            ),
                          ),
                          const SizedBox(width: TpTokens.space3),
                          Expanded(
                            child: Text(
                              needsLogin ? '需要先登录 TechPie' : '需要绑定 IDS 账号',
                              style: TpTypography.cardTitle(colors)
                                  .copyWith(fontSize: 17),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TpTokens.space3),
                      Text(
                        '学生津贴使用已绑定的校园 IDS 账号直接向学校财务系统查询。',
                        style: TpTypography.itemMeta(colors).copyWith(
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: TpTokens.space4),
                      AdaptiveButton(
                        onPressed: needsLogin
                            ? () => unawaited(startUniAuthLogin(context))
                            : () => unawaited(
                                  pushAdaptivePage<void>(
                                    context,
                                    builder: (_) =>
                                        const ThirdPartyAccountsPage(),
                                  ),
                                ),
                        icon:
                            needsLogin ? TpIcons.login : TpIcons.linkedAccounts,
                        sfSymbol: needsLogin
                            ? 'person.crop.circle'
                            : 'key.horizontal',
                        label: needsLogin ? '去登录' : '去绑定 IDS',
                        height: 44,
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
    );
  }
}

class _AllowanceQuery extends StatefulWidget {
  const _AllowanceQuery({
    super.key,
    required this.service,
    required this.padding,
  });

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
      final report =
          await widget.service.query(StudentAllowancePeriod(_start, _end));
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
    final colors = context.tpColors;
    final report = _report;
    return ListView(
      padding: widget.padding,
      children: [
        TpPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpCard(
                leadingIcon: TpIcons.calendar,
                title: '发放月份',
                padding: const EdgeInsets.fromLTRB(
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space1,
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: TpTokens.space2,
                      runSpacing: TpTokens.space2,
                      children: [
                        OutlinedButton(
                          onPressed:
                              _loading ? null : () => _selectMonth(start: true),
                          child: Text('开始：${_monthText(_start)}'),
                        ),
                        OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => _selectMonth(start: false),
                          child: Text('结束：${_monthText(_end)}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: TpTokens.space3),
                    AdaptiveButton(
                      onPressed: _query,
                      icon: TpIcons.search,
                      sfSymbol: 'magnifyingglass',
                      label: '查询津贴',
                      accessibilityLabel: _loading ? '正在查询津贴' : '查询津贴',
                      loading: _loading,
                      height: 44,
                      role: AdaptiveButtonRole.prominent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TpTokens.sectionGap),
              if (_error case final error?)
                TpCard(
                  color: colors.dangerRed
                      .withValues(alpha: colors.isDark ? 0.16 : 0.08),
                  borderColor: colors.dangerRed.withValues(alpha: 0.25),
                  padding: const EdgeInsets.all(TpTokens.space4),
                  child: Text(
                    error,
                    style: TpTypography.itemMeta(colors).copyWith(
                      color: colors.dangerRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else if (report != null) ...[
                if (report.total case final total?) ...[
                  _AllowanceTile(title: '查询区间合计', entry: total, isTotal: true),
                  const SizedBox(height: TpTokens.sectionGap),
                ],
                if (report.months.isEmpty)
                  TpCard(
                    padding: const EdgeInsets.all(TpTokens.space4),
                    child: Text(
                      '所选月份没有津贴发放记录',
                      style: TpTypography.itemMeta(colors).copyWith(
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                for (final entry in report.months) ...[
                  _AllowanceTile(
                    title: _monthText(entry.month!),
                    entry: entry,
                  ),
                  const SizedBox(height: TpTokens.space2),
                ],
              ] else if (!_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TpTokens.space2,
                    vertical: TpTokens.space1,
                  ),
                  child: Text(
                    '按月份查询学校财务记录，结果仅在当前页面显示。',
                    style: TpTypography.itemMeta(colors),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AllowanceTile extends StatelessWidget {
  const _AllowanceTile({
    required this.title,
    required this.entry,
    this.isTotal = false,
  });

  final String title;
  final StudentAllowanceEntry entry;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return TpCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: TpTypography.itemTitle(colors),
          ),
          subtitle: Text(
            '实发 ${_amountText(entry.netFen)}',
            style: TpTypography.itemMeta(colors).copyWith(
              color: isTotal ? colors.brand : colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          childrenPadding: const EdgeInsets.fromLTRB(
            TpTokens.cardPaddingHorizontal,
            0,
            TpTokens.cardPaddingHorizontal,
            TpTokens.space4,
          ),
          children: [
            Wrap(
              spacing: TpTokens.space4,
              runSpacing: TpTokens.space1,
              children: [
                Text(
                  '应发 ${_amountText(entry.grossFen)}',
                  style: TpTypography.itemMeta(colors),
                ),
                Text(
                  '扣款 ${_amountText(entry.deductionsFen)}',
                  style: TpTypography.itemMeta(colors),
                ),
                Text(
                  '扣税 ${_amountText(entry.taxFen)}',
                  style: TpTypography.itemMeta(colors),
                ),
              ],
            ),
            for (final category in entry.categories) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: TpTokens.space2),
                child: Divider(height: 1, thickness: 0.5, color: colors.divider),
              ),
              Text(
                category.label,
                style: TpTypography.itemTitle(colors).copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: TpTokens.space4,
                runSpacing: TpTokens.space1,
                children: [
                  Text(
                    '应发 ${_amountText(category.grossFen)}',
                    style: TpTypography.itemMeta(colors),
                  ),
                  Text(
                    '实发 ${_amountText(category.netFen)}',
                    style: TpTypography.itemMeta(colors),
                  ),
                ],
              ),
            ],
          ],
        ),
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
