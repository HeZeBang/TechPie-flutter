import 'dart:convert';

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:cryptography/cryptography.dart' hide Hmac;

/// The desktop path's key material, computed from what the controller hands out
/// in `authConfig.antiMITMAttackData`.
///
/// The controller issues an RSA public key (`devicePubKeyMod`/`devicePubKeyExp`)
/// and a per-login `challenge`; the client derives a signature key from them and
/// proves it can reproduce an encrypted challenge. That proof is the only reason
/// a session can be marked as a *desktop* one — and only a desktop session may be
/// bound as a trusted terminal, which is what stops the controller asking for an
/// SMS on every fresh login.
///
/// Ported from the protocol notes (geekTrust `docs/TECHNICAL.md` §10.1–10.2),
/// where both algorithms were checked against real login logs.
abstract final class AtrustCrypto {
  /// §10.1's salt.
  static const _signKeySalt =
      '3uW5IEy8KwDaOMK8uw1TmNr50U3aK1Qdu8b6vopXxGstzan3AJXxVNR6piuKi5Nq';

  /// §10.2's salt.
  static const _challengeSalt =
      'OrHWuJz7gku5awmVb5w1sKTmfeCWHmzokBxmn0sn0faIcv1G10PdrbbRGKBrrZ3m';

  /// `signKey = UPPER_HEX( h1 XOR SHA256( UPPER_HEX(h1) + challenge ) )`
  /// where `h1 = SHA256(devicePubKeyMod + devicePubKeyExp + salt)`.
  ///
  /// The challenge is used as the base64 text the controller sent — it is never
  /// decoded.
  static String signKey({
    required String devicePubKeyMod,
    required String devicePubKeyExp,
    required String challenge,
  }) {
    final modulus = '$devicePubKeyMod$devicePubKeyExp';
    final h1Hex = _hex(
      sha256.convert(utf8.encode('$modulus$_signKeySalt')).bytes,
    );
    final mix = sha256.convert(utf8.encode('$h1Hex$challenge')).bytes;
    final first = _bytes(h1Hex);
    return _hex(<int>[
      for (var i = 0; i < first.length; i++) first[i] ^ mix[i],
    ]);
  }

  /// §10.2 — AES-CBC-128 with PKCS#7 over the challenge text, keyed by the first
  /// and last 16 bytes of `SHA256(modulus + salt)`.
  ///
  /// This is the value the desktop `reportEnv` sends as its proof; the controller
  /// recomputes it from its own public key.
  static Future<String> encryptedChallenge({
    required String devicePubKeyMod,
    required String devicePubKeyExp,
    required String challenge,
  }) async {
    final modulus = '$devicePubKeyMod$devicePubKeyExp';
    final digest = sha256.convert(utf8.encode('$modulus$_challengeSalt')).bytes;
    final algorithm = AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);
    final box = await algorithm.encrypt(
      utf8.encode(challenge),
      secretKey: SecretKey(digest.sublist(0, 16)),
      nonce: digest.sublist(16, 32),
    );
    return _hex(box.cipherText);
  }

  /// §10.3 — the interface signature a *signed* trusted request needs:
  /// `UPPER_HEX( HMAC-SHA256( hex_decode(signKey), pathWithQuery + body ) )`.
  ///
  /// Nothing in this client uses it yet: the notes are explicit that both the
  /// login and the trusted-terminal calls work without it, and the resource
  /// fetch stays on the unsigned browser shape. It is here (and tested) so a
  /// request that does need it — the notes call out the desktop `clientResource`
  /// — can be signed without rediscovering the algorithm.
  static String requestSignature({
    required String signKey,
    required String pathWithQuery,
    required String body,
  }) {
    final mac = Hmac(sha256, _bytes(signKey));
    return _hex(mac.convert(utf8.encode('$pathWithQuery$body')).bytes);
  }

  static String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  static List<int> _bytes(String hex) => <int>[
        for (var i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
}
