import 'package:clock/clock.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/payment_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/payment_ports.dart';
import '../api/ecard_api_client.dart';
import '../api/qr_payload_codec.dart';

final class EcardPaymentCodeRepository implements PaymentCodeRepository {
  EcardPaymentCodeRepository(this._client, {Clock? clock, this.onBalance})
      : _clock = clock ?? const Clock();

  static const _gatewayFallbackMessages = {'开放平台返回失败', '开放平台请求超时'};
  static const _successResultPaths = {
    '/pages/common/success/success',
    '/pages/common/paysuccess/paysuccess',
  };
  static final _unusedCodeMessage = RegExp(
    r'未(?:被)?使用|\bunused\b|\bnot (?:yet )?used\b',
    caseSensitive: false,
  );
  static final _paymentFailureMessage = RegExp(
    r'密码.*(?:错误|不正确|有误|失败|锁定|不匹配)|(?:支付|付款|交易)(?:失败|被拒绝|已取消)|'
    r'(?:incorrect|invalid|wrong)\s+password|password.*(?:error|incorrect|invalid|failed|locked)|'
    r'(?:payment|transaction)\s+(?:failed|declined|rejected|cancelled)',
    caseSensitive: false,
  );

  final Future<bool> Function(Map<String, Object?>, MoneyFen)? onBalance;
  final EcardTransport _client;
  final Clock _clock;

  @override
  Future<PaymentCodeFrame> generateOnlineCode() async {
    final response = requireObjectMap(
      await _client.post('/offlineCode/openVirtualcard', {
        'usertype': '8',
        'appcode': '1',
      }),
      context: 'PAYMENT_CODE',
    );
    if (!apiSuccess(response)) {
      final message = apiMessage(response, fallback: '付款码生成失败。');
      if (message.contains('未开通')) {
        throw AppFailure(
          FailureKind.unavailable,
          message,
          code: 'PAYMENT_CODE_NOT_ACTIVATED',
        );
      }
      throw AppFailure(
        FailureKind.server,
        message,
        code: 'PAYMENT_CODE_GENERATION_REJECTED',
        retryable: true,
      );
    }
    final data = requireObjectMap(
      response['data'],
      context: 'PAYMENT_CODE_DATA',
    );
    final payCode = data['code']?.toString() ?? '';
    final qrcode = data['qrcode']?.toString().trim() ?? '';
    final rawQrCode = qrcode.isEmpty ? payCode : qrcode;
    if (payCode.isEmpty || rawQrCode.isEmpty) {
      throw const AppFailure(
        FailureKind.protocol,
        '服务未返回完整付款码。',
        code: 'PAYMENT_CODE_FIELDS_MISSING',
      );
    }
    late String payload;
    try {
      payload = QrPayloadCodec.online(rawQrCode);
    } on FormatException catch (error) {
      throw AppFailure(
        FailureKind.protocol,
        '付款码内容格式无效。',
        code: 'PAYMENT_QR_PAYLOAD_INVALID',
        cause: error,
      );
    }
    await validateEcardResponse(response);
    MoneyFen? balance;
    if (data['cardbal'] != null) {
      try {
        balance = MoneyFen.fromApiYuan(data['cardbal'], field: 'cardbal');
      } on FormatException {
        // An optional malformed balance must not hide a usable payment code.
      }
    }
    final changed = balance != null && onBalance != null
        ? await onBalance!(response, balance) : false;
    await validateEcardResponse(response);
    return PaymentCodeFrame(
      payCode: payCode,
      balance: balance,
      balanceChanged: changed,
      rawQrCode: rawQrCode,
      qrPayload: payload,
      offlineAllowed: data['allowOfflineCode']?.toString() == '1',
      generatedAt: _clock.now().toUtc(),
      requestContext:
          response is EcardResponseMap ? response.requestContext : null,
    );
  }

  @override
  Future<void> activateOnlineCode() async {
    final response = requireObjectMap(
      await _client.post('/virtualcard/openVirtualCardSelf', const {}),
      context: 'PAYMENT_CODE_ACTIVATION',
    );
    if (!apiSuccess(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '付款码开通失败。'),
        code: 'PAYMENT_CODE_ACTIVATION_REJECTED',
      );
    }
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode,
      {PaymentRequestContext? context,}) async {
    final response = requireObjectMap(
      await (_client is EcardApiClient
          ? (_client).pollPaymentResult(payCode, context)
          : _client
              .post('/virtualcard/queryOrderStatus', {'paycode': payCode})),
      context: 'PAYMENT_RESULT',
    );
    final data = response['data'] is Map
        ? requireObjectMap(response['data'], context: 'PAYMENT_RESULT_DATA')
        : response;
    final message = apiMessage(
      data,
      fallback: apiMessage(response, fallback: ''),
    );
    final status = int.tryParse(data['status']?.toString() ?? '');
    if (status == 5) return const PaymentPending();
    if (status == 3) return const PaymentCodeExpired();
    // Some successful polling responses label an unused code as "支付失败".
    // The unused-code qualifier takes precedence over generic failure text.
    if (_unusedCodeMessage.hasMatch(message)) {
      return const PaymentPending();
    }
    if (_gatewayFallbackMessages.contains(message)) {
      return PaymentShouldUseOffline(message);
    }
    if (_paymentFailureMessage.hasMatch(message)) {
      return PaymentNotCompleted(reason: message);
    }
    final resultUrl = (data['url'] ?? response['url'])?.toString().trim() ?? '';
    // `success` belongs to the query, and a result URL may lead to a failure
    // page. Only the known success destination confirms payment completion.
    final resultUri = Uri.tryParse(resultUrl);
    final urlMessage = resultUri?.queryParameters['message'] ?? '';
    if (_paymentFailureMessage.hasMatch(urlMessage)) {
      return PaymentNotCompleted(reason: urlMessage);
    }
    if (apiSuccess(response) &&
        !apiRejected(data) &&
        status == 1 &&
        _successResultPaths.contains(resultUri?.path) &&
        data['txamt'] != null) {
      return PaymentCompleted(
        TransactionResult(
          amount: _paymentResultAmount(data['txamt']),
          confirmedLocallyAt: _clock.now().toUtc(),
          tradeAt: _date(data['paytime']),
          merchantName: _nonEmpty(data['merchantname']),
          orderId: _nonEmpty(data['journo']),
        ),
      );
    }
    if (resultUrl.isNotEmpty) return const PaymentNotCompleted();
    // No result yet is a normal polling response, not a network failure.
    return const PaymentPending();
  }

  MoneyFen _paymentResultAmount(Object? value) {
    try {
      // queryOrderStatus returns yuan; the domain stores integer fen.
      final amount = MoneyFen.fromApiYuan(value, field: 'txamt');
      if (amount.isNegative) throw const FormatException('Negative payment');
      return amount;
    } on FormatException {
      throw const AppFailure(
        FailureKind.protocol,
        '付款结果金额格式无效。',
        code: 'PAYMENT_RESULT_AMOUNT_INVALID',
      );
    }
  }

  String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  DateTime? _date(Object? value) {
    final source = value?.toString().trim();
    if (source == null || source.isEmpty) return null;
    return DateTime.tryParse(source.replaceFirst(' ', 'T'))?.toUtc();
  }
}
