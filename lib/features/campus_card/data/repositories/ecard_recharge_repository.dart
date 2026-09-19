import '../../core/errors/app_failure.dart';
import '../../domain/models/security_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/security_ports.dart';
import '../api/ecard_api_client.dart';

/// Real recharge adapter with a deliberately split trust boundary.
///
/// Initialization and channel discovery are query-only. Order creation and
/// status reporting stay fail-closed until the corresponding write contract is
/// independently authorized and verified.
final class EcardRechargeRepository implements RechargePort {
  EcardRechargeRepository(this._client);

  final EcardTransport _client;

  @override
  Future<RechargeInitialization> initialize() async {
    final response = requireObjectMap(
      await _client.post('/cardpay/openCardPay', const {}),
      context: 'RECHARGE_INITIALIZATION',
    );
    if (apiRejected(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '充值服务初始化失败。'),
        code: 'RECHARGE_INITIALIZATION_REJECTED',
      );
    }
    final data = response['data'] is Map
        ? requireObjectMap(
            response['data'],
            context: 'RECHARGE_INITIALIZATION_DATA',
          )
        : response;
    final cardPay = requireObjectMap(
      data['cardPay'],
      context: 'RECHARGE_CARD_PAY',
    );
    final accountKey = cardPay['idserial']?.toString() ?? '';
    if (accountKey.isEmpty) {
      throw const AppFailure(
        FailureKind.protocol,
        '充值服务未返回完整账户字段。',
        code: 'RECHARGE_ACCOUNT_KEY_MISSING',
      );
    }
    return RechargeInitialization(
      accountKey: accountKey,
      balance: MoneyFen.fromApiYuan(cardPay['cardbal'] ?? 0, field: 'cardbal'),
      disableAccountPrefix: data['disableidserialstart']?.toString(),
      applicationId: data['appid']?.toString(),
    );
  }

  @override
  Future<List<RechargeChannelInfo>> channels({required String menuId}) async {
    final trimmed = menuId.trim();
    if (trimmed.isEmpty) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '充值渠道标识缺失。',
        code: 'RECHARGE_MENU_ID_REQUIRED',
      );
    }
    final response = await _client.getPlain('/queryPayInfoList', {
      'menuid': trimmed,
    });
    final raw = switch (response) {
      final List<Object?> list => list,
      final Map<Object?, Object?> map =>
        map['data'] ?? map['resultData'] ?? const <Object?>[],
      _ => const <Object?>[],
    };
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          RechargeChannelInfo(
            payWay: item['payway']?.toString() ?? '',
            payName: item['payname']?.toString() ?? '',
          ),
    ].where((channel) => channel.payWay.isNotEmpty).toList(growable: false);
  }

  @override
  Future<RechargeOrder> create({
    required MoneyFen amount,
    required RechargeChannel channel,
  }) =>
      Future.error(_writeUnavailable());

  @override
  Future<RechargeOrder> status(String orderId) =>
      Future.error(_writeUnavailable());

  AppFailure _writeUnavailable() => const AppFailure(
        FailureKind.unavailable,
        '充值下单尚未获得远端写操作授权。',
        code: 'RECHARGE_WRITE_NOT_AUTHORIZED',
      );
}
