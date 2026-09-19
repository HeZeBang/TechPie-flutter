import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_providers.dart';
import '../../domain/models/bill_models.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../widgets/apple_wallet_components.dart';
import '../widgets/gp_state.dart';

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
                padding: const EdgeInsets.fromLTRB(
                  20,
                  ApplePinnedHeaderLayout.contentTop,
                  20,
                  52,
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

final class _Detail extends StatelessWidget {
  const _Detail({required this.record});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context) {
    final amount = formatTransactionAmount(record);
    final date = DateFormat('yyyy-MM-dd HH:mm:ss').format(
      record.occurredAt.toLocal(),
    );
    final extraDetails = record.details.entries.where(
      (entry) => !_canonicalTransactionFields.contains(entry.key.toLowerCase()),
    );
    return Column(
      children: [
        Icon(
          transactionIcon(context, record),
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
            letterSpacing: -1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          record.merchantName?.trim().isNotEmpty == true
              ? record.merchantName!
              : record.title,
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
      ],
    );
  }

  String _detailLabel(BuildContext context, String key) {
    final label = switch (key.toLowerCase()) {
      'merchantno' || 'merno' => '商户号',
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
