import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_payment_code_repository.dart';
import 'package:techpie/features/campus_card/domain/models/payment_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';
import '../support/successful_payment_poll.dart';

void main() {
  test('preserves yuan amounts including cents without a 100-fold reduction',
      () async {
    for (final value in ['38.00', '8.80', '0.01', '0.00', 38, 8.8]) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/virtualcard/queryOrderStatus', {
          ...successfulPaymentPoll,
          'data': {
            ...(successfulPaymentPoll['data']! as Map<String, Object?>),
            'txamt': value,
          },
        });
      final result = await EcardPaymentCodeRepository(transport)
          .pollTransaction('synthetic-code') as PaymentCompleted;
      final expected = switch (value) {
        '38.00' || 38 => '38.00',
        '8.80' || 8.8 => '8.80',
        '0.01' => '0.01',
        _ => '0.00',
      };
      expect(result.result.amount.toYuanFixed(), expected);
    }
  });

  test('rejects malformed, negative and sub-fen payment amounts', () async {
    for (final value in ['invalid', '-1.00', '0.001']) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/virtualcard/queryOrderStatus', {
          ...successfulPaymentPoll,
          'data': {
            ...(successfulPaymentPoll['data']! as Map<String, Object?>),
            'txamt': value,
          },
        });
      await expectLater(
        EcardPaymentCodeRepository(transport).pollTransaction('synthetic-code'),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            'PAYMENT_RESULT_AMOUNT_INVALID',
          ),
        ),
      );
    }
  });

  test('recognizes the captured successful payment contract', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', successfulPaymentPoll);
    final result = await EcardPaymentCodeRepository(transport)
        .pollTransaction('synthetic-code');
    expect(result, isA<PaymentCompleted>());
    final transaction = (result as PaymentCompleted).result;
    expect(transaction.amount, const MoneyFen(880));
    expect(transaction.orderId, 'SYNTHETIC-ORDER');
    expect(transaction.merchantName, '示例商户');
  });

  test('success destination cannot override failed, missing, or unknown status',
      () async {
    for (final status in [2, 9, null]) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/virtualcard/queryOrderStatus', {
          ...successfulPaymentPoll,
          'data': {
            ...(successfulPaymentPoll['data']! as Map<String, Object?>),
            'status': status,
            'message': '',
          },
        });
      expect(
          await EcardPaymentCodeRepository(transport)
              .pollTransaction('synthetic-code'),
          isA<PaymentNotCompleted>(),);
    }
  });
  test('uses live POST contract and accepts code as QR fallback', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/offlineCode/openVirtualcard', {
        'success': true,
        'data': {
          'code': '5638AABBCCDD',
          'qrcode': '',
          'allowOfflineCode': '1',
          'idserial': 'SYNTHETIC-STUDENT',
        },
      });
    final repository = EcardPaymentCodeRepository(
      transport,
      clock: Clock.fixed(DateTime.utc(2026, 9, 1)),
    );

    final frame = await repository.generateOnlineCode();

    expect(frame.payCode, '5638AABBCCDD');
    expect(frame.rawQrCode, '5638AABBCCDD');
    expect(frame.qrPayload, isNotEmpty);
    expect(transport.requests.single.method, 'POST');
  });

  test('distinguishes unused and expired live statuses', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {'status': 5, 'txamt': 0},
      })
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {'status': 3, 'txamt': 0},
      });
    final repository = EcardPaymentCodeRepository(transport);

    expect(await repository.pollTransaction('code-1'), isA<PaymentPending>());
    expect(
      await repository.pollTransaction('code-1'),
      isA<PaymentCodeExpired>(),
    );
  });

  test('keeps polling when the query has no confirmed result', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': false,
        'message': 'synthetic rejection',
      })
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {'status': 1},
      });
    final repository = EcardPaymentCodeRepository(transport);

    expect(
      await repository.pollTransaction('code-1'),
      isA<PaymentPending>(),
    );
    expect(
      await repository.pollTransaction('code-1'),
      isA<PaymentPending>(),
    );
  });

  test('unused-code failure wording is a pending result, never a rejection',
      () async {
    for (final success in [true, false]) {
      for (final status in [5, null]) {
        final transport = FakeEcardTransport()
          ..enqueue('POST', '/virtualcard/queryOrderStatus', {
            'success': success,
            'data': {
              if (status != null) 'status': status,
              'message': '支付失败，付款码未使用',
              'txamt': 0,
            },
          });
        expect(
          await EcardPaymentCodeRepository(transport).pollTransaction('code'),
          isA<PaymentPending>(),
        );
      }
    }
  });

  test('converts the successful result page amount from yuan to fen', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {
          'status': 1,
          'txamt': '8.80',
          'url': '/pages/common/paysuccess/paysuccess',
          'paytime': '2026-09-02 12:30:45',
        },
      });
    final repository = EcardPaymentCodeRepository(
      transport,
      clock: Clock.fixed(DateTime.utc(2026, 9, 1)),
    );

    final result = await repository.pollTransaction('code-1');

    expect(result, isA<PaymentCompleted>());
    expect((result as PaymentCompleted).result.amount, const MoneyFen(880));
    expect(result.result.tradeAt, DateTime(2026, 9, 2, 12, 30, 45).toUtc());
  });

  test('a failure result URL and amount never imply payment success', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {
          'status': 2,
          'txamt': '880.00',
          'url': '/pages/common/payfailure/payfailure',
          'message': '密码错误',
        },
      });
    final result = await EcardPaymentCodeRepository(transport)
        .pollTransaction('test-failed-code');

    expect(result, isA<PaymentNotCompleted>());
    expect((result as PaymentNotCompleted).reason, '密码错误');
  });

  test('a password error overrides a contradictory success result URL',
      () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {
          'status': 1,
          'txamt': 880,
          'url': '/pages/common/paysuccess/paysuccess',
          'message': '密码错误',
        },
      });
    expect(
      await EcardPaymentCodeRepository(transport).pollTransaction('code'),
      isA<PaymentNotCompleted>(),
    );
  });

  test('unrecognized result destinations do not confirm payment', () async {
    for (final url in [
      '/pages/common/payfailure/payfailure',
      '/unknown-result?next=/pages/common/paysuccess/paysuccess',
    ]) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/virtualcard/queryOrderStatus', {
          'success': true,
          'data': {'status': 9, 'txamt': 880, 'url': url},
        });
      expect(
        await EcardPaymentCodeRepository(transport).pollTransaction('code'),
        isA<PaymentNotCompleted>(),
      );
    }
  });

  test('nested rejection cannot confirm a successful payment', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/queryOrderStatus', {
        'success': true,
        'data': {
          'success': false,
          'txamt': 880,
          'url': '/pages/common/paysuccess/paysuccess',
        },
      });
    expect(
      await EcardPaymentCodeRepository(transport).pollTransaction('code'),
      isA<PaymentNotCompleted>(),
    );
  });

  test('gateway failures still select offline fallback', () async {
    for (final message in ['开放平台返回失败', '开放平台请求超时']) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/virtualcard/queryOrderStatus', {
          'success': false,
          'message': message,
        });
      expect(
        await EcardPaymentCodeRepository(transport).pollTransaction('code'),
        isA<PaymentShouldUseOffline>(),
      );
    }
  });
}
