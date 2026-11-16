enum AppEnvironment { demo, staging, production }

final class AppCapabilities {
  const AppCapabilities({
    required this.spendingLimits,
    required this.spendingLimitsRead,
    required this.changeSpendingPassword,
  });

  factory AppCapabilities.forEnvironment(AppEnvironment environment) =>
      switch (environment) {
        AppEnvironment.demo => const AppCapabilities(
            spendingLimits: true,
            spendingLimitsRead: true,
            changeSpendingPassword: true,
          ),
        AppEnvironment.staging ||
        AppEnvironment.production =>
          const AppCapabilities(
            spendingLimits: true,
            spendingLimitsRead: true,
            changeSpendingPassword: true,
          ),
      };

  final bool spendingLimits;
  final bool spendingLimitsRead;
  final bool changeSpendingPassword;
}
