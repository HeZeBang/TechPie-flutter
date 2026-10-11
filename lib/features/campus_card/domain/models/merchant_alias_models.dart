import 'dart:convert';

import '../../core/iso_date_time.dart';
import 'bill_models.dart';

final class MerchantAlias {
  const MerchantAlias({
    required this.merchantId,
    required this.alias,
    required this.verifiedAt,
    required this.evidence,
    required this.enabled,
    this.posCode,
    this.category,
  });

  final String merchantId;
  final String? posCode;
  final String alias;
  final String verifiedAt;
  final String evidence;
  final bool enabled;
  final String? category;

  String get key => merchantIdentityKey(merchantId, posCode);

  Map<String, Object?> toJson() => {
        'merchantId': merchantId,
        if (posCode != null) 'posCode': posCode,
        'alias': alias,
        'verifiedAt': verifiedAt,
        'evidence': evidence,
        'enabled': enabled,
        if (category != null) 'category': category,
      };
}

String merchantIdentityKey(String merchantId, String? posCode) =>
    jsonEncode([merchantId, posCode]);

final class MerchantAliasConfig {
  const MerchantAliasConfig.empty()
      : version = 0,
        updatedAt = null,
        entries = const [],
        _index = const {},
        _blocked = const {};

  MerchantAliasConfig._(
    this.version,
    this.updatedAt,
    List<MerchantAlias> records,
  )   : entries = List.unmodifiable(records),
        _index = {},
        _blocked = {} {
    for (final record in records) {
      if (_index.containsKey(record.key) || !record.enabled) {
        _blocked.add(record.key);
      }
      _index[record.key] = record;
    }
  }

  final int version;
  final DateTime? updatedAt;
  final List<MerchantAlias> entries;
  final Map<String, MerchantAlias> _index;
  final Set<String> _blocked;

  factory MerchantAliasConfig.decode(String source) {
    if (utf8.encode(source).length > 1024 * 1024) {
      throw const FormatException('Merchant configuration is too large');
    }
    final data = jsonDecode(source);
    if (data is! Map ||
        data['schemaVersion'] is! int ||
        data['schemaVersion'] != 1 ||
        data['version'] is! int ||
        (data['version'] as int) < 1 ||
        data['entries'] is! List ||
        (data['entries'] as List).length > 5000) {
      throw const FormatException('Invalid merchant configuration');
    }
    final updatedAt = parseIsoDateTime(_string(data['updatedAt'], 40));
    if (updatedAt == null) {
      throw const FormatException('Invalid configuration date');
    }
    final records = <MerchantAlias>[];
    for (final value in data['entries'] as List) {
      if (value is! Map || value['enabled'] is! bool) {
        throw const FormatException('Invalid merchant entry');
      }
      final verifiedAt = _string(value['verifiedAt'], 10);
      final date = DateTime.tryParse(verifiedAt);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(verifiedAt) ||
          date == null ||
          date.toIso8601String().substring(0, 10) != verifiedAt) {
        throw const FormatException('Invalid verification date');
      }
      final category = value['category'];
      if (category != null && category != 'dining' && category != 'other') {
        throw const FormatException('Invalid merchant category');
      }
      records.add(
        MerchantAlias(
          merchantId: _string(value['merchantId'], 80),
          posCode:
              value['posCode'] == null ? null : _string(value['posCode'], 80),
          alias: _string(value['alias'], 100),
          verifiedAt: verifiedAt,
          evidence: _string(value['evidence'], 500),
          enabled: value['enabled'] as bool,
          category: category as String?,
        ),
      );
    }
    return MerchantAliasConfig._(data['version'] as int, updatedAt, records);
  }

  static String _string(Object? value, int maxLength) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > maxLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
        value.trim() == '-' ||
        value.trim() == '--') {
      throw const FormatException('Invalid configuration text');
    }
    return value.trim();
  }

  MerchantAlias? resolve(String? merchantId, String? posCode) {
    if (merchantId == null) return null;
    final terminal = merchantIdentityKey(merchantId, posCode);
    final merchant = merchantIdentityKey(merchantId, null);
    if (_blocked.contains(terminal) || _blocked.contains(merchant)) return null;
    return _index[terminal] ?? _index[merchant];
  }

  TransactionRecord apply(TransactionRecord record) {
    final match = resolve(record.merchantId, record.posCode);
    return record.withMerchantAlias(
      match?.alias,
      dining: match?.category == 'dining',
    );
  }

  bool containsMerchant(String merchantId) =>
      entries.any((entry) => entry.merchantId == merchantId);

  String encode() => jsonEncode({
        'schemaVersion': 1,
        'version': version,
        'updatedAt': updatedAt!.toUtc().toIso8601String(),
        'entries': entries.map((entry) => entry.toJson()).toList(),
      });
}
