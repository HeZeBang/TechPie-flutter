import 'dart:convert';

/// Only these explicitly selected fields may leave the transaction detail.
final class MerchantContribution {
  const MerchantContribution({
    required this.merchantId,
    required this.cafeteria,
    this.posCode,
    this.floor = '',
    this.stall = '',
    this.correction = false,
  });

  final String merchantId;
  final String? posCode;
  final String cafeteria;
  final String floor;
  final String stall;
  final bool correction;

  Map<String, String> get fields => {
        'merchantId': merchantId,
        if (posCode != null) 'posCode': posCode!,
        'cafeteria': cafeteria.trim(),
        if (floor.trim().isNotEmpty) 'floor': floor.trim(),
        if (stall.trim().isNotEmpty) 'stall': stall.trim(),
      };

  String get issueBody => '商户资料${correction ? '纠正' : '补充'}，待维护者核实。\n\n'
      '```json\n${const JsonEncoder.withIndent('  ').convert(fields)}\n```\n\n'
      '可选：附加招牌或店面照片。请确认照片没有人脸、付款码或账户信息。\n'
      '此线索尚未核实，不直接修改公共商户名称。';

  Uri get issueUri =>
      Uri.https('github.com', '/HeZeBang/TechPie-flutter/issues/new', {
        'title': '[商户资料] ${correction ? '纠正' : '补充'}（待核实）',
        'body': issueBody,
      });
}
