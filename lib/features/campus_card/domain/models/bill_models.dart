import '../money_fen.dart';

enum TransactionKind {
  consumption,
  recharge,
  subsidy,
  transfer,
  refund,
  adjustment,
}

final class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.occurredAt,
    required this.title,
    required this.amount,
    required this.kind,
    this.merchantName,
    this.location,
    this.balance,
    this.rawDateText,
    this.typeCode,
    this.details = const {},
  });

  final String id;
  final DateTime occurredAt;
  final String title;
  final MoneyFen amount;
  final TransactionKind kind;
  final String? merchantName;
  final String? location;
  final MoneyFen? balance;
  final String? rawDateText;
  final String? typeCode;
  final Map<String, String> details;
}

final class TransactionPage {
  const TransactionPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<TransactionRecord> items;
  final bool hasMore;
  final String? nextCursor;
}
