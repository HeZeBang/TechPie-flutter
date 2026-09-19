enum DemoScenario {
  standard,
  onlineActivationRequired,
  onlineGatewayFallback,
  onlinePaymentFailure,
  scanPasswordRequired,
  scanPasswordError,
  scanAttendance,
  scanOpenDevice,
  scanBindTray,
  scanUnknownType,
  emptyBillMonth,
  offlineExpired,
  offlineExhausted,
  cardFrozen,
}

final class DemoScenarioController {
  DemoScenarioController([this.scenario = DemoScenario.standard]);

  DemoScenario scenario;
  int paymentCodeGeneration = 0;
  int paymentPollCount = 0;
  int scanSubmissionCount = 0;

  void resetCounters() {
    paymentCodeGeneration = 0;
    paymentPollCount = 0;
    scanSubmissionCount = 0;
  }
}
