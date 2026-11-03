import '../models/security_models.dart';

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
