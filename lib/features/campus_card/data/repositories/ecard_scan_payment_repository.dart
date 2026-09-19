import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import '../../domain/models/scan_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/payment_ports.dart';
import '../api/ecard_api_client.dart';

final class EcardScanPaymentRepository implements ScanPaymentRepository {
  EcardScanPaymentRepository(this._client);

  final EcardTransport _client;

  static const _successResultPaths = {
    '/pages/common/success/success',
    '/pages/common/paysuccess/paysuccess',
  };

  @override
  Future<ScanPaymentResult> submit({
    required String qrCode,
    required DateTime payTime,
    String? password,
    PaymentRequestContext? context,
  }) async {
    // Preserve the server-returned challenge, including percent escapes, so
    // password retries match the code held by the payment context.
    final payload = <String, Object?>{
      'qrcode': qrCode,
      'paytime': payTime.toUtc().millisecondsSinceEpoch,
    };
    if (password != null) payload['password'] = password;
    final response = requireObjectMap(
      await (_client is EcardApiClient
          ? (_client).submitScanPayment(payload, context)
          : _client.post('/scan/scanningResult', payload)),
      context: 'SCAN_PAYMENT',
    );
    final status = response['issuccess']?.toString();
    final data = response['data'] is Map
        ? requireObjectMap(response['data'], context: 'SCAN_PAYMENT_DATA')
        : const <String, Object?>{};
    final resultUrl = response['url']?.toString().trim() ?? '';
    final resultPath = Uri.tryParse(resultUrl)?.path;
    if (status == '2004' ||
        (apiSuccess(response) &&
            !apiRejected(data) &&
            resultPath == '/pages/common/inputPass/inputPass')) {
      final serverQrCode =
          (data['qrcode'] ?? response['qrcode'])?.toString() ?? '';
      if (serverQrCode.trim().isEmpty) {
        return const ScanFailed(
          message: '服务未返回密码重试所需的付款码。',
          code: 'SCAN_PASSWORD_QR_MISSING',
        );
      }
      return ScanPasswordRequired(
        serverQrCode: serverQrCode,
        context: response is EcardResponseMap ? response.requestContext : null,
      );
    }
    if (apiSuccess(response) &&
        !apiRejected(data) &&
        ((status == '1' && resultUrl.isEmpty) ||
            _successResultPaths.contains(resultPath))) {
      final resultData = response['resultData'] is Map
          ? requireObjectMap(
              response['resultData'],
              context: 'SCAN_RESULT_DATA',
            )
          : const <String, Object?>{};
      final type = (resultData['type'] ?? data['type'] ?? response['type'])?.toString() ?? '';
      return ScanSucceeded(
        kind: switch (type) {
          '' => ScanSuccessKind.payment,
          'scj' => ScanSuccessKind.attendance,
          'opendevice' => ScanSuccessKind.openDevice,
          'bindTray' => ScanSuccessKind.bindTray,
          _ => ScanSuccessKind.unknown,
        },
        // The captured nested receipt uses yuan; legacy top-level fields use fen.
        amount: data.containsKey('txamt')
            ? _optionalYuan(data['txamt'], 'txamt')
            : _optionalFen(response['txamt'], 'txamt'),
        fee: _optionalFen(response['managefee'], 'managefee'),
        balance: _optionalFen(response['balance'], 'balance'),
        message: _successMessage(response['message']),
        paidAt: _paymentTime(data['paytime'] ?? response['paytime']),
        authorizationCode: _text(data['authcode'] ?? response['authcode']),
        transactionId: _text(data['journo'] ?? response['journo']),
        terminalCode: _text(data['poscode'] ?? response['poscode']),
        transactionCode: _text(data['txcode'] ?? response['txcode']),
      );
    }
    return ScanFailed(
      message: apiMessage(response, fallback: '扫码消费失败。'),
      code: status,
    );
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _successMessage(Object? value) {
    final text = _text(value);
    // A protocol status identifier is not a receipt description.
    return text != null && RegExp(r'^CORE\d+$').hasMatch(text) ? null : text;
  }

  MoneyFen? _optionalYuan(Object? value, String field) {
    if (value == null || value.toString().trim().isEmpty) return null;
    try {
      final amount = MoneyFen.fromApiYuan(value, field: field);
      return amount.isNegative ? null : amount;
    } on FormatException {
      // A missing/invalid optional receipt field cannot undo confirmed payment.
      return null;
    }
  }

  DateTime? _paymentTime(Object? value) {
    final text = _text(value);
    if (text == null || !RegExp(r'^\d{14}$').hasMatch(text)) return null;
    final parts = [int.parse(text.substring(0, 4)),
      for (var i = 4; i < 14; i += 2) int.parse(text.substring(i, i + 2)),];
    final local = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    if (local.year != parts[0] || local.month != parts[1] || local.day != parts[2] ||
        local.hour != parts[3] || local.minute != parts[4] || local.second != parts[5]) {
      return null;
    }
    // eCard's compact timestamp is campus wall time (UTC+08:00).
    return local.subtract(const Duration(hours: 8));
  }

  MoneyFen? _optionalFen(Object? value, String field) =>
      value == null || value.toString().isEmpty
          ? null
          : MoneyFen.fromApiFen(value, field: field);
}
