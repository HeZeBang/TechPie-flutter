// IDS protocol port from auth-portal / shanghaitech-ids-passkey (MIT).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../../models/ids_passkey.dart';

class SoftwarePasskey {
  static const origin = 'https://ids.shanghaitech.edu.cn';

  // Real IDS logins on 2026-11-03 accepted signCount 7, 7, 3, 0, 0,
  // each with a fresh challenge, cookie jar and verified account session.
  // Use WebAuthn's "counter unsupported" value so synced software credentials
  // need no cross-device counter. Do not increment or sync this value.
  static const signCount = 0;

  static final _curve = ECDomainParameters('prime256v1');
  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  static String encode(List<int> value) => base64Url.encode(value).replaceAll('=', '');
  static Uint8List decode(String value) => base64Url.decode(base64Url.normalize(value));
  static BigInt _integer(List<int> bytes) =>
      BigInt.parse(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16);
  static Uint8List _bytes(BigInt value) {
    final hex = value.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList(
      List.generate(32, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)),
    );
  }

  static Uint8List _clientData(String type, String challenge) => Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'type': type,
            'challenge': challenge,
            'origin': origin,
            'crossOrigin': false,
          }),
        ),
      );

  static ({IdsPasskey secret, Map<String, dynamic> credential}) registration(
    Map<String, dynamic> options,
    String username,
  ) {
    if ((options['rp'] as Map)['id'] != IdsPasskey.rpId ||
        (options['user'] as Map)['name'] != username) {
      throw const FormatException('IDS registration identity mismatch');
    }
    if (!(options['pubKeyCredParams'] as List).any((p) => p['alg'] == -7) ||
        (options['authenticatorSelection'] as Map?)?['userVerification'] == 'required') {
      throw const FormatException('IDS requires unsupported user verification');
    }
    BigInt d;
    do {
      d = _integer(randomBytes(32));
    } while (d == BigInt.zero || d >= _curve.n);
    final point = _curve.G * d;
    String credentialId;
    do {
      credentialId = encode(randomBytes(32));
    } while ((options['excludeCredentials'] as List? ?? []).any((c) => c['id'] == credentialId));
    final secret = IdsPasskey(
      credentialId: credentialId,
      privateKey: encode(_bytes(d)),
      userHandle: (options['user'] as Map)['id'] as String,
      anonBiometricsId: randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      username: username,
    );
    final cose = cbor.encode(
      CborMap({
        const CborSmallInt(1): const CborSmallInt(2),
        const CborSmallInt(3): const CborSmallInt(-7),
        const CborSmallInt(-1): const CborSmallInt(1),
        const CborSmallInt(-2): CborBytes(_bytes(point!.x!.toBigInteger()!)),
        const CborSmallInt(-3): CborBytes(_bytes(point.y!.toBigInteger()!)),
      }),
    );
    final id = decode(credentialId);
    final authData = Uint8List.fromList([
      ...sha256.convert(utf8.encode(IdsPasskey.rpId)).bytes,
      0x49, // UP + BE + AT; this software credential is backup eligible.
      ...Uint8List(4), ...Uint8List(16), id.length >> 8, id.length & 255, ...id, ...cose,
    ]);
    final attestation = cbor.encode(
      CborMap({
        CborString('fmt'): CborString('none'),
        CborString('attStmt'): CborMap({}),
        CborString('authData'): CborBytes(authData),
      }),
    );
    return (
      secret: secret,
      credential: {
        'type': 'public-key',
        'id': credentialId,
        'response': {
          'attestationObject': encode(attestation),
          'clientDataJSON': encode(_clientData('webauthn.create', options['challenge'] as String)),
        },
        'clientExtensionResults': <String, dynamic>{},
      }
    );
  }

  static Map<String, dynamic> authentication(
    Map<String, dynamic> options,
    IdsPasskey secret, {
    bool backedUp = false,
  }) {
    if (options['rpId'] != IdsPasskey.rpId || options['userVerification'] == 'required') {
      throw const FormatException('Unsupported IDS assertion');
    }
    final allowed = options['allowCredentials'] as List?;
    if (allowed != null &&
        allowed.isNotEmpty &&
        !allowed.any((c) => c['id'] == secret.credentialId)) {
      throw const FormatException('IDS Passkey has been removed; bind again');
    }
    final counter = ByteData(4)..setUint32(0, signCount);
    final authData = Uint8List.fromList([
      ...sha256.convert(utf8.encode(IdsPasskey.rpId)).bytes,
      0x09 | (backedUp ? 0x10 : 0), // UP + BE, and actual backup state.
      ...counter.buffer.asUint8List(),
    ]);
    final data = _clientData('webauthn.get', options['challenge'] as String);
    final signer = Signer('SHA-256/DET-ECDSA')
      ..init(true, PrivateKeyParameter(ECPrivateKey(_integer(decode(secret.privateKey)), _curve)));
    final signature =
        signer.generateSignature(Uint8List.fromList([...authData, ...sha256.convert(data).bytes]))
            as ECSignature;
    final der =
        ASN1Sequence(elements: [ASN1Integer(signature.r), ASN1Integer(signature.s)]).encode();
    return {
      'type': 'public-key',
      'id': secret.credentialId,
      'response': {
        'authenticatorData': encode(authData),
        'clientDataJSON': encode(data),
        'signature': encode(der),
        'userHandle': secret.userHandle,
      },
      'clientExtensionResults': <String, dynamic>{},
    };
  }
}
