import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final class Sm2KeyPair {
  const Sm2KeyPair({
    required this.privateKeyHex,
    required this.publicKeyCompressed,
    required this.publicKeyXHex,
    required this.publicKeyYHex,
  });

  final String privateKeyHex;
  final String publicKeyCompressed;
  final String publicKeyXHex;
  final String publicKeyYHex;
}

final class Sm2OfflineCrypto {
  Sm2OfflineCrypto({Random? random}) : _random = random ?? Random.secure();

  static final BigInt p = BigInt.parse(
    'FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF',
    radix: 16,
  );
  static final BigInt a = BigInt.parse(
    'FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC',
    radix: 16,
  );
  static final BigInt b = BigInt.parse(
    '28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93',
    radix: 16,
  );
  static final BigInt n = BigInt.parse(
    'FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123',
    radix: 16,
  );
  static final BigInt gx = BigInt.parse(
    '32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7',
    radix: 16,
  );
  static final BigInt gy = BigInt.parse(
    'BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0',
    radix: 16,
  );
  static const defaultUserId = '1234567812345678';

  static final _generator = _EcPoint(gx, gy);

  final Random _random;

  Sm2KeyPair generateKeyPair() {
    // d = n - 1 would make (1 + d)^-1 undefined during SM2 signing.
    final privateKey = _randomScalar(maxExclusive: n - BigInt.one);
    final publicKey = _multiply(privateKey, _generator);
    if (publicKey.isInfinity) throw StateError('Invalid SM2 public key');
    final x = _hex(publicKey.x!);
    final y = _hex(publicKey.y!);
    return Sm2KeyPair(
      privateKeyHex: _hex(privateKey).toUpperCase(),
      publicKeyCompressed:
          '${publicKey.y!.isOdd ? '03' : '02'}$x'.toUpperCase(),
      publicKeyXHex: x.toUpperCase(),
      publicKeyYHex: y.toUpperCase(),
    );
  }

  String sign({
    required String privateKeyHex,
    required List<int> message,
    String userId = defaultUserId,
  }) {
    final privateKey = _parsePrivateKey(privateKeyHex);
    final publicKey = _multiply(privateKey, _generator);
    final e = _digestForSignature(publicKey, message, userId);
    while (true) {
      final k = _randomScalar(maxExclusive: n);
      final point = _multiply(k, _generator);
      final r = _mod(e + point.x!, n);
      if (r == BigInt.zero || r + k == n) continue;
      final inverse = (BigInt.one + privateKey).modInverse(n);
      final s = _mod((k - r * privateKey) * inverse, n);
      if (s == BigInt.zero) continue;
      return '${_hex(r)}${_hex(s)}'.toUpperCase();
    }
  }

  bool verify({
    required String publicKeyXHex,
    required String publicKeyYHex,
    required List<int> message,
    required String signatureHex,
    String userId = defaultUserId,
  }) {
    if (!RegExp(r'^[0-9A-Fa-f]{128}$').hasMatch(signatureHex)) return false;
    final publicKey = _EcPoint(
      BigInt.parse(publicKeyXHex, radix: 16),
      BigInt.parse(publicKeyYHex, radix: 16),
    );
    if (!_isOnCurve(publicKey)) return false;
    final r = BigInt.parse(signatureHex.substring(0, 64), radix: 16);
    final s = BigInt.parse(signatureHex.substring(64), radix: 16);
    if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return false;
    final t = _mod(r + s, n);
    if (t == BigInt.zero) return false;
    final point = _add(_multiply(s, _generator), _multiply(t, publicKey));
    if (point.isInfinity) return false;
    final e = _digestForSignature(publicKey, message, userId);
    return _mod(e + point.x!, n) == r;
  }

  static String buildTimeCrc({
    required String deviceCode,
    required DateTime now,
  }) {
    final checksum = deviceChecksum(deviceCode);
    final seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (seconds < 0 || seconds > 0xffffffff) {
      throw RangeError.range(seconds, 0, 0xffffffff, 'Unix seconds');
    }
    final bytes = <int>[
      (seconds >> 24) & 0xff,
      (seconds >> 16) & 0xff,
      (seconds >> 8) & 0xff,
      seconds & 0xff,
    ];
    bytes.add(bytes.fold<int>(checksum, (value, byte) => value ^ byte));
    return _hexBytes(bytes).toUpperCase();
  }

  /// The offline protocol uses only this checksum, not the raw login identifier.
  static int deviceChecksum(String deviceCode) =>
      _sm3(utf8.encode(deviceCode)).fold<int>(0, (sum, byte) => sum ^ byte);

  String buildOfflineQrHex({
    required String authorInfo,
    required String deviceCode,
    required String privateKeyHex,
    required DateTime now,
  }) {
    if (authorInfo.isEmpty ||
        authorInfo.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(authorInfo)) {
      throw const FormatException(
        'authorInfo must be a non-empty complete hex string',
      );
    }
    final messageHex =
        '${authorInfo.toUpperCase()}${buildTimeCrc(deviceCode: deviceCode, now: now)}';
    final message = _hexDecode(messageHex);
    return '$messageHex${sign(privateKeyHex: privateKeyHex, message: message)}';
  }

  BigInt _randomScalar({required BigInt maxExclusive}) {
    if (maxExclusive <= BigInt.one) throw ArgumentError.value(maxExclusive);
    while (true) {
      final bytes = List<int>.generate(
        32,
        (_) => _random.nextInt(256),
        growable: false,
      );
      final candidate = BigInt.parse(_hexBytes(bytes), radix: 16);
      if (candidate >= BigInt.one && candidate < maxExclusive) return candidate;
    }
  }

  static BigInt _parsePrivateKey(String value) {
    if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(value)) {
      throw const FormatException('SM2 private key must be 32-byte hex');
    }
    final parsed = BigInt.parse(value, radix: 16);
    if (parsed <= BigInt.zero || parsed >= n - BigInt.one) {
      throw const FormatException(
        'SM2 private key is outside the signing range',
      );
    }
    return parsed;
  }

  static BigInt _digestForSignature(
    _EcPoint publicKey,
    List<int> message,
    String userId,
  ) {
    final userIdBytes = utf8.encode(userId);
    final bitLength = userIdBytes.length * 8;
    if (bitLength > 0xffff) {
      throw const FormatException('SM2 user ID is too long');
    }
    final za = _sm3([
      (bitLength >> 8) & 0xff,
      bitLength & 0xff,
      ...userIdBytes,
      ..._bigIntBytes(a),
      ..._bigIntBytes(b),
      ..._bigIntBytes(gx),
      ..._bigIntBytes(gy),
      ..._bigIntBytes(publicKey.x!),
      ..._bigIntBytes(publicKey.y!),
    ]);
    return BigInt.parse(_hexBytes(_sm3([...za, ...message])), radix: 16);
  }

  static _EcPoint _multiply(BigInt scalar, _EcPoint point) {
    if (scalar == BigInt.zero || point.isInfinity) {
      return const _EcPoint.infinity();
    }
    var result = const _EcPoint.infinity();
    var addend = point;
    var value = scalar;
    while (value > BigInt.zero) {
      if (value.isOdd) result = _add(result, addend);
      addend = _add(addend, addend);
      value >>= 1;
    }
    return result;
  }

  static _EcPoint _add(_EcPoint first, _EcPoint second) {
    if (first.isInfinity) return second;
    if (second.isInfinity) return first;
    final x1 = first.x!;
    final y1 = first.y!;
    final x2 = second.x!;
    final y2 = second.y!;
    if (x1 == x2) {
      if (_mod(y1 + y2, p) == BigInt.zero || y1 == BigInt.zero) {
        return const _EcPoint.infinity();
      }
      final slope = _mod(
        (BigInt.from(3) * x1 * x1 + a) * (BigInt.two * y1).modInverse(p),
        p,
      );
      final x3 = _mod(slope * slope - BigInt.two * x1, p);
      final y3 = _mod(slope * (x1 - x3) - y1, p);
      return _EcPoint(x3, y3);
    }
    final slope = _mod((y2 - y1) * _mod(x2 - x1, p).modInverse(p), p);
    final x3 = _mod(slope * slope - x1 - x2, p);
    final y3 = _mod(slope * (x1 - x3) - y1, p);
    return _EcPoint(x3, y3);
  }

  static bool _isOnCurve(_EcPoint point) {
    if (point.isInfinity) return false;
    return _mod(point.y! * point.y!, p) ==
        _mod(point.x! * point.x! * point.x! + a * point.x! + b, p);
  }

  static BigInt _mod(BigInt value, BigInt modulus) {
    final result = value % modulus;
    return result.sign < 0 ? result + modulus : result;
  }

  static Uint8List _sm3(List<int> data) {
    final input = Uint8List.fromList(data);
    final digest = SM3Digest()..update(input, 0, input.length);
    final output = Uint8List(digest.digestSize);
    digest.doFinal(output, 0);
    return output;
  }

  static List<int> _bigIntBytes(BigInt value) => _hexDecode(_hex(value));

  static String _hex(BigInt value) => value.toRadixString(16).padLeft(64, '0');

  static String _hexBytes(Iterable<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hexDecode(String hex) => [
        for (var index = 0; index < hex.length; index += 2)
          int.parse(hex.substring(index, index + 2), radix: 16),
      ];
}

final class _EcPoint {
  const _EcPoint(this.x, this.y);
  const _EcPoint.infinity()
      : x = null,
        y = null;

  final BigInt? x;
  final BigInt? y;

  bool get isInfinity => x == null || y == null;
}
