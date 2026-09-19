import '../../domain/models/bill_models.dart';
import '../../domain/money_fen.dart';

List<TransactionRecord> debugTransactionRecords(DateTime now) {
  final consumeDate = _text(now.subtract(const Duration(minutes: 8)));
  final rechargeDate = _text(now.subtract(const Duration(hours: 3)));
  final subsidyDate = _text(now.subtract(const Duration(days: 1, hours: 2)));
  final transferDate = _text(now.subtract(const Duration(days: 2, hours: 1)));
  return [
    TransactionRecord(
      id: 'DEBUG-JOURNO-CONSUME-001',
      occurredAt: now.subtract(const Duration(minutes: 8)).toUtc(),
      rawDateText: consumeDate,
      title: '消费',
      merchantName: '校园咖啡厅',
      amount: const MoneyFen(1280),
      kind: TransactionKind.consumption,
      typeCode: '1',
      balance: const MoneyFen(7927),
      details: {
        'journo': 'DEBUG-JOURNO-CONSUME-001',
        'txdate': consumeDate,
        'txname': '消费',
        'mername': '校园咖啡厅',
        'txamt': '12.80',
        'txtype': '1',
        'terminal': 'DEBUG-POS-01',
      },
    ),
    TransactionRecord(
      id: 'DEBUG-JOURNO-RECHARGE-002',
      occurredAt: now.subtract(const Duration(hours: 3)).toUtc(),
      rawDateText: rechargeDate,
      title: '充值',
      merchantName: '校园卡线上充值',
      amount: const MoneyFen(10000),
      kind: TransactionKind.recharge,
      typeCode: '2',
      balance: const MoneyFen(9207),
      details: {
        'journo': 'DEBUG-JOURNO-RECHARGE-002',
        'txdate': rechargeDate,
        'txname': '充值',
        'mername': '校园卡线上充值',
        'txamt': '100.00',
        'txtype': '2',
        'channel': 'DEBUG',
      },
    ),
    TransactionRecord(
      id: 'DEBUG-JOURNO-SUBSIDY-003',
      occurredAt: now.subtract(const Duration(days: 1, hours: 2)).toUtc(),
      rawDateText: subsidyDate,
      title: '补贴',
      merchantName: '学生补贴',
      amount: const MoneyFen(5000),
      kind: TransactionKind.subsidy,
      typeCode: '3',
      details: {
        'journo': 'DEBUG-JOURNO-SUBSIDY-003',
        'txdate': subsidyDate,
        'txname': '补贴',
        'mername': '学生补贴',
        'txamt': '50.00',
        'txtype': '3',
      },
    ),
    TransactionRecord(
      id: 'DEBUG-JOURNO-TRANSFER-004',
      occurredAt: now.subtract(const Duration(days: 2, hours: 1)).toUtc(),
      rawDateText: transferDate,
      title: '转账',
      merchantName: '校园卡转账',
      amount: const MoneyFen(-2000),
      kind: TransactionKind.transfer,
      typeCode: '4',
      balance: const MoneyFen(5927),
      details: {
        'journo': 'DEBUG-JOURNO-TRANSFER-004',
        'txdate': transferDate,
        'txname': '转账',
        'mername': '校园卡转账',
        'txamt': '-20.00',
        'txtype': '4',
        'merchantno': 'DEBUG-MERCHANT',
      },
    ),
  ];
}

String _text(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
