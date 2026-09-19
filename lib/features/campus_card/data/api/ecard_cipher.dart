import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

typedef EcardKeyGenerator = String Function();

final class EcardCipher {
  EcardCipher({EcardKeyGenerator? keyGenerator})
      : _keyGenerator = keyGenerator ?? secureKey;

  static const _charset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  final EcardKeyGenerator _keyGenerator;

  static String secureKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => _charset[random.nextInt(_charset.length)],
      growable: false,
    ).join();
  }

  static String encodeHeader(String key) {
    _requireAsciiKey(key);
    final rotated = key.substring(10) + key.substring(0, 10);
    return String.fromCharCodes(rotated.codeUnits.reversed);
  }

  static String decodeHeader(String header) {
    _requireAsciiKey(header);
    final reversed = String.fromCharCodes(header.codeUnits.reversed);
    return reversed.substring(6) + reversed.substring(0, 6);
  }

  String encodeRequest(Map<String, Object?> payload) =>
      encodeWithKey(payload, _keyGenerator());

  static String encodeWithKey(Object? payload, String key) {
    _requireAsciiKey(key);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final encrypted = _aesEcb(
      plain,
      Uint8List.fromList(ascii.encode(key)),
      true,
    );
    return encodeHeader(key) + base64Encode(encrypted);
  }

  static Object? decodeResponse(Object? body) {
    final normalized = _decodeJsonBody(body);
    if (normalized is! Map || !normalized.containsKey('datajson')) {
      return normalized;
    }
    final raw = normalized['datajson'];
    if (raw is! String) {
      throw const FormatException('Response datajson must be a string');
    }
    return decodeEnvelope(raw);
  }

  static Object? _decodeJsonBody(Object? body) {
    if (body is! String) return body;
    final candidate = body.trim();
    if (!(candidate.startsWith('{') || candidate.startsWith('['))) return body;
    try {
      return jsonDecode(candidate);
    } on FormatException {
      return body;
    }
  }

  static Object? decodeEnvelope(String raw) {
    if (raw.length <= 16) {
      throw const FormatException('Encrypted response is too short');
    }
    final key = decodeHeader(raw.substring(0, 16));
    late Uint8List encrypted;
    try {
      encrypted = base64Decode(raw.substring(16));
    } on FormatException {
      throw const FormatException('Encrypted response contains invalid base64');
    }
    final plain = _aesEcb(
      encrypted,
      Uint8List.fromList(ascii.encode(key)),
      false,
    );
    late String text;
    try {
      text = utf8.decode(plain);
    } on FormatException {
      throw const FormatException('Encrypted response is not valid UTF-8');
    }
    final candidate = text.trim();
    if (candidate.startsWith('{') || candidate.startsWith('[')) {
      try {
        return jsonDecode(candidate);
      } on FormatException {
        throw const FormatException('Encrypted response contains invalid JSON');
      }
    }
    if (candidate.startsWith('"')) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is String) {
          final nested = decoded.trim();
          if (nested.startsWith('{') || nested.startsWith('[')) {
            return jsonDecode(nested);
          }
          return decoded;
        }
      } on FormatException {
        // Non-JSON plaintext remains a valid documented response shape.
      }
    }
    return text;
  }

  static Uint8List _aesEcb(Uint8List data, Uint8List key, bool encrypt) {
    if (key.length != 16) {
      throw const FormatException('AES key must be 16 bytes');
    }
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))
          ..init(
            encrypt,
            PaddedBlockCipherParameters<KeyParameter, Null>(
              KeyParameter(key),
              null,
            ),
          );
    try {
      return cipher.process(data);
    } on ArgumentError {
      throw const FormatException('Encrypted response failed AES validation');
    } on InvalidCipherTextException {
      throw const FormatException(
        'Encrypted response failed padding validation',
      );
    }
  }

  static void _requireAsciiKey(String key) {
    if (key.length != 16 || !RegExp(r'^[A-Za-z0-9]{16}$').hasMatch(key)) {
      throw const FormatException(
        'Ecard key header must be 16 alphanumeric ASCII characters',
      );
    }
  }
}
