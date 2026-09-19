import '../models/bill_models.dart';

abstract interface class BillSummaryRepository {
  Future<List<String>> availableMonths();
  Future<BillSummary> summary(String month);
}

abstract interface class TransactionHistoryPort {
  Future<TransactionPage> timeline({
    required String month,
    String? cursor,
    int pageSize = 20,
  });

  Future<TransactionRecord> detail(String id);
}

abstract interface class DateRangeTransactionHistoryPort {
  Future<TransactionPage> timelineRange({
    DateTime? begin,
    DateTime? end,
    String? cursor,
    int pageSize = 20,
  });
}
