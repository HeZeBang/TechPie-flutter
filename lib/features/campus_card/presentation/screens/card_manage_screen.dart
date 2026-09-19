import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../domain/models/card_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';
import 'bill_transaction_screen.dart';
import 'bind_card_screen.dart';
import 'offline_screen.dart';
import 'security_hub_screen.dart';
import 'settings_screen.dart';
import 'widget_setup_screen.dart';

/// eCard information and activity. OpenID account management lives in
/// TechPie's Account settings.
final class CardManageScreen extends ConsumerStatefulWidget {
  const CardManageScreen({super.key});

  @override
  ConsumerState<CardManageScreen> createState() => _CardManageScreenState();
}

class _CardManageScreenState extends ConsumerState<CardManageScreen>
    with SingleTickerProviderStateMixin {
  static final DateTimeRange _clearDateRangeSentinel = DateTimeRange(
    start: DateTime.utc(1900),
    end: DateTime.utc(1900),
  );

  int _segment = 0;
  DateTimeRange? _range;
  late final ScrollController _scrollController;
  late final AnimationController _tabController;
  late final Animation<double> _tabOpacity;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_loadMoreIfNeeded);
    _tabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    _tabOpacity = _tabController.drive(CurveTween(curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  TransactionDateRange get _transactionQuery => (
        begin: _range == null
            ? null
            : DateTime(
                _range!.start.year,
                _range!.start.month,
                _range!.start.day,
              ),
        end: _range == null
            ? null
            : DateTime(
                _range!.end.year,
                _range!.end.month,
                _range!.end.day,
                23,
                59,
                59,
              ),
      );

  void _loadMoreIfNeeded() {
    if (_segment != 1 ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 240) {
      return;
    }
    unawaited(
      ref.read(transactionFeedProvider(_transactionQuery).notifier).loadMore(),
    );
  }

  Future<void> _setSegment(int value) async {
    if (value == _segment) return;
    await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.selection);
    if (!mounted) return;
    setState(() => _segment = value);
    if (MediaQuery.disableAnimationsOf(context)) {
      _tabController.value = 1;
    } else {
      unawaited(_tabController.forward(from: 0));
    }
  }

  Future<void> _refreshActivity() async {
    final provider = transactionFeedProvider(_transactionQuery);
    ref.invalidate(provider);
    await ref.read(provider.future);
  }

  Future<void> _pickRange() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final selection = await _showCupertinoRangePicker();
      if (selection == null || !mounted) return;
      await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.selection);
      if (!mounted) return;
      setState(() => _range = selection.clear ? null : selection.range);
      return;
    }
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      useRootNavigator: false,
      initialDateRange: _range ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      saveText: '完成',
      helpText: '日期范围',
      builder: (pickerContext, child) => _AndroidDateRangePickerShell(
        onClear: () => Navigator.of(
          pickerContext,
        ).pop<DateTimeRange>(_clearDateRangeSentinel),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    await ref.read(appRuntimeProvider).feedback.play(FeedbackEvent.selection);
    if (!mounted) return;
    setState(() {
      _range = selected.start == _clearDateRangeSentinel.start &&
              selected.end == _clearDateRangeSentinel.end
          ? null
          : selected;
    });
  }

  Future<_DateRangeSelection?> _showCupertinoRangePicker() {
    final now = DateTime.now();
    var start = _range?.start ?? DateTime(now.year, now.month, 1);
    var end = _range?.end ?? now;
    var editingStart = true;
    return showModalBottomSheet<_DateRangeSelection>(
      context: context,
      useRootNavigator: false,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          height: 390,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.pop(
                        sheetContext,
                        const _DateRangeSelection.clear(),
                      ),
                      child: const Text('不指定日期'),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      onPressed: () => Navigator.pop(
                        sheetContext,
                        _DateRangeSelection.range(
                          DateTimeRange(start: start, end: end),
                        ),
                      ),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: CupertinoSlidingSegmentedControl<bool>(
                  groupValue: editingStart,
                  children: const {
                    true: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Text('开始日期'),
                    ),
                    false: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Text('结束日期'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) {
                      setSheetState(() => editingStart = value);
                    }
                  },
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  key: ValueKey(editingStart),
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: editingStart ? start : end,
                  minimumDate: DateTime(2020),
                  maximumDate: now.add(const Duration(days: 1)),
                  onDateTimeChanged: (value) {
                    setSheetState(() {
                      if (editingStart) {
                        start = value;
                        if (end.isBefore(start)) end = start;
                      } else {
                        end = value;
                        if (start.isAfter(end)) start = end;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(cardControllerProvider);
    final card = cardAsync.valueOrNull;
    final profile = ref.watch(profileControllerProvider).valueOrNull;

    return Scaffold(
      key: const Key('card-manage-page'),
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () => popCampusCard(context),
          ),
          child: switch (cardAsync) {
            AsyncError(:final error) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  ApplePinnedHeaderLayout.contentTop,
                  20,
                  20,
                ),
                child: GpStateView.error(
                  error,
                  onRetry: () => ref.invalidate(cardControllerProvider),
                ),
              ),
            AsyncLoading() when card == null => const Center(
                child: CupertinoActivityIndicator(radius: 13),
              ),
            _ when card == null => Center(
                child: FilledButton(
                  onPressed: () => unawaited(pushCampusCardPage<void>(context, builder: (_) => const BindCardScreen())),
                  child: const Text('绑定卡片'),
                ),
              ),
            _ => CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  if (_segment == 1)
                    EcardSliverRefreshControl(onRefresh: _refreshActivity),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      ApplePinnedHeaderLayout.contentTop,
                      20,
                      52,
                    ),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverList.list(
                          children: [
                            Center(
                              child: SizedBox(
                                width: 164,
                                child: CampusWalletCard(
                                  card: card,
                                  compact: true,
                                  heroTag: 'card-details-thumbnail',
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              '上海科技大学 eCard',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.gpColors.textPrimary,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 26),
                            AppleSegmentedControl(
                              labels: const [
                                '信息',
                                '使用明细',
                              ],
                              selectedIndex: _segment,
                              onChanged: _setSegment,
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                        SliverFadeTransition(
                          opacity: _tabOpacity,
                          sliver: _segment == 0
                              ? SliverToBoxAdapter(
                                  child: _InformationTab(
                                    key: const ValueKey('info'),
                                    card: card,
                                    profilePosition: profile?.positionName,
                                  ),
                                )
                              : _ActivitySliver(
                                  key: const ValueKey('activity'),
                                  range: _range,
                                  onPickRange: _pickRange,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}

final class _InformationTab extends ConsumerWidget {
  const _InformationTab({
    super.key,
    required this.card,
    required this.profilePosition,
  });

  final CampusCard card;
  final String? profilePosition;

  String _date(BuildContext context, DateTime? value) => value == null
      ? '—'
      : DateFormat('yyyy-MM-dd HH:mm:ss').format(value.toLocal());

  String _status(BuildContext context) => switch (card.status) {
        CampusCardStatus.normal => '正常',
        CampusCardStatus.lost => '挂失',
        CampusCardStatus.frozen ||
        CampusCardStatus.manualFrozen =>
          '冻结',
        CampusCardStatus.closed => '销户',
        CampusCardStatus.preclosed => '预销户',
        CampusCardStatus.unknown => '—',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        AppleSection(
          children: [
            AppleListRow(label: '姓名', value: card.ownerName),
            AppleListRow(
              label: '身份',
              value: profilePosition ?? card.positionName,
            ),
            AppleListRow(
              label: '所属单位',
              value: card.departmentName ?? card.schoolName ?? '—',
            ),
            AppleListRow(label: '账户状态', value: _status(context)),
            AppleListRow(
              label: '有效期',
              value: _date(context, card.validUntil),
            ),
            AppleListRow(
              label: '最近登录',
              value: _date(context, card.lastTransactionAt),
            ),
          ],
        ),
        const SizedBox(height: 18),
        AppleSection(
          children: [
            AppleListRow(
              icon: GpPlatformIcons.security(context),
              label: '安全中心',
              onTap: () => unawaited(pushCampusCardPage<void>(context, builder: (_) => const SecurityHubScreen())),
            ),
            AppleListRow(
              icon: GpPlatformIcons.offline(context),
              label: '离线授权',
              onTap: () => unawaited(pushCampusCardPage<void>(context, builder: (_) => const OfflineAuthorizationScreen())),
            ),
            AppleListRow(
              icon: GpPlatformIcons.settings(context),
              label: '设置',
              onTap: () => unawaited(pushCampusCardPage<void>(context, builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        if (Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS) ...[
          const SizedBox(height: 18),
          AppleSection(
            footer: '将消费码放到主屏幕，轻触小组件即可打开。',
            children: [
              AppleListRow(
                key: const Key('add-pay-widget'),
                icon: GpPlatformIcons.homeWidget(context),
                label: '添加消费码小组件',
                onTap: () => unawaited(pushCampusCardPage<void>(context, builder: (_) => const WidgetSetupScreen())),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

final class _ActivitySliver extends ConsumerWidget {
  const _ActivitySliver({
    super.key,
    required this.range,
    required this.onPickRange,
  });

  final DateTimeRange? range;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (
      begin: range == null
          ? null
          : DateTime(range!.start.year, range!.start.month, range!.start.day),
      end: range == null
          ? null
          : DateTime(
              range!.end.year,
              range!.end.month,
              range!.end.day,
              23,
              59,
              59,
            ),
    );
    final transactions = ref.watch(transactionFeedProvider(query));
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: AppleSection(
            children: [
              AppleListRow(
                label: '日期范围',
                value: range == null
                    ? '不指定日期'
                    : '${range!.start.month}月${range!.start.day}日'
                        ' 至 '
                        '${range!.end.month}月${range!.end.day}日',
                icon: GpPlatformIcons.calendar(context),
                onTap: onPickRange,
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        switch (transactions) {
          AsyncData(:final value) => SliverMainAxisGroup(
              slivers: [
                TransactionList(
                  items: value.items,
                  onTap: (record) => unawaited(
                    pushCampusCardPage<void>(context, builder: (_) => BillTransactionScreen(transactionId: record.id)),
                  ),
                ),
                if (value.hasMore) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: CupertinoButton(
                        onPressed: () => unawaited(
                          ref
                              .read(transactionFeedProvider(query).notifier)
                              .loadMore(),
                        ),
                        child: const Text('加载更多'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          AsyncError(:final error) => SliverToBoxAdapter(
              child: GpStateView.error(
                error,
                onRetry: () => ref.invalidate(transactionFeedProvider(query)),
              ),
            ),
          _ => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(42),
                child: CupertinoActivityIndicator(radius: 13),
              ),
            ),
        },
      ],
    );
  }
}

final class _DateRangeSelection {
  const _DateRangeSelection.range(this.range) : clear = false;
  const _DateRangeSelection.clear()
      : clear = true,
        range = null;

  final bool clear;
  final DateTimeRange? range;
}

final class _AndroidDateRangePickerShell extends StatelessWidget {
  const _AndroidDateRangePickerShell({
    required this.child,
    required this.onClear,
  });

  final Widget child;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final actionColor = context.gpColors.action;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
          systemOverlayStyle: theme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.paddingOf(context).bottom + 18,
            child: Material(
              color: Colors.transparent,
              child: OutlinedButton(
                key: const Key('android-date-range-clear'),
                onPressed: onClear,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: actionColor,
                  backgroundColor: actionColor.withValues(alpha: 0.08),
                  side: BorderSide(color: actionColor.withValues(alpha: 0.28)),
                  shape: const StadiumBorder(),
                ),
                child: const Text('不指定日期'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
