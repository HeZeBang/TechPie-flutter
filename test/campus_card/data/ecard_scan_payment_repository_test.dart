import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_scan_payment_repository.dart';
import 'package:techpie/features/campus_card/domain/models/scan_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';
import '../support/scan_password_challenge.dart';
import '../support/scan_payment_receipt.dart';

void main() {
  test('captured nested receipt uses yuan and exposes payment metadata', () async {
    final transport = FakeEcardTransport()..enqueue('POST', '/scan/scanningResult', scanPaymentReceipt);
    final result = await EcardScanPaymentRepository(transport).submit(qrCode: 'TEST', payTime: DateTime.utc(2026), password: '123456') as ScanSucceeded;
    expect(result.amount, const MoneyFen(617));
    expect(result.paidAt, DateTime.utc(2026, 9, 13, 14, 40, 31));
    expect(result.authorizationCode, 'A1B2');
    expect(result.transactionId, '0305_20260913224014_A1B2');
    expect(result.terminalCode, '0305');
    expect(result.transactionCode, '1829');
    expect(result.message, isNull);
    expect(result.balance, isNull);
  });

  test('invalid optional receipt fields never convert confirmed success to failure', () async {
    final transport = FakeEcardTransport()..enqueue('POST', '/scan/scanningResult', {
      ...scanPaymentReceipt, 'data': {'txamt': 'bad', 'paytime': '20260230224031'},
    });
    final result = await EcardScanPaymentRepository(transport).submit(qrCode: 'TEST', payTime: DateTime.utc(2026)) as ScanSucceeded;
    expect(result.amount, isNull);
    expect(result.paidAt, isNull);
  });

  test('recognizes inputPass with a nested server QR and no issuccess',
      () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/scan/scanningResult', scanPasswordChallenge);
    final result = await EcardScanPaymentRepository(transport)
        .submit(qrCode: 'CLIENT-CODE', payTime: DateTime.utc(2026, 9, 9));
    expect(result, isA<ScanPasswordRequired>());
    expect(
      (result as ScanPasswordRequired).serverQrCode,
      'SYNTHETIC%20SERVER-QR',
    );
  });

  test('inputPass without a retry QR cannot submit the original scan again',
      () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/scan/scanningResult', {
        ...scanPasswordChallenge,
        'data': <String, Object?>{},
      });
    final result = await EcardScanPaymentRepository(transport)
        .submit(qrCode: 'CLIENT-CODE', payTime: DateTime.utc(2026, 9, 9));
    expect(result, isA<ScanFailed>());
    expect((result as ScanFailed).code, 'SCAN_PASSWORD_QR_MISSING');
  });

  test('a failure destination after password submission is never success',
      () async {
    for (final status in [null, '1']) {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/scan/scanningResult', {
          'success': true,
          if (status != null) 'issuccess': status,
          'data': <String, Object?>{},
          'message': '二维码已使用请刷新重试',
          'url': '/pages/common/fail/fail',
        });
      final result = await EcardScanPaymentRepository(transport).submit(
        qrCode: 'SYNTHETIC%20SERVER-QR',
        payTime: DateTime.utc(2026, 9, 9),
        password: '111222',
      );
      expect(result, isA<ScanFailed>());
    }
  });

  test(
    'requires and preserves the server-returned QR for password retry',
    () async {
      final transport = FakeEcardTransport()
        ..enqueue('POST', '/scan/scanningResult', {
          'success': true,
          'issuccess': '2004',
          'qrcode': 'SERVER-ORIGINAL',
        });
      final result = await EcardScanPaymentRepository(
        transport,
      ).submit(qrCode: 'CLIENT-CODE', payTime: DateTime.utc(2026, 8, 31));

      expect(result, isA<ScanPasswordRequired>());
      expect((result as ScanPasswordRequired).serverQrCode, 'SERVER-ORIGINAL');
    },
  );

  test('password retry resubmits the challenge string byte-for-byte', () async {
    // Synthetic code with escapes that must survive the password retry.
    const challengeQr = '.s:p010_SYNTHETIC%2B%2F%3D%3D';
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/scan/scanningResult', {
        'success': true,
        'url': '/pages/common/paysuccess/paysuccess',
        'message': '支付成功',
        'txamt': 880,
      });

    final result = await EcardScanPaymentRepository(transport).submit(
      qrCode: challengeQr,
      payTime: DateTime.utc(2026, 9, 2),
      password: '111222',
    );

    expect(result, isA<ScanSucceeded>());
    expect(transport.requests.single.data['qrcode'], challengeQr);
    expect(transport.requests.single.data['password'], '111222');
  });

  test(
    'maps payment amounts as fen and recognizes each success type',
    () async {
      final values = <String, ScanSuccessKind>{
        '': ScanSuccessKind.payment,
        'scj': ScanSuccessKind.attendance,
        'opendevice': ScanSuccessKind.openDevice,
        'bindTray': ScanSuccessKind.bindTray,
        'future-type': ScanSuccessKind.unknown,
      };
      for (final entry in values.entries) {
        final transport = FakeEcardTransport()
          ..enqueue('POST', '/scan/scanningResult', {
            'success': true,
            'issuccess': '1',
            'resultData': {'type': entry.key},
            'txamt': 1234,
            'managefee': 5,
            'balance': 9000,
          });
        final result = await EcardScanPaymentRepository(
          transport,
        ).submit(qrCode: 'QR', payTime: DateTime.utc(2026, 8, 31));

        expect(result, isA<ScanSucceeded>());
        final success = result as ScanSucceeded;
        expect(success.kind, entry.value);
        expect(success.amount, const MoneyFen(1234));
        expect(success.fee, const MoneyFen(5));
        expect(success.balance, const MoneyFen(9000));
      }
    },
  );
}
