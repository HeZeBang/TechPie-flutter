import '../../core/errors/app_failure.dart';
import '../../domain/models/bill_models.dart';
import '../../domain/models/offline_models.dart';
import '../../domain/models/security_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/bill_ports.dart';
import '../../domain/ports/offline_ports.dart';
import '../../domain/ports/security_ports.dart';

final class DisabledTransactionHistoryPort implements TransactionHistoryPort {
  const DisabledTransactionHistoryPort();

  @override
  Future<TransactionRecord> detail(String id) => Future.error(_unavailable());

  @override
  Future<TransactionPage> timeline({
    required String month,
    String? cursor,
    int pageSize = 20,
  }) =>
      Future.error(_unavailable());

  AppFailure _unavailable() => const AppFailure(
        FailureKind.unavailable,
        '逐笔账单服务暂未开放。',
        code: 'TRANSACTION_HISTORY_UNAVAILABLE',
      );
}

final class DisabledRechargePort implements RechargePort {
  const DisabledRechargePort();

  @override
  Future<RechargeInitialization> initialize() => Future.error(_unavailable());

  @override
  Future<List<RechargeChannelInfo>> channels({required String menuId}) =>
      Future.error(_unavailable());

  @override
  Future<RechargeOrder> create({
    required MoneyFen amount,
    required RechargeChannel channel,
  }) =>
      Future.error(_unavailable());

  @override
  Future<RechargeOrder> status(String orderId) => Future.error(_unavailable());

  AppFailure _unavailable() => const AppFailure(
        FailureKind.unavailable,
        '卡片充值服务暂未开放。',
        code: 'RECHARGE_UNAVAILABLE',
      );
}

final class DisabledSecuritySettingsPort implements SecuritySettingsPort {
  const DisabledSecuritySettingsPort();

  @override
  Future<SpendingPasswordInitialization> initializePasswordChange() =>
      Future.error(
        _unavailable('消费密码服务暂未开放。', 'PASSWORD_INITIALIZATION_UNAVAILABLE'),
      );

  @override
  Future<void> changeSpendingPassword({
    required String accountKey,
    required String oldPassword,
    required String newPassword,
  }) =>
      Future.error(
        _unavailable('消费密码修改服务暂未开放。', 'PASSWORD_CHANGE_UNAVAILABLE'),
      );

  @override
  Future<SpendingLimits> readLimits() =>
      Future.error(_unavailable('限额服务暂未开放。', 'SPENDING_LIMITS_UNAVAILABLE'));

  @override
  Future<void> updateCardLimits(SpendingLimits limits) =>
      Future.error(_unavailable('限额服务暂未开放。', 'SPENDING_LIMITS_UNAVAILABLE'));

  @override
  Future<void> updateQrLimits(
    SpendingLimits limits, {
    required String transactionPassword,
  }) =>
      Future.error(_unavailable('限额服务暂未开放。', 'SPENDING_LIMITS_UNAVAILABLE'));

  AppFailure _unavailable(String message, String code) =>
      AppFailure(FailureKind.unavailable, message, code: code);
}

final class DisabledOfflineAuthorizationRemotePort
    implements OfflineAuthorizationRemotePort {
  const DisabledOfflineAuthorizationRemotePort();

  @override
  Future<OfflineActivationResponse> activate(
    OfflineActivationRequest request,
  ) =>
      Future.error(_unavailable());

  @override
  Future<OfflineActivationResponse?> renew(
    OfflineAuthorization authorization,
  ) =>
      Future.error(_unavailable());

  AppFailure _unavailable() => const AppFailure(
        FailureKind.unavailable,
        '真实离线付款开通尚未通过安全确认。',
        code: 'OFFLINE_ACTIVATION_SECURITY_HOLD',
      );
}
