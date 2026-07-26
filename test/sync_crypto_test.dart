import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/sync_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncCrypto roundtrip', () {
    test('encryptWithSalt -> decryptWithSalt recovers plaintext', () async {
      const password = 'correct horse battery staple';
      const payload =
          '[{"platform":"cpdaily","account":"13800000000","token":"tgc-secret"}]';

      final blob = await SyncCrypto.encryptWithSalt(payload, password);
      expect(blob.contains('.'), isTrue);

      final recovered = await SyncCrypto.decryptWithSalt(blob, password);
      expect(recovered, payload);
    });
    test('ThirdPartyPlatform.fromId resolves legacy egate alias to cpdaily',
        () {
      expect(ThirdPartyPlatform.fromId('egate'), ThirdPartyPlatform.cpdaily);
      expect(ThirdPartyPlatform.fromId('cpdaily'), ThirdPartyPlatform.cpdaily);
    });

    test('wrong master password fails authentication (returns null)',
        () async {
      const payload = 'secret bindings';
      final blob = await SyncCrypto.encryptWithSalt(payload, 'right-password');

      final recovered = await SyncCrypto.decryptWithSalt(blob, 'wrong-password');
      expect(recovered, isNull);
    });

    test('tampered ciphertext fails authentication', () async {
      final blob = await SyncCrypto.encryptWithSalt('hello', 'pw');
      // Flip one character in the base64 payload after the salt separator.
      final dot = blob.indexOf('.');
      final tampered =
          blob.substring(0, dot + 1) + _flipLastChar(blob.substring(dot + 1));
      final recovered = await SyncCrypto.decryptWithSalt(tampered, 'pw');
      expect(recovered, isNull);
    });

    test('different passwords produce different blobs (different salts)',
        () async {
      final a = await SyncCrypto.encryptWithSalt('payload', 'pwA');
      final b = await SyncCrypto.encryptWithSalt('payload', 'pwB');
      expect(a, isNot(b));
      // Salts differ
      expect(
        SyncCrypto.extractSalt(a),
        isNot(SyncCrypto.extractSalt(b)),
      );
    });

    test('re-push reuses existing salt so other devices still decrypt',
        () async {
      const password = 'shared-pw';
      const first = '{"v":1}';
      const second = '{"v":2,"more":"data"}';

      final blob1 = await SyncCrypto.encryptWithSalt(first, password);
      // A device with the password but not the cached key re-pushes new
      // payload reusing blob1's salt:
      final blob2 = await SyncCrypto.encryptWithExistingSalt(
        second,
        password,
        blob1,
      );
      expect(SyncCrypto.extractSalt(blob1), SyncCrypto.extractSalt(blob2));
      // Both decrypt with the same password
      expect(await SyncCrypto.decryptWithSalt(blob2, password), second);
    });

    test('CachedSyncKey persists and restores the derived key', () async {
      const password = 'pw';
      const saltBase64 = '0123456789abcdef';
      final salt = saltBase64.codeUnits;
      final key = await SyncCrypto.deriveKey(password, salt);
      final cached = CachedSyncKey(salt, key);

      final stored = await cached.toStorageString();
      final restored = await CachedSyncKey.fromStorageString(stored);

      expect(restored, isNotNull);
      expect(restored!.salt, salt);
      // Key material matches
      expect(await restored.key.extractBytes(), await key.extractBytes());
    });
  });
}

/// Flip the last base64 character to a different one (guaranteed change).
String _flipLastChar(String s) {
  if (s.isEmpty) return 'A';
  final last = s[s.length - 1];
  final next = last == 'A' ? 'B' : 'A';
  return s.substring(0, s.length - 1) + next;
}
