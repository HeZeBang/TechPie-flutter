import 'package:clock/clock.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/bill_models.dart';
import '../../domain/models/card_models.dart';
import '../../domain/models/offline_models.dart';
import '../../domain/models/payment_models.dart';
import '../../domain/models/profile_models.dart';
import '../../domain/models/scan_models.dart';
import '../../domain/models/security_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/bill_ports.dart';
import '../../domain/ports/card_ports.dart';
import '../../domain/ports/offline_ports.dart';
import '../../domain/ports/payment_ports.dart';
import '../../domain/ports/security_ports.dart';
import '../api/qr_payload_codec.dart';
import 'demo_scenarios.dart';

final class DemoPaymentCodeRepository implements PaymentCodeRepository {
  DemoPaymentCodeRepository(this._scenario, {Clock? clock})
      : _clock = clock ?? const Clock();

  final DemoScenarioController _scenario;
  final Clock _clock;
  bool _activated = false;

  @override
  Future<void> activateOnlineCode() async {
    _activated = true;
  }

  @override
  Future<PaymentCodeFrame> generateOnlineCode() async {
    if (_scenario.scenario == DemoScenario.onlineActivationRequired &&
        !_activated) {
      throw const AppFailure(
        FailureKind.unavailable,
        '尚未开通校园付款码。',
        code: 'PAYMENT_CODE_NOT_ACTIVATED',
      );
    }
    if (_scenario.scenario == DemoScenario.onlinePaymentFailure) {
      throw const AppFailure(
        FailureKind.server,
        '演示：付款码服务暂时不可用。',
        code: 'DEMO_PAYMENT_CODE_FAILURE',
        retryable: true,
      );
    }
    final generation = ++_scenario.paymentCodeGeneration;
    final raw =
        '5638${generation.toString().padLeft(4, '0')}A1B2C3D4E5F60718293A4B5C6D7E8F90';
    return PaymentCodeFrame(
      payCode: 'DEMO-PAY-${generation.toString().padLeft(4, '0')}',
      rawQrCode: raw,
      qrPayload: QrPayloadCodec.online(raw),
      offlineAllowed: true,
      generatedAt: _clock.now().toUtc(),
    );
  }

  @override
  Future<PaymentCodePollResult> pollTransaction(String payCode, {PaymentRequestContext? context}) async {
    if (_scenario.scenario == DemoScenario.onlineGatewayFallback) {
      return const PaymentShouldUseOffline('开放平台请求超时');
    }
    final count = ++_scenario.paymentPollCount;
    if (count < 2) return const PaymentPending();
    return PaymentCompleted(
      TransactionResult(
        amount: const MoneyFen(1280),
        confirmedLocallyAt: _clock.now().toUtc(),
        merchantName: '演示校园餐厅',
        terminalNumber: 'DEMO-01',
        tradeAt: _clock.now().toUtc(),
        orderId: 'DEMO-ORDER-0001',
        balance: const MoneyFen(8620),
        fee: MoneyFen.zero,
      ),
    );
  }
}

final class DemoScanPaymentRepository implements ScanPaymentRepository {
  DemoScanPaymentRepository(this._scenario);
  final DemoScenarioController _scenario;

  @override
  Future<ScanPaymentResult> submit({
    required String qrCode,
    required DateTime payTime,
    String? password,
    PaymentRequestContext? context,
  }) async {
    ++_scenario.scanSubmissionCount;
    final scenario = _scenario.scenario;
    if ((scenario == DemoScenario.scanPasswordRequired ||
            scenario == DemoScenario.scanPasswordError ||
            qrCode == 'DEMO-NEED-PASSWORD') &&
        password == null) {
      return const ScanPasswordRequired(
        serverQrCode: 'DEMO-SERVER-QR-ORIGINAL',
      );
    }
    if (password != null && password != '246810') {
      return const ScanFailed(message: '演示：消费密码错误。', code: '2005');
    }
    final kind = switch (scenario) {
      DemoScenario.scanAttendance => ScanSuccessKind.attendance,
      DemoScenario.scanOpenDevice => ScanSuccessKind.openDevice,
      DemoScenario.scanBindTray => ScanSuccessKind.bindTray,
      DemoScenario.scanUnknownType => ScanSuccessKind.unknown,
      _ => ScanSuccessKind.payment,
    };
    return ScanSucceeded(
      kind: kind,
      amount: kind == ScanSuccessKind.payment ? const MoneyFen(850) : null,
      fee: kind == ScanSuccessKind.payment ? MoneyFen.zero : null,
      balance: kind == ScanSuccessKind.payment ? const MoneyFen(9050) : null,
      message: '演示操作成功',
    );
  }
}

final class DemoCardRepository implements CardRepository {
  DemoCardRepository(
    this._scenario, {
    required Future<void> Function() onUnbind,
  }) : _onUnbind = onUnbind;

  final DemoScenarioController _scenario;
  final Future<void> Function() _onUnbind;
  bool _bound = true;

  @override
  Future<CampusCard?> currentCard() async {
    if (!_bound) return null;
    return CampusCard(
      id: 'DEMO-CARD-0001',
      maskedNumber: '••••0001',
      ownerName: '极客同学',
      balance: const MoneyFen(9900),
      status: _scenario.scenario == DemoScenario.cardFrozen
          ? CampusCardStatus.frozen
          : CampusCardStatus.normal,
      positionName: '学生',
      positionCode: '01',
      offlineCodeAllowed: true,
    );
  }

  @override
  Future<UserProfile> profile() async => const UserProfile(
        displayName: '极客同学',
        maskedCardNumber: '••••0001',
        positionName: '学生',
      );

  @override
  Future<BindCardResult> bind(BindCardCommand command) async {
    command.validate();
    _bound = true;
    return const BindCardResult(offlineCodeAllowed: true);
  }

  @override
  Future<void> unbind({required String cardPassword}) async {
    if (!RegExp(r'^\d{6}$').hasMatch(cardPassword)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '请输入 6 位卡片查询密码。',
        code: 'DEMO_CARD_PASSWORD_INVALID',
      );
    }
    _bound = false;
    await _onUnbind();
  }
}

final class DemoBillSummaryRepository implements BillSummaryRepository {
  DemoBillSummaryRepository(this._scenario);
  final DemoScenarioController _scenario;

  static const _months = [
    '2026-03',
    '2026-04',
    '2026-05',
    '2026-06',
    '2026-07',
    '2026-08',
  ];

  @override
  Future<List<String>> availableMonths() async => _months;

  @override
  Future<BillSummary> summary(String month) async {
    final empty = _scenario.scenario == DemoScenario.emptyBillMonth;
    return BillSummary(
      month: month,
      availableMonths: _months,
      spendingTotal: empty ? MoneyFen.zero : const MoneyFen(126840),
      spendingCategories: empty
          ? const []
          : const [
              BillCategory(name: '餐饮', amount: MoneyFen(78640)),
              BillCategory(name: '超市', amount: MoneyFen(28300)),
              BillCategory(name: '交通', amount: MoneyFen(11900)),
              BillCategory(name: '其他', amount: MoneyFen(8000)),
            ],
      halfYearTrend: const [
        MonthlyTrendPoint(month: '2026-03', amount: MoneyFen(98200)),
        MonthlyTrendPoint(month: '2026-04', amount: MoneyFen(105600)),
        MonthlyTrendPoint(month: '2026-05', amount: MoneyFen(118900)),
        MonthlyTrendPoint(month: '2026-06', amount: MoneyFen(94600)),
        MonthlyTrendPoint(month: '2026-07', amount: MoneyFen(111500)),
        MonthlyTrendPoint(month: '2026-08', amount: MoneyFen(126840)),
      ],
      rechargeTotal: empty ? MoneyFen.zero : const MoneyFen(200000),
      rechargeCategories: empty
          ? const []
          : const [BillCategory(name: '银行卡', amount: MoneyFen(200000))],
      fun: FunBillSummary(
        breakfastCount: empty ? 0 : 18,
        breakfastAmount: empty ? MoneyFen.zero : const MoneyFen(21600),
        lunchCount: empty ? 0 : 21,
        lunchAmount: empty ? MoneyFen.zero : const MoneyFen(35700),
        dinnerCount: empty ? 0 : 17,
        dinnerAmount: empty ? MoneyFen.zero : const MoneyFen(30600),
        foodTotalAmount: empty ? MoneyFen.zero : const MoneyFen(87900),
        sportAmount: empty ? MoneyFen.zero : const MoneyFen(8000),
        sportDays: empty ? 0 : 8,
        sportTimes: empty ? 0 : 12,
        networkAmount: empty ? MoneyFen.zero : const MoneyFen(3000),
        networkTimes: empty ? 0 : 1,
      ),
    );
  }
}

final class DemoTransactionHistoryPort
    implements TransactionHistoryPort, DateRangeTransactionHistoryPort {
  DemoTransactionHistoryPort({Clock? clock}) : _clock = clock ?? const Clock();
  final Clock _clock;

  late final List<TransactionRecord> _records = List.generate(
    36,
    (index) {
      final recharge = index == 8 || index == 24;
      return TransactionRecord(
        id: 'DEMO-TX-${(index + 1).toString().padLeft(4, '0')}',
        occurredAt: _clock.now().toUtc().subtract(Duration(hours: index * 7)),
        title: recharge
            ? '校园卡充值'
            : index.isEven
                ? '演示校园餐厅'
                : '演示校园超市',
        amount:
            recharge ? const MoneyFen(100000) : MoneyFen(-(650 + index * 35)),
        kind: recharge ? TransactionKind.recharge : TransactionKind.consumption,
        merchantName: recharge
            ? null
            : index.isEven
                ? '演示校园餐厅'
                : '演示校园超市',
        location: recharge ? null : '演示校区',
        balance: MoneyFen(9900 + index * 650),
      );
    },
    growable: false,
  );

  @override
  Future<TransactionRecord> detail(String id) async => _records.firstWhere(
        (record) => record.id == id,
        orElse: () => throw const AppFailure(
          FailureKind.invalidInput,
          '未找到这笔演示交易。',
          code: 'DEMO_TRANSACTION_NOT_FOUND',
        ),
      );

  @override
  Future<TransactionPage> timeline({
    required String month,
    String? cursor,
    int pageSize = 20,
  }) =>
      _page(_records, cursor: cursor, pageSize: pageSize);

  @override
  Future<TransactionPage> timelineRange({
    DateTime? begin,
    DateTime? end,
    String? cursor,
    int pageSize = 20,
  }) {
    final filtered = _records.where((record) {
      if (begin != null && record.occurredAt.isBefore(begin)) return false;
      if (end != null && record.occurredAt.isAfter(end)) return false;
      return true;
    }).toList();
    return _page(filtered, cursor: cursor, pageSize: pageSize);
  }

  Future<TransactionPage> _page(
    List<TransactionRecord> records, {
    required String? cursor,
    required int pageSize,
  }) async {
    final offset = int.tryParse(cursor ?? '0') ?? 0;
    final safeSize = pageSize.clamp(1, 50);
    final end = (offset + safeSize).clamp(0, records.length);
    final items = offset >= records.length
        ? const <TransactionRecord>[]
        : records.sublist(offset, end);
    return TransactionPage(
      items: items,
      hasMore: end < records.length,
      nextCursor: end < records.length ? end.toString() : null,
    );
  }
}

final class DemoRechargePort implements RechargePort {
  DemoRechargePort({Clock? clock}) : _clock = clock ?? const Clock();
  final Clock _clock;
  final Map<String, RechargeOrder> _orders = {};

  @override
  Future<RechargeInitialization> initialize() async =>
      const RechargeInitialization(
        accountKey: 'DEMO-RECHARGE-ACCOUNT',
        balance: MoneyFen(9900),
        applicationId: 'demo-application',
      );

  @override
  Future<List<RechargeChannelInfo>> channels({required String menuId}) async =>
      const [
        RechargeChannelInfo(payWay: 'demo-bank', payName: '演示渠道A（银行卡）'),
        RechargeChannelInfo(payWay: 'demo-campus', payName: '演示渠道B（校园卡）'),
        RechargeChannelInfo(payWay: 'demo-third', payName: '演示渠道C（第三方）'),
      ];

  @override
  Future<RechargeOrder> create({
    required MoneyFen amount,
    required RechargeChannel channel,
  }) async {
    if (amount.value <= 0) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '充值金额必须大于 0。',
        code: 'DEMO_RECHARGE_AMOUNT_INVALID',
      );
    }
    final id =
        'DEMO-RECHARGE-${(_orders.length + 1).toString().padLeft(4, '0')}';
    final order = RechargeOrder(
      id: id,
      amount: amount,
      channel: channel,
      state: RechargeOrderState.processing,
      createdAt: _clock.now().toUtc(),
    );
    _orders[id] = order;
    return order;
  }

  @override
  Future<RechargeOrder> status(String orderId) async {
    final current = _orders[orderId];
    if (current == null) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '未找到这笔演示充值。',
        code: 'DEMO_RECHARGE_NOT_FOUND',
      );
    }
    final completed = RechargeOrder(
      id: current.id,
      amount: current.amount,
      channel: current.channel,
      state: RechargeOrderState.succeeded,
      createdAt: current.createdAt,
      message: '演示充值成功',
    );
    _orders[orderId] = completed;
    return completed;
  }
}

final class DemoSecuritySettingsPort implements SecuritySettingsPort {
  SpendingLimits _limits = const SpendingLimits(
    idSerial: 'DEMO-STUDENT-0001',
    cardId: 'DEMO-CARD-0001',
    qrCodeId: 'DEMO-QR-0001',
    haveCard: true,
    haveQrCode: true,
    cardPerTransaction: MoneyFen(20000),
    cardPerDay: MoneyFen(50000),
    qrPerTransaction: MoneyFen(5000),
    qrPerDay: MoneyFen(20000),
    displayName: '极客同学',
  );

  @override
  Future<SpendingPasswordInitialization> initializePasswordChange() async =>
      const SpendingPasswordInitialization(
        accountKey: 'DEMO-PASSWORD-ACCOUNT',
        haveCard: true,
        displayName: '极客同学',
      );

  @override
  Future<void> changeSpendingPassword({
    required String accountKey,
    required String oldPassword,
    required String newPassword,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(oldPassword) ||
        !RegExp(r'^\d{6}$').hasMatch(newPassword)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '消费密码必须为 6 位数字。',
        code: 'DEMO_PASSWORD_INVALID',
      );
    }
  }

  @override
  Future<SpendingLimits> readLimits() async => _limits;

  @override
  Future<void> updateCardLimits(SpendingLimits limits) async {
    if (limits.cardPerTransaction.value <= 0 ||
        limits.cardPerDay.compareTo(limits.cardPerTransaction) < 0) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '单日限额不能低于单笔限额。',
        code: 'DEMO_LIMIT_INVALID',
      );
    }
    _limits = limits;
  }

  @override
  Future<void> updateQrLimits(
    SpendingLimits limits, {
    required String transactionPassword,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(transactionPassword) ||
        limits.qrPerTransaction.value <= 0 ||
        limits.qrPerDay.compareTo(limits.qrPerTransaction) < 0) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '二维码限额或消费密码无效。',
        code: 'DEMO_QR_LIMIT_INVALID',
      );
    }
    _limits = limits;
  }
}

final class DemoOfflineAuthorizationRemotePort
    implements OfflineAuthorizationRemotePort {
  DemoOfflineAuthorizationRemotePort(this._scenario, {Clock? clock})
      : _clock = clock ?? const Clock();

  final DemoScenarioController _scenario;
  final Clock _clock;

  @override
  Future<OfflineActivationResponse> activate(
    OfflineActivationRequest request,
  ) async =>
      OfflineActivationResponse(
        authorInfo: '5638A1B2C3D4E5F60718293A4B5C6D7E',
        totalUses: _scenario.scenario == DemoScenario.offlineExhausted ? 0 : 20,
        expiresOn: _scenario.scenario == DemoScenario.offlineExpired
            ? _clock.now().toUtc().subtract(const Duration(days: 1))
            : _clock.now().toUtc().add(const Duration(days: 30)),
      );

  @override
  Future<OfflineActivationResponse?> renew(
    OfflineAuthorization authorization,
  ) async =>
      OfflineActivationResponse(
        authorInfo: '5638F1E2D3C4B5A69788776655443322',
        totalUses: 20,
        expiresOn: _clock.now().toUtc().add(const Duration(days: 30)),
      );
}
