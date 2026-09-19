enum AppEnvironment { demo, staging, production }

final class AppCapabilities {
  const AppCapabilities({
    required this.authConfigured,
    required this.onlinePaymentCode,
    required this.offlinePaymentCode,
    required this.scanPayment,
    required this.transactionHistory,
    required this.cardBinding,
    required this.cardRecharge,
    required this.rechargeInitialization,
    required this.spendingLimits,
    required this.spendingLimitsRead,
    required this.changeSpendingPassword,
    required this.spendingPasswordInitialization,
    required this.profile,
    required this.settings,
  });

  factory AppCapabilities.forEnvironment(AppEnvironment environment) =>
      switch (environment) {
        AppEnvironment.demo => const AppCapabilities(
            authConfigured: true,
            onlinePaymentCode: true,
            offlinePaymentCode: true,
            scanPayment: true,
            transactionHistory: true,
            cardBinding: true,
            cardRecharge: true,
            rechargeInitialization: true,
            spendingLimits: true,
            spendingLimitsRead: true,
            changeSpendingPassword: true,
            spendingPasswordInitialization: true,
            profile: true,
            settings: true,
          ),
        AppEnvironment.staging ||
        AppEnvironment.production =>
          const AppCapabilities(
            authConfigured: true,
            onlinePaymentCode: true,
            offlinePaymentCode: true,
            scanPayment: true,
            transactionHistory: true,
            cardBinding: true,
            cardRecharge: false,
            rechargeInitialization: true,
            spendingLimits: true,
            spendingLimitsRead: true,
            changeSpendingPassword: true,
            spendingPasswordInitialization: true,
            profile: true,
            settings: true,
          ),
      };

  final bool authConfigured;
  final bool onlinePaymentCode;
  final bool offlinePaymentCode;
  final bool scanPayment;
  final bool transactionHistory;
  final bool cardBinding;
  final bool cardRecharge;
  final bool rechargeInitialization;
  final bool spendingLimits;
  final bool spendingLimitsRead;
  final bool changeSpendingPassword;
  final bool spendingPasswordInitialization;
  final bool profile;
  final bool settings;
}
