import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_security_settings_repository.dart';
import 'package:techpie/features/campus_card/domain/models/security_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';

void main() {
  const limits = SpendingLimits(
    idSerial: 'SYNTHETIC-STUDENT',
    cardId: 'SYNTHETIC-CARD',
    qrCodeId: 'SYNTHETIC-QR',
    haveCard: true,
    haveQrCode: true,
    cardPerTransaction: MoneyFen(20000),
    cardPerDay: MoneyFen(50000),
    qrPerTransaction: MoneyFen(5000),
    qrPerDay: MoneyFen(20000),
    displayName: '合成同学',
  );

  test('reads password-change initialization', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/openQrcodePwdModify', {
        'success': true,
        'data': {
          'idserial': 'SYNTHETIC-STUDENT',
          'username': '合成同学',
          'haveCard': '1',
        },
      });
    final repository = EcardSecuritySettingsRepository(transport);

    final initialization = await repository.initializePasswordChange();

    expect(initialization.accountKey, 'SYNTHETIC-STUDENT');
    expect(initialization.displayName, '合成同学');
    expect(initialization.haveCard, isTrue);
  });

  test('reads card and QR limits as exact integer fen', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/openQrcodeQuotaModify', {
        'success': true,
        'data': {
          'cardmaxconsamt': '200.00',
          'cardmaxconstolamt': '500.00',
          'qrcodemaxconsamt': '50.00',
          'qrcodemaxconstolamt': '200.00',
          'idserial': 'SYNTHETIC-STUDENT',
          'cardid': 'SYNTHETIC-CARD',
          'qrcodeid': 'SYNTHETIC-QR',
          'haveCard': '1',
          'haveQrcode': '1',
        },
      });
    final repository = EcardSecuritySettingsRepository(transport);

    final value = await repository.readLimits();

    expect(value.cardPerTransaction, const MoneyFen(20000));
    expect(value.cardPerDay, const MoneyFen(50000));
    expect(value.qrPerTransaction, const MoneyFen(5000));
    expect(value.qrPerDay, const MoneyFen(20000));
  });

  test('writes card limits with integer-fen field names', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/card/cardQuotaModify', {
        'success': true,
        'message': 'CORE10008',
        'resultData': {'id': 34831},
      });

    await EcardSecuritySettingsRepository(transport).updateCardLimits(limits);

    expect(transport.requests.single.data, {
      'idserial': 'SYNTHETIC-STUDENT',
      'maxconsamt': '20000',
      'maxconstolamt': '50000',
      'cardid': 'SYNTHETIC-CARD',
    });
  });

  test('accepts a raw CORE10008 success response for a limit update', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/card/cardQuotaModify', 'CORE10008');

    await EcardSecuritySettingsRepository(transport).updateCardLimits(limits);

    expect(transport.requests, hasLength(1));
  });

  test('writes QR limits with totalamt spelling and password', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/virtualcard/qrcodeQuotaModify', {
        'success': true,
        'message': 'CORE10008',
        'resultData': <String, Object?>{},
      });

    await EcardSecuritySettingsRepository(
      transport,
    ).updateQrLimits(limits, transactionPassword: '111222');

    expect(transport.requests.single.data, {
      'idserial': 'SYNTHETIC-STUDENT',
      'maxconsamt': '5000',
      'maxconstotalamt': '20000',
      'qrcodeid': 'SYNTHETIC-QR',
      'txpasswd': '111222',
    });
  });

  test('writes the verified password-change contract', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/virtualcard/qrcodePwdModify', {
        'success': true,
        'title': '修改密码',
      });

    await EcardSecuritySettingsRepository(transport).changeSpendingPassword(
      accountKey: 'SYNTHETIC-STUDENT',
      oldPassword: '111222',
      newPassword: '333444',
    );

    expect(transport.requests.single.data, {
      'idserial': 'SYNTHETIC-STUDENT',
      'txpasswd': '111222',
      'newpwd': '333444',
      'okpassword': '333444',
      'flag': 1,
    });
  });

  test('surfaces business rejection from HTTP 200', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/virtualcard/qrcodeQuotaModify', {
        'success': false,
        'message': 'synthetic rejected',
      });

    await expectLater(
      EcardSecuritySettingsRepository(
        transport,
      ).updateQrLimits(limits, transactionPassword: '111222'),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.safeMessage,
          'message',
          'synthetic rejected',
        ),
      ),
    );
  });
}
