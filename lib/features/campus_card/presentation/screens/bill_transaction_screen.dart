import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../domain/models/bill_models.dart';
import '../../domain/models/merchant_alias_models.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';
import 'merchant_contribution_screen.dart';

final class BillTransactionScreen extends ConsumerWidget {
  const BillTransactionScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(transactionDetailProvider(transactionId));
    return Scaffold(
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () => popCampusCard(context),
          ),
          title: '交易详情',
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  ApplePinnedHeaderLayout.contentTop(context),
                  20,
                  ApplePinnedHeaderLayout.contentBottom(context, 52),
                ),
                sliver: SliverList.list(
                  children: [
                    switch (detail) {
                      AsyncData(:final value) => _Detail(record: value),
                      AsyncError(:final error) => GpStateView.error(error),
                      _ => const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(
                            child: CupertinoActivityIndicator(radius: 13),
                          ),
                        ),
                    },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Detail extends ConsumerWidget {
  const _Detail({required this.record});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = ref.watch(merchantAliasConfigProvider);
    final display = aliases.apply(record);
    final amount = formatTransactionAmount(display);
    final date = record.hasValidDate
        ? DateFormat('yyyy-MM-dd HH:mm:ss').format(record.occurredAt.toLocal())
        : '时间未知';
    final extraDetails = record.details.entries.where(
      (entry) =>
          !_canonicalTransactionFields.contains(entry.key.toLowerCase()) &&
          !(record.merchantId != null &&
              _merchantFields.contains(entry.key.toLowerCase())) &&
          !(record.posCode != null &&
              _posFields.contains(entry.key.toLowerCase())),
    );
    return Column(
      children: [
        Icon(
          transactionIcon(context, display),
          size: 72,
          color: context.gpColors.action,
        ),
        const SizedBox(height: 18),
        Text(
          amount,
          style: TextStyle(
            color: context.gpColors.textPrimary,
            fontSize: 48,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          display.displayMerchantName,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.gpColors.textSecondary, fontSize: 17),
        ),
        Text(
          date,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.gpColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 32),
        AppleSection(
          children: [
            AppleListRow(
              label: '原始商户名称',
              value: record.merchantName ?? record.title,
              valueMaxLines: null,
            ),
            if (record.merchantId != null)
              AppleListRow(
                label: '商户号',
                value: record.merchantId,
                valueMaxLines: null,
              ),
            if (record.posCode != null)
              AppleListRow(
                label: 'POS 代码',
                value: record.posCode,
                valueMaxLines: null,
              ),
            AppleListRow(
              label: '交易类型',
              value: record.title,
            ),
            AppleListRow(
              label: '交易流水号',
              value: record.id,
              valueMaxLines: null,
            ),
            if (record.location != null)
              AppleListRow(
                label: '所属单位',
                value: record.location,
              ),
            if (record.balance != null)
              AppleListRow(
                label: '余额',
                value: formatMoneyFen(record.balance!.value),
              ),
            for (final entry in extraDetails)
              AppleListRow(
                label: _detailLabel(context, entry.key),
                value: entry.value,
                valueMaxLines: null,
              ),
          ],
        ),
        if (record.kind == TransactionKind.consumption &&
            record.merchantId != null)
          _MerchantActions(
            key: ValueKey(record.id),
            record: record,
            aliases: aliases,
          ),
      ],
    );
  }

  String _detailLabel(BuildContext context, String key) {
    final label = switch (key.toLowerCase()) {
      'merchantno' || 'merno' || 'merchantid' => '商户号',
      'poscode' => 'POS 代码',
      'terminal' || 'terminalno' => '终端',
      'room' => '场所',
      'location' || 'address' || 'tradestation' => '交易地点',
      'channel' => '交易渠道',
      _ => null,
    };
    return label ?? '附加信息 ($key)';
  }
}

final class _MerchantActions extends ConsumerStatefulWidget {
  const _MerchantActions({
    super.key,
    required this.record,
    required this.aliases,
  });
  final TransactionRecord record;
  final MerchantAliasConfig aliases;

  @override
  ConsumerState<_MerchantActions> createState() => _MerchantActionsState();
}

final class _MerchantActionsState extends ConsumerState<_MerchantActions> {
  bool _invitation = false;

  bool get _unknown {
    final match =
        widget.aliases.resolve(widget.record.merchantId, widget.record.posCode);
    return match == null ||
        (widget.record.posCode != null && match.posCode == null);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_checkInvitation());
  }

  Future<void> _checkInvitation() async {
    final identity =
        merchantIdentityKey(widget.record.merchantId!, widget.record.posCode);
    final preferences = ref.read(merchantContributionPreferencesProvider);
    if (!_unknown ||
        await preferences.hasSeen(identity) ||
        !mounted ||
        !_unknown) {
      return;
    }
    setState(() => _invitation = true);
    await preferences.markSeen(identity);
  }

  void _open({required bool correction}) => unawaited(
        pushCampusCardPage<void>(
          context,
          builder: (_) => MerchantContributionScreen(
            merchantId: widget.record.merchantId!,
            posCode: widget.record.posCode,
            correction: correction,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final known = widget.aliases.containsMerchant(widget.record.merchantId!);
    final knownArea =
        widget.aliases.resolve(widget.record.merchantId, null) != null;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          if (_invitation && _unknown)
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.record.posCode == null || !knownArea
                        ? '此商户尚未收录'
                        : '此收款终端尚未收录',
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _invitation = false),
                  child: const Text('跳过'),
                ),
              ],
            ),
          if (_unknown)
            TextButton.icon(
              onPressed: () => _open(correction: false),
              icon: Icon(GpPlatformIcons.infoCircle(context)),
              label: const Text('补充商户资料'),
            ),
          if (known)
            TextButton.icon(
              onPressed: () => _open(correction: true),
              icon: Icon(GpPlatformIcons.adjustment(context)),
              label: const Text('纠正商户资料'),
            ),
        ],
      ),
    );
  }
}

const _merchantFields = {'merchantno', 'merno', 'merchantid'};
const _posFields = {'poscode', 'terminalno'};

const _canonicalTransactionFields = <String>{
  'id',
  'journo',
  'serialno',
  'tradeno',
  'orderid',
  'txdate',
  'tradetime',
  'paytime',
  'txdatetime',
  'occurtime',
  'txname',
  'tradename',
  'summary',
  'mername',
  'merchantname',
  'merchant',
  'txamt',
  'amount',
  'tradeamt',
  'balance',
  'cardbal',
  'afterbalance',
  'txtype',
  'tradetype',
  'txcode',
  'type',
};
