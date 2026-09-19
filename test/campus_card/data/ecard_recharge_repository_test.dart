import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_recharge_repository.dart';
import 'package:techpie/features/campus_card/domain/models/security_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';

void main() {
  test('reads recharge initialization without creating an order', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/cardpay/openCardPay', {
        'success': true,
        'data': {
          'cardPay': {'idserial': 'SYNTHETIC-ACCOUNT', 'cardbal': '92.07'},
          'disableidserialstart': '0000',
          'appid': 'synthetic-app',
        },
      });
    final repository = EcardRechargeRepository(transport);

    final initialization = await repository.initialize();

    expect(initialization.accountKey, 'SYNTHETIC-ACCOUNT');
    expect(initialization.balance, const MoneyFen(9207));
    expect(initialization.applicationId, 'synthetic-app');
    expect(transport.requests, hasLength(1));
  });

  test('reads a plain-query channel list and accepts an empty list', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET_PLAIN', '/queryPayInfoList', {
        'data': [
          {'payway': 'SYNTHETIC_WAY', 'payname': '合成渠道'},
        ],
      })
      ..enqueue('GET_PLAIN', '/queryPayInfoList', {'data': <Object?>[]});
    final repository = EcardRechargeRepository(transport);

    final channels = await repository.channels(menuId: 'synthetic-menu');
    final empty = await repository.channels(menuId: 'synthetic-menu');

    expect(channels, const [
      RechargeChannelInfo(payWay: 'SYNTHETIC_WAY', payName: '合成渠道'),
    ]);
    expect(empty, isEmpty);
  });

  test('order writes fail before any remote request', () async {
    final transport = FakeEcardTransport();
    final repository = EcardRechargeRepository(transport);

    await expectLater(
      repository.create(
        amount: const MoneyFen(1000),
        channel: RechargeChannel.bankTransfer,
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'RECHARGE_WRITE_NOT_AUTHORIZED',
        ),
      ),
    );
    await expectLater(
      repository.status('SYNTHETIC-ORDER'),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'RECHARGE_WRITE_NOT_AUTHORIZED',
        ),
      ),
    );
    expect(transport.requests, isEmpty);
  });
}
