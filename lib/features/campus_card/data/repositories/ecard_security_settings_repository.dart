import '../../core/errors/app_failure.dart';
import '../../domain/models/security_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/security_ports.dart';
import '../api/ecard_api_client.dart';

final class EcardSecuritySettingsRepository implements SecuritySettingsPort {
  EcardSecuritySettingsRepository(this._client);

  final EcardTransport _client;

  @override
  Future<SpendingPasswordInitialization> initializePasswordChange() async {
    final response = requireObjectMap(
      await _client.post('/virtualcard/openQrcodePwdModify', const {}),
      context: 'PASSWORD_INITIALIZATION',
    );
    if (apiRejected(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '密码服务初始化失败。'),
        code: 'PASSWORD_INITIALIZATION_REJECTED',
      );
    }
    final data = response['data'] is Map
        ? requireObjectMap(
            response['data'],
            context: 'PASSWORD_INITIALIZATION_DATA',
          )
        : response;
    final accountKey = data['idserial']?.toString() ?? '';
    if (accountKey.isEmpty) {
      throw const AppFailure(
        FailureKind.protocol,
        '密码服务未返回完整账户字段。',
        code: 'PASSWORD_ACCOUNT_KEY_MISSING',
      );
    }
    return SpendingPasswordInitialization(
      accountKey: accountKey,
      haveCard: data['haveCard']?.toString() == '1',
      displayName: data['username']?.toString(),
    );
  }

  @override
  Future<SpendingLimits> readLimits() async {
    final response = requireObjectMap(
      await _client.post('/virtualcard/openQrcodeQuotaModify', const {}),
      context: 'QRCODE_LIMITS',
    );
    if (apiRejected(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '限额读取失败。'),
        code: 'LIMITS_READ_REJECTED',
      );
    }
    final data = response['data'] is Map
        ? requireObjectMap(response['data'], context: 'QRCODE_LIMITS_DATA')
        : response;
    final idSerial = data['idserial']?.toString() ?? '';
    final cardId = data['cardid']?.toString() ?? '';
    final qrCodeId = data['qrcodeid']?.toString() ?? '';
    if (idSerial.isEmpty || cardId.isEmpty || qrCodeId.isEmpty) {
      throw const AppFailure(
        FailureKind.protocol,
        '限额服务未返回完整账户字段。',
        code: 'LIMITS_IDENTIFIERS_MISSING',
      );
    }
    return SpendingLimits(
      idSerial: idSerial,
      cardId: cardId,
      qrCodeId: qrCodeId,
      haveCard: data['haveCard']?.toString() == '1',
      haveQrCode: data['haveQrcode']?.toString() == '1',
      cardPerTransaction: MoneyFen.fromApiYuan(
        data['cardmaxconsamt'] ?? 0,
        field: 'cardmaxconsamt',
      ),
      cardPerDay: MoneyFen.fromApiYuan(
        data['cardmaxconstolamt'] ?? 0,
        field: 'cardmaxconstolamt',
      ),
      qrPerTransaction: MoneyFen.fromApiYuan(
        data['qrcodemaxconsamt'] ?? 0,
        field: 'qrcodemaxconsamt',
      ),
      qrPerDay: MoneyFen.fromApiYuan(
        data['qrcodemaxconstolamt'] ?? 0,
        field: 'qrcodemaxconstolamt',
      ),
      displayName: data['username']?.toString(),
    );
  }

  @override
  Future<void> updateCardLimits(SpendingLimits limits) async {
    _validateLimits(limits.cardPerTransaction, limits.cardPerDay);
    final response = requireObjectMap(
      await _client.get('/card/cardQuotaModify', {
        'idserial': limits.idSerial,
        'maxconsamt': limits.cardPerTransaction.value.toString(),
        'maxconstolamt': limits.cardPerDay.value.toString(),
        'cardid': limits.cardId,
      }),
      context: 'CARD_LIMITS_UPDATE',
    );
    _requireSuccess(response, '卡消费限额修改失败。', 'CARD_LIMITS_UPDATE_REJECTED');
  }

  @override
  Future<void> updateQrLimits(
    SpendingLimits limits, {
    required String transactionPassword,
  }) async {
    _validatePassword(transactionPassword);
    _validateLimits(limits.qrPerTransaction, limits.qrPerDay);
    final response = requireObjectMap(
      await _client.get('/virtualcard/qrcodeQuotaModify', {
        'idserial': limits.idSerial,
        'maxconsamt': limits.qrPerTransaction.value.toString(),
        'maxconstotalamt': limits.qrPerDay.value.toString(),
        'qrcodeid': limits.qrCodeId,
        'txpasswd': transactionPassword,
      }),
      context: 'QRCODE_LIMITS_UPDATE',
    );
    _requireSuccess(response, '二维码消费限额修改失败。', 'QRCODE_LIMITS_UPDATE_REJECTED');
  }

  @override
  Future<void> changeSpendingPassword({
    required String accountKey,
    required String oldPassword,
    required String newPassword,
  }) async {
    _validatePassword(oldPassword);
    _validatePassword(newPassword);
    if (accountKey.trim().isEmpty) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '消费密码账户标识缺失。',
        code: 'PASSWORD_ACCOUNT_KEY_REQUIRED',
      );
    }
    final response = requireObjectMap(
      await _client.post('/virtualcard/qrcodePwdModify', {
        'idserial': accountKey,
        'txpasswd': oldPassword,
        'newpwd': newPassword,
        'okpassword': newPassword,
        'flag': 1,
      }),
      context: 'PASSWORD_UPDATE',
    );
    _requireSuccess(response, '消费密码修改失败。', 'PASSWORD_UPDATE_REJECTED');
  }

  void _validatePassword(String value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '消费密码必须为 6 位数字。',
        code: 'PASSWORD_FORMAT_INVALID',
      );
    }
  }

  void _validateLimits(MoneyFen perTransaction, MoneyFen perDay) {
    if (perTransaction.value <= 0 || perDay.value < perTransaction.value) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '单日限额不能低于单笔限额。',
        code: 'SPENDING_LIMITS_INVALID',
      );
    }
  }

  void _requireSuccess(
    Map<String, Object?> response,
    String fallback,
    String code,
  ) {
    final responseCode = response['message']?.toString().trim();
    if (apiSuccess(response) ||
        responseCode == 'CORE10007' ||
        responseCode == 'CORE10008') {
      return;
    }
    throw AppFailure(
      FailureKind.server,
      apiMessage(response, fallback: fallback),
      code: code,
    );
  }
}
