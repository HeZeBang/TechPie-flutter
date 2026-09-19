import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/bill_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/bill_ports.dart';
import '../api/ecard_api_client.dart';

typedef TransactionSubjectReader = Future<String?> Function();

final class EcardTransactionHistoryRepository
    implements TransactionHistoryPort, DateRangeTransactionHistoryPort {
  EcardTransactionHistoryRepository(
    this._client, {
    required TransactionSubjectReader subjectReader,
  }) : _subjectReader = subjectReader;

  final EcardTransport _client;
  final TransactionSubjectReader _subjectReader;
  final Map<String, Map<String, TransactionRecord>> _detailCache = {};

  @override
  Future<TransactionPage> timeline({
    required String month,
    String? cursor,
    int pageSize = 20,
  }) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '账单月份格式无效。',
        code: 'TRANSACTION_MONTH_INVALID',
      );
    }
    final year = int.parse(month.substring(0, 4));
    final monthNumber = int.parse(month.substring(5, 7));
    final lastDay = DateTime.utc(year, monthNumber + 1, 0).day;
    return _loadPage(
      begin: DateTime(year, monthNumber),
      end: DateTime(year, monthNumber, lastDay),
      cursor: cursor,
      pageSize: pageSize,
    );
  }

  @override
  Future<TransactionRecord> detail(String id) async {
    final subjectId = await _requireSubject();
    final record = _detailCache[subjectId]?[id];
    if (record != null) return record;
    throw const AppFailure(
      FailureKind.invalidInput,
      '当前会话中没有这笔交易详情，请从账单列表重新进入。',
      code: 'TRANSACTION_DETAIL_NOT_CACHED',
    );
  }

  @override
  Future<TransactionPage> timelineRange({
    DateTime? begin,
    DateTime? end,
    String? cursor,
    int pageSize = 20,
  }) async {
    if (begin != null && end != null && end.isBefore(begin)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '账单日期范围无效。',
        code: 'TRANSACTION_RANGE_INVALID',
      );
    }
    return _loadPage(
      begin: begin,
      end: end,
      cursor: cursor,
      pageSize: pageSize,
    );
  }

  Future<TransactionPage> _loadPage({
    DateTime? begin,
    DateTime? end,
    String? cursor,
    required int pageSize,
  }) async {
    final subjectId = await _requireSubject();
    final page = int.tryParse(cursor ?? '0') ?? 0;
    final size = pageSize.clamp(1, 50);
    final now = DateTime.now();
    final beginDate = begin ?? DateTime(now.year, now.month - 6, now.day + 1);
    final endDate = end ?? now;
    final beginText = _formatDate(beginDate);
    // The live endpoint treats endDate/endtime as an exclusive day boundary.
    // Send the following day so the user-selected end date is fully included.
    final endText = _formatDate(endDate.add(const Duration(days: 1)));
    final raw = await _client.get('/selftrade/queryCardSelfTradeList', {
      'beginDate': beginText,
      'endDate': endText,
      'starttime': beginText,
      'endtime': endText,
      'tradeType': 0,
      'pageSize': size,
      'pageNumber': page,
    });
    if (await _requireSubject() != subjectId) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '请求期间登录账户发生变化，已丢弃交易数据。',
        code: 'TRANSACTION_SUBJECT_CHANGED',
      );
    }
    await validateEcardResponse(raw);
    if (raw is String && raw.contains('CORE10008')) {
      return const TransactionPage(items: [], hasMore: false);
    }
    final response = requireObjectMap(raw, context: 'TRANSACTION_HISTORY');
    if (apiRejected(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '使用明细加载失败。'),
        code: 'TRANSACTION_HISTORY_REJECTED',
        retryable: true,
      );
    }
    final result = response['resultData'] is Map
        ? requireObjectMap(response['resultData'], context: 'TRANSACTION_PAGE')
        : response['data'] is Map
            ? requireObjectMap(
                response['data'],
                context: 'TRANSACTION_PAGE_DATA',
              )
            : const <String, Object?>{};
    final rows = result['rows'] is List
        ? List<Object?>.from(result['rows'] as List)
        : result['data'] is List
            ? List<Object?>.from(result['data'] as List)
            : const <Object?>[];
    final records = <TransactionRecord>[];
    for (final rawRow in rows) {
      if (rawRow is! Map) continue;
      final row = rawRow.map((key, value) => MapEntry(key.toString(), value));
      final record = _record(row);
      records.add(record);
      (_detailCache[subjectId] ??= {})[record.id] = record;
    }
    records.sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final currentPage = _integer(
      result['currentPage'] ?? result['currentpage'] ?? result['pageNumber'],
      page,
    );
    final totalPages = _nullableInteger(
      result['totalpage'] ?? result['totalPage'],
    );
    final hasMore = totalPages == null
        ? records.length >= size
        : currentPage + 1 < totalPages;
    return TransactionPage(
      items: List.unmodifiable(records),
      hasMore: hasMore,
      nextCursor: hasMore ? (currentPage + 1).toString() : null,
    );
  }

  Future<String> _requireSubject() async {
    final subjectId = await _subjectReader();
    if (subjectId == null || subjectId.isEmpty) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '无法确认交易数据所属账户。',
        code: 'TRANSACTION_SUBJECT_MISSING',
      );
    }
    return subjectId;
  }

  void clearCachedDetails() => _detailCache.clear();

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  TransactionRecord _record(Map<String, Object?> row) {
    final canonical = jsonEncode(
      Map.fromEntries(
        row.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    final id =
        _text(row, const ['journo', 'id', 'serialno', 'tradeno', 'orderid']) ??
            sha256.convert(utf8.encode(canonical)).toString();
    final title = _text(row, const [
          'txname',
          'tradename',
          'merchantname',
          'mername',
          'summary',
        ]) ??
        '校园卡交易';
    final amount =
        _money(row, const ['txamt', 'amount', 'tradeamt']) ?? MoneyFen.zero;
    final typeText =
        _text(row, const ['txtype', 'tradetype', 'txcode', 'type']) ?? '';
    final rawDateText = _text(row, const [
      'txdate',
      'tradetime',
      'paytime',
      'txdatetime',
      'occurtime',
    ]);
    final kind = _kind(
      typeText,
      '$title ${row['mername'] ?? ''} ${row['summary'] ?? ''}',
      amount,
    );
    final merchantName = _text(row, const [
      'mername',
      'merchantname',
      'merchant',
    ]);
    return TransactionRecord(
      id: id,
      occurredAt: _dateText(rawDateText) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      title: title,
      amount: amount,
      kind: kind,
      merchantName: merchantName ?? title,
      location: _text(row, const ['location', 'address', 'tradestation']),
      balance: _money(row, const ['balance', 'cardbal', 'afterbalance']),
      rawDateText: rawDateText,
      typeCode: typeText,
      details: Map.unmodifiable({
        for (final entry in row.entries)
          if (entry.value != null && entry.value.toString().trim().isNotEmpty)
            entry.key: entry.value.toString(),
      }),
    );
  }

  TransactionKind _kind(String type, String source, MoneyFen amount) {
    switch (type) {
      case '1':
        return TransactionKind.consumption;
      case '2':
        return TransactionKind.recharge;
      case '3':
        return TransactionKind.subsidy;
      case '4':
        return TransactionKind.transfer;
    }
    if (source.contains('补贴') || source.contains('补助')) {
      return TransactionKind.subsidy;
    }
    if (source.contains('充值') ||
        source.contains('余额结转') ||
        source.contains('入账')) {
      return TransactionKind.recharge;
    }
    if (source.contains('转账')) return TransactionKind.transfer;
    if (source.contains('退款') || source.contains('冲正')) {
      return TransactionKind.refund;
    }
    if (source.contains('修改') ||
        source.contains('设置') ||
        source.contains('开通') ||
        source.contains('挂失') ||
        source.contains('解挂') ||
        source.contains('冻结') ||
        source.contains('销户') ||
        source.contains('延长有效期') ||
        source.contains('调整')) {
      return TransactionKind.adjustment;
    }
    if (source.contains('消费') || source.contains('支付')) {
      return TransactionKind.consumption;
    }
    if (amount.value > 0) return TransactionKind.recharge;
    if (amount.value == 0) return TransactionKind.adjustment;
    return TransactionKind.consumption;
  }

  String? _text(Map<String, Object?> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  MoneyFen? _money(Map<String, Object?> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null || value.toString().trim().isEmpty) continue;
      final source = value.toString().trim();
      return source.contains('.')
          ? MoneyFen.fromApiYuan(source, field: key)
          : MoneyFen.fromApiFen(source, field: key);
    }
    return null;
  }

  DateTime? _dateText(String? value) {
    if (value == null) return null;
    final epoch = int.tryParse(value);
    if (epoch != null) {
      final milliseconds = epoch < 100000000000 ? epoch * 1000 : epoch;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return DateTime.tryParse(value.replaceFirst(' ', 'T'))?.toUtc();
  }

  int _integer(Object? value, int fallback) =>
      int.tryParse(value?.toString() ?? '') ?? fallback;

  int? _nullableInteger(Object? value) => int.tryParse(value?.toString() ?? '');
}
