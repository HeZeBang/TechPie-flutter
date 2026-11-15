import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/services/ids/software_passkey.dart';

void main() {
  test('registration COSE key verifies DER assertions, with zero counter on every use', () {
    final challenge = SoftwarePasskey.encode(List.generate(32, (i) => i));
    final registered = SoftwarePasskey.registration(
      {
        'challenge': challenge,
        'rp': {'id': IdsPasskey.rpId},
        'user': {'id': 'dXNlcg', 'name': 'student'},
        'pubKeyCredParams': [
          {'alg': -7},
        ],
      },
      'student',
    );
    final response = registered.credential['response'] as Map;
    final attestation = cbor
        .decode(SoftwarePasskey.decode(response['attestationObject'] as String))
        .toObject() as Map;
    final auth = attestation['authData'] as List<int>;
    expect(attestation['fmt'], 'none');
    expect(auth.take(32), sha256.convert(utf8.encode(IdsPasskey.rpId)).bytes);
    expect(auth[32], 0x49);
    expect(auth.sublist(33, 37), [0, 0, 0, 0]);
    final length = auth[53] * 256 + auth[54];
    expect(SoftwarePasskey.encode(auth.sublist(55, 55 + length)), registered.secret.credentialId);
    final public = cbor.decode(auth.sublist(55 + length)).toObject() as Map;
    final curve = ECDomainParameters('prime256v1');
    final point = curve.curve.decodePoint(
      Uint8List.fromList([4, ...(public[-2] as List<int>), ...(public[-3] as List<int>)]),
    );
    final key = ECPublicKey(point, curve);
    final restored = IdsPasskey.fromJson(
      jsonDecode(jsonEncode(registered.secret.toJson())) as Map<String, dynamic>,
    );
    for (var i = 0; i < 2; i++) {
      final assertion = SoftwarePasskey.authentication(
        {'challenge': '$challenge$i', 'rpId': IdsPasskey.rpId},
        restored,
        backedUp: i == 1,
      );
      final data = assertion['response'] as Map;
      final authenticator = SoftwarePasskey.decode(data['authenticatorData'] as String);
      final client = SoftwarePasskey.decode(data['clientDataJSON'] as String);
      expect(authenticator[32], i == 1 ? 0x19 : 0x09);
      expect(authenticator.sublist(33), [0, 0, 0, 0]);
      expect((jsonDecode(utf8.decode(client)) as Map)['challenge'], '$challenge$i');
      final der = ASN1Parser(SoftwarePasskey.decode(data['signature'] as String)).nextObject()
          as ASN1Sequence;
      final signature = ECSignature(
        (der.elements![0] as ASN1Integer).integer!,
        (der.elements![1] as ASN1Integer).integer!,
      );
      final verifier = Signer('SHA-256/ECDSA')..init(false, PublicKeyParameter(key));
      expect(
        verifier.verifySignature(
          Uint8List.fromList([...authenticator, ...sha256.convert(client).bytes]),
          signature,
        ),
        isTrue,
      );
    }
  });
}
