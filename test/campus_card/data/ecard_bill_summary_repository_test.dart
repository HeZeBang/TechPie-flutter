import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_bill_summary_repository.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';

void main() {
  test('uses only the three approved bill endpoints and exact units', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/bill/openMyBill', {
        'success': true,
        'data': {
          'billDateList': ['2026-07', '2026-08'],
          'currentBillDate': '2026-08',
        },
      })
      ..enqueue('POST', '/bill/queryUserMonthlybill', {
        'success': true,
        'resultData': {
          'sumamt': '12.34',
          'billList': [
            {'name': '餐饮', 'value': '10.05'},
          ],
        },
      })
      ..enqueue('POST', '/bill/queryRechargeGroupByTxcode', {
        'success': true,
        'resultData': {
          'sumamt': 20000,
          'billList': [
            {'txname': '银行卡', 'txamt': 20000},
          ],
        },
      });

    final summary = await EcardBillSummaryRepository(
      transport,
    ).summary('2026-08');

    expect(summary.spendingTotal, const MoneyFen(1234));
    expect(summary.spendingCategories.single.amount, const MoneyFen(1005));
    expect(summary.rechargeTotal, const MoneyFen(20000));
    expect(summary.rechargeCategories.single.amount, const MoneyFen(20000));
    expect(summary.halfYearTrend, isEmpty);
    expect(transport.requests.map((request) => request.path).toSet(), {
      '/bill/openMyBill',
      '/bill/queryUserMonthlybill',
      '/bill/queryRechargeGroupByTxcode',
    });
  });

  test('parses resultData before treating CORE10008 as an error', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/bill/openMyBill', {
        'success': true,
        'data': {
          'billDateList': ['2026-08'],
          'currentBillDate': '2026-08',
        },
      })
      ..enqueue('POST', '/bill/queryUserMonthlybill', {
        'success': true,
        'message': 'CORE10008',
        'resultData': {'sumamt': '0.00', 'billList': <Object>[]},
      })
      ..enqueue('POST', '/bill/queryRechargeGroupByTxcode', {
        'success': true,
        'message': 'CORE10008',
        'resultData': {'sumamt': 0, 'billList': <Object>[]},
      });

    final summary = await EcardBillSummaryRepository(
      transport,
    ).summary('2026-08');

    expect(summary.spendingTotal, MoneyFen.zero);
    expect(summary.rechargeTotal, MoneyFen.zero);
  });

  test('rejects sub-fen precision instead of rounding', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/bill/openMyBill', {
        'success': true,
        'data': {
          'billDateList': ['2026-08'],
          'currentBillDate': '2026-08',
        },
      })
      ..enqueue('POST', '/bill/queryUserMonthlybill', {
        'success': true,
        'resultData': {'sumamt': '1.001', 'billList': <Object>[]},
      })
      ..enqueue('POST', '/bill/queryRechargeGroupByTxcode', {
        'success': true,
        'resultData': {'sumamt': 0, 'billList': <Object>[]},
      });

    await expectLater(
      EcardBillSummaryRepository(transport).summary('2026-08'),
      throwsFormatException,
    );
  });
}
