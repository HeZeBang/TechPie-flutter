import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/api/qr_payload_codec.dart';

void main() {
  test('keeps ordinary online payloads as text', () {
    expect(QrPayloadCodec.online('ordinary-code'), 'ordinary-code');
  });

  test('converts 5638 online payload bytes through Latin-1 one-to-one', () {
    final payload = QrPayloadCodec.online('5638FF00');
    expect(latin1.encode(payload), [0x56, 0x38, 0xff, 0x00]);
  });

  test('always converts offline hex payloads', () {
    expect(latin1.encode(QrPayloadCodec.offline('00A1FF')), [0x00, 0xa1, 0xff]);
  });

  test('rejects incomplete or non-hex payloads', () {
    expect(() => QrPayloadCodec.offline('ABC'), throwsFormatException);
    expect(() => QrPayloadCodec.offline('GG'), throwsFormatException);
  });
}
