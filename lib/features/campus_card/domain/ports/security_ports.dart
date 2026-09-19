import '../models/security_models.dart';
import '../money_fen.dart';

abstract interface class RechargePort {
  Future<RechargeInitialization> initialize();

  Future<List<RechargeChannelInfo>> channels({required String menuId});

  Future<RechargeOrder> create({
    required MoneyFen amount,
    required RechargeChannel channel,
  });

  Future<RechargeOrder> status(String orderId);
}

abstract interface class SecuritySettingsPort {
  Future<SpendingPasswordInitialization> initializePasswordChange();

  Future<SpendingLimits> readLimits();
  Future<void> updateCardLimits(SpendingLimits limits);
  Future<void> updateQrLimits(
    SpendingLimits limits, {
    required String transactionPassword,
  });
  Future<void> changeSpendingPassword({
    required String accountKey,
    required String oldPassword,
    required String newPassword,
  });
}
