import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption helpers for the cloud-sync feature.
///
/// The sync blob stored in Casdoor `User.properties["techpie_sync"]` holds the
/// user's third-party account bindings (eGate CASTGC session, Gradescope/Hydro
/// tokens, and optionally their stored passwords). It MUST be unreadable to the
/// server. We use a user-chosen master password — the only secret that never
/// leaves the device — to derive an AES-256-GCM key via PBKDF2. The server
/// (Casdoor) only ever sees `base64(salt || nonce || ciphertext || authtag)`.
///
/// Blob layout (all raw bytes, then base64-encoded as a single string):
///   [0..16)   salt   — random per master-password setup, stored in blob
///   [16..28)  nonce  — random per encryption (12 bytes, AES-GCM)
///   [28..end) ciphertext + GCM auth tag (16 bytes trailing)
///
/// Decryption reads salt + nonce from the blob, but needs the master password
/// to re-derive the key. A wrong password (or tampered ciphertext) fails GCM
/// authentication — [decryptBlob] returns `null` instead of garbage.
class SyncCrypto {
  SyncCrypto._();

  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32; // AES-256
  static const int _pbkdf2Iterations = 200000;

  static final MacAlgorithm _mac = Hmac.sha256();
  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: _mac,
    iterations: _pbkdf2Iterations,
    bits: _keyLength * 8,
  );
  static final AesGcm _aes = AesGcm.with256bits();

  /// Derive a 256-bit key from [password] and [salt]. Deterministic: same
  /// password + salt → same key. The salt travels with the blob, the password
  /// lives only in the user's head / device keychain.
  static Future<SecretKey> deriveKey(
    String password,
    List<int> salt,
  ) async {
    final secret = SecretKey(utf8.encode(password));
    return _pbkdf2.deriveKey(secretKey: secret, nonce: salt);
  }

  /// Encrypt [plaintext] (a JSON string) with [key]. Produces a base64 string
  /// embedding a fresh random nonce. The caller stores salt separately (it is
  /// stable per master-password setup); only the nonce + ciphertext go here.
  static Future<String> encrypt(String plaintext, SecretKey key) async {
    final nonce = _aes.newNonce();
    final secretBox = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final combined = <int>[
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return base64.encode(combined);
  }

  /// Decrypt a blob produced by [encrypt] (base64, nonce-prefixed). Returns
  /// `null` if authentication fails (wrong key / tampered) so callers can
  /// surface "wrong master password" cleanly.
  static Future<String?> decrypt(String blob, SecretKey key) async {
    final List<int> raw;
    try {
      raw = base64.decode(blob);
    } catch (_) {
      return null;
    }
    if (raw.length < _nonceLength + 16) return null; // too short to be valid
    final nonce = raw.sublist(0, _nonceLength);
    final mac = Mac(raw.sublist(raw.length - 16));
    final cipherText = raw.sublist(_nonceLength, raw.length - 16);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    try {
      final plain = await _aes.decrypt(secretBox, secretKey: key);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Encrypt a full self-contained blob: salt + nonce + ciphertext + tag.
  /// Used for the *initial* upload (or master-password change), where the salt
  /// must travel alongside the ciphertext so other devices can derive the key.
  static Future<String> encryptWithSalt(
    String plaintext,
    String password,
  ) async {
    final salt = _randomBytes(_saltLength);
    final key = await deriveKey(password, salt);
    final inner = await encrypt(plaintext, key);
    // inner is base64(nonce+ciphertext+tag); prepend salt as base64 too and
    // join with a separator so decryptWithSalt can split cleanly.
    return '${base64.encode(salt)}.$inner';
  }

  /// Decrypt a self-contained blob (salt + nonce + ciphertext + tag) given the
  /// master password. Returns `null` on auth failure. Used for restore on a
  /// new device where no key is cached locally.
  static Future<String?> decryptWithSalt(
    String blob,
    String password,
  ) async {
    final dot = blob.indexOf('.');
    if (dot <= 0) return null;
    final List<int> salt;
    try {
      salt = base64.decode(blob.substring(0, dot));
    } catch (_) {
      return null;
    }
    final key = await deriveKey(password, salt);
    return decrypt(blob.substring(dot + 1), key);
  }

  /// Extract just the salt from a self-contained blob (without the password),
  /// so the UI can show "cloud has a backup" without needing to decrypt.
  static List<int>? extractSalt(String blob) {
    final dot = blob.indexOf('.');
    if (dot <= 0) return null;
    try {
      return base64.decode(blob.substring(0, dot));
    } catch (_) {
      return null;
    }
  }

  /// Encrypt [plaintext] with a key derived from [password] + the *existing*
  /// salt already embedded in [existingBlob]. Used when re-pushing on a device
  /// that has the master password but not the cached derived key: it reuses
  /// the same salt so other devices' cached keys still work.
  static Future<String> encryptWithExistingSalt(
    String plaintext,
    String password,
    String existingBlob,
  ) async {
    final salt = extractSalt(existingBlob);
    if (salt == null) {
      // No usable existing salt — fall back to a fresh self-contained blob.
      return encryptWithSalt(plaintext, password);
    }
    final key = await deriveKey(password, salt);
    final inner = await encrypt(plaintext, key);
    return '${base64.encode(salt)}.$inner';
  }

  static List<int> _randomBytes(int length) {
    // crypto-secure RNG. dart:math.Random.secure() reads from the platform's
    // CSPRNG on every supported target (Android/iOS/Linux/macOS/OHOS).
    final rnd = Random.secure();
    return List<int>.generate(length, (_) => rnd.nextInt(256));
  }
}

/// A self-contained set of secrets a device caches in secure storage so it
/// does not need to prompt for the master password on every sync operation:
/// the derived [key] and the [salt] it was derived with (so re-pushes keep
/// the same salt and stay decryptable by other devices).
class CachedSyncKey {
  final List<int> salt;
  final SecretKey key;

  CachedSyncKey(this.salt, this.key);

  /// Serialize for secure-storage caching. The key bytes are extracted via
  /// [SecretKey.extractBytes]; this is the only place raw key material is
  /// materialized, and it lives in the device keychain — never uploaded.
  Future<String> toStorageString() async {
    final keyBytes = await key.extractBytes();
    return '${base64.encode(salt)}:${base64.encode(keyBytes)}';
  }

  static Future<CachedSyncKey?> fromStorageString(String? s) async {
    if (s == null || s.isEmpty) return null;
    final colon = s.indexOf(':');
    if (colon <= 0) return null;
    try {
      final salt = base64.decode(s.substring(0, colon));
      final keyBytes = base64.decode(s.substring(colon + 1));
      return CachedSyncKey(salt, SecretKey(keyBytes));
    } catch (_) {
      return null;
    }
  }
}
