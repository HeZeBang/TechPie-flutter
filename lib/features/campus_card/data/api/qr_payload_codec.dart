import 'dart:convert';

final class QrPayloadCodec {
  const QrPayloadCodec._();

  static String online(String raw) {
    if (!raw.startsWith('5638')) return raw;
    return hexToLatin1(raw);
  }

  static String offline(String hex) => hexToLatin1(hex);

  static String hexToLatin1(String hex) {
    if (hex.length.isOdd || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(hex)) {
      throw const FormatException('QR hex payload must contain complete bytes');
    }
    final bytes = <int>[
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ];
    return latin1.decode(bytes);
  }
}
