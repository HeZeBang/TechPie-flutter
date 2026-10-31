import '../money_fen.dart';

final class BillCategory {
  const BillCategory({required this.name, required this.amount});
  final String name;
  final MoneyFen amount;
}

final class MonthlyTrendPoint {
  const MonthlyTrendPoint({required this.month, required this.amount});
  final String month;
  final MoneyFen amount;
}

final class FunBillSummary {
  const FunBillSummary({
    required this.breakfastCount,
    required this.breakfastAmount,
    required this.lunchCount,
    required this.lunchAmount,
    required this.dinnerCount,
    required this.dinnerAmount,
    required this.foodTotalAmount,
    required this.sportAmount,
    required this.sportDays,
    required this.sportTimes,
    required this.networkAmount,
    required this.networkTimes,
  });

  final int breakfastCount;
  final MoneyFen breakfastAmount;
  final int lunchCount;
  final MoneyFen lunchAmount;
  final int dinnerCount;
  final MoneyFen dinnerAmount;
  final MoneyFen foodTotalAmount;
  final MoneyFen sportAmount;
  final int sportDays;
  final int sportTimes;
  final MoneyFen networkAmount;
  final int networkTimes;
}

final class BillSummary {
  const BillSummary({
    required this.month,
    required this.availableMonths,
    required this.spendingTotal,
    required this.spendingCategories,
    required this.halfYearTrend,
    required this.rechargeTotal,
    required this.rechargeCategories,
    required this.fun,
  });

  final String month;
  final List<String> availableMonths;
  final MoneyFen spendingTotal;
  final List<BillCategory> spendingCategories;
  final List<MonthlyTrendPoint> halfYearTrend;
  final MoneyFen rechargeTotal;
  final List<BillCategory> rechargeCategories;
  final FunBillSummary fun;
}

enum TransactionKind {
  consumption,
  recharge,
  creditReplenishment,
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
    this.merchantId,
    this.posCode,
    this.merchantAlias,
    this.hasValidDate = true,
    this.isDining = false,
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
  final String? merchantId;
  final String? posCode;
  final String? merchantAlias;
  final bool hasValidDate;
  final bool isDining;
  final Map<String, String> details;

  bool get isHiddenFromHistory =>
      kind == TransactionKind.creditReplenishment ||
      (merchantId == '900000001' && (posCode?.trim().isEmpty ?? true));

  String get displayMerchantName =>
      merchantAlias ??
      (merchantName?.trim().isNotEmpty == true ? merchantName! : title);

  TransactionRecord withMerchantAlias(String? alias, {bool dining = false}) =>
      TransactionRecord(
        id: id,
        occurredAt: occurredAt,
        title: title,
        amount: amount,
        kind: kind,
        merchantName: merchantName,
        location: location,
        balance: balance,
        rawDateText: rawDateText,
        typeCode: typeCode,
        merchantId: merchantId,
        posCode: posCode,
        merchantAlias: alias,
        hasValidDate: hasValidDate,
        isDining: isDining || dining,
        details: details,
      );
}

bool isTransactionVisible(
  TransactionRecord record, {
  bool showAllRecords = false,
}) =>
    showAllRecords || !record.isHiddenFromHistory;

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
