import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/crypto/sm2_offline_crypto.dart';

void main() {
  group('Sm2OfflineCrypto', () {
    test('builds the independently checked five-byte time CRC', () {
      expect(
        Sm2OfflineCrypto.buildTimeCrc(
          deviceCode: 'DEMO-DEVICE-0001',
          now: DateTime.utc(2026, 8, 31, 12),
        ),
        '6A956CC09D',
      );
    });

    test('generates compressed keys and verifies raw r||s signatures', () {
      final crypto = Sm2OfflineCrypto(random: Random(20260831));
      final keyPair = crypto.generateKeyPair();
      final message = [0x56, 0x38, 0xa1, 0xb2, 0x00, 0xff];
      final signature = crypto.sign(
        privateKeyHex: keyPair.privateKeyHex,
        message: message,
      );

      expect(keyPair.privateKeyHex, matches(RegExp(r'^[0-9A-F]{64}$')));
      expect(
        keyPair.publicKeyCompressed,
        matches(RegExp(r'^0[23][0-9A-F]{64}$')),
      );
      expect(signature, matches(RegExp(r'^[0-9A-F]{128}$')));
      expect(
        crypto.verify(
          publicKeyXHex: keyPair.publicKeyXHex,
          publicKeyYHex: keyPair.publicKeyYHex,
          message: message,
          signatureHex: signature,
        ),
        isTrue,
      );
      expect(
        crypto.verify(
          publicKeyXHex: keyPair.publicKeyXHex,
          publicKeyYHex: keyPair.publicKeyYHex,
          message: [...message, 1],
          signatureHex: signature,
        ),
        isFalse,
      );
    });

    test('assembles author info, time CRC, and 64-byte raw signature', () {
      final crypto = Sm2OfflineCrypto(random: Random(7));
      final keyPair = crypto.generateKeyPair();
      const authorInfo = '5638A1B2C3D4';
      final value = crypto.buildOfflineQrHex(
        authorInfo: authorInfo,
        deviceCode: 'DEMO-DEVICE-0001',
        privateKeyHex: keyPair.privateKeyHex,
        now: DateTime.utc(2026, 8, 31, 12),
      );
      expect(value, startsWith('${authorInfo}6A956CC09D'));
      expect(value.length, authorInfo.length + 10 + 128);
    });
  });
}
