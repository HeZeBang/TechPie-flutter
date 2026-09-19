import '../../core/errors/app_failure.dart';
import '../../domain/models/bill_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/bill_ports.dart';
import '../api/ecard_api_client.dart';

final class EcardBillSummaryRepository implements BillSummaryRepository {
  EcardBillSummaryRepository(this._client);

  final EcardTransport _client;

  @override
  Future<List<String>> availableMonths() async {
    final response = requireObjectMap(
      await _client.post('/bill/openMyBill', const {}),
      context: 'BILL_MONTHS',
    );
    _requireSuccess(response, '账单月份加载失败。', 'BILL_MONTHS_REJECTED');
    final data = _unwrapMap(response, 'data', 'BILL_MONTHS_DATA');
    final months = requireList(
      data['billDateList'],
      context: 'BILL_MONTH_LIST',
    ).map((value) => value.toString()).where(_isMonth).toList(growable: false);
    return List.unmodifiable(months);
  }

  @override
  Future<BillSummary> summary(String month) async {
    if (!_isMonth(month)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '账单月份格式无效。',
        code: 'BILL_MONTH_INVALID',
      );
    }
    final monthsFuture = availableMonths();
    final monthlyFuture = _client.post('/bill/queryUserMonthlybill', {
      'startdate': month,
      'enddate': month,
    });
    final rechargeFuture = _client.post('/bill/queryRechargeGroupByTxcode', {
      'startdate': month,
      'enddate': month,
    });

    final results = await Future.wait<Object?>([monthlyFuture, rechargeFuture]);
    final available = await monthsFuture;
    final monthly = _resultData(results[0], 'MONTHLY_BILL');
    final recharge = _resultData(results[1], 'RECHARGE_BILL');

    return BillSummary(
      month: month,
      availableMonths: available,
      spendingTotal: MoneyFen.fromApiYuan(
        monthly['sumamt'] ?? 0,
        field: 'sumamt',
      ),
      spendingCategories: _list(monthly['billList'], 'MONTHLY_BILL_LIST')
          .map(
            (entry) => BillCategory(
              name: entry['name']?.toString() ?? '其他',
              amount: MoneyFen.fromApiYuan(entry['value'] ?? 0, field: 'value'),
            ),
          )
          .toList(growable: false),
      halfYearTrend: const [],
      rechargeTotal: MoneyFen.fromApiFen(
        recharge['sumamt'] ?? 0,
        field: 'sumamt',
      ),
      rechargeCategories: _list(recharge['billList'], 'RECHARGE_BILL_LIST')
          .map(
            (entry) => BillCategory(
              name: entry['txname']?.toString() ?? '其他',
              amount: MoneyFen.fromApiFen(entry['txamt'] ?? 0, field: 'txamt'),
            ),
          )
          .toList(growable: false),
      fun: const FunBillSummary(
        breakfastCount: 0,
        breakfastAmount: MoneyFen.zero,
        lunchCount: 0,
        lunchAmount: MoneyFen.zero,
        dinnerCount: 0,
        dinnerAmount: MoneyFen.zero,
        foodTotalAmount: MoneyFen.zero,
        sportAmount: MoneyFen.zero,
        sportDays: 0,
        sportTimes: 0,
        networkAmount: MoneyFen.zero,
        networkTimes: 0,
      ),
    );
  }

  Map<String, Object?> _resultData(Object? raw, String context) {
    if (raw is String && raw.contains('CORE10008')) {
      return const {'sumamt': 0, 'billList': <Object>[]};
    }
    final response = requireObjectMap(raw, context: context);
    if (response['resultData'] is Map) {
      return requireObjectMap(
        response['resultData'],
        context: '${context}_DATA',
      );
    }
    if (apiMessage(response, fallback: '').contains('CORE10008')) {
      return const {'sumamt': 0, 'billList': <Object>[]};
    }
    _requireSuccess(response, '账单信息加载失败。', '${context}_REJECTED');
    throw AppFailure(
      FailureKind.protocol,
      '账单接口成功但没有返回 resultData。',
      code: '${context}_RESULT_DATA_MISSING',
    );
  }

  Map<String, Object?> _unwrapMap(
    Map<String, Object?> source,
    String key,
    String context,
  ) =>
      requireObjectMap(source[key], context: context);

  List<Map<String, Object?>> _list(Object? raw, String context) =>
      requireList(raw ?? const [], context: context)
          .map((entry) => requireObjectMap(entry, context: '${context}_ITEM'))
          .toList(growable: false);

  void _requireSuccess(
    Map<String, Object?> response,
    String fallback,
    String code,
  ) {
    if (apiSuccess(response)) return;
    throw AppFailure(
      FailureKind.server,
      apiMessage(response, fallback: fallback),
      code: code,
      retryable: true,
    );
  }

  static bool _isMonth(String value) =>
      RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value);
}
