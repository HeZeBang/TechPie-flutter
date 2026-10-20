import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';

import '../../../utils/secure_storage.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';

/// A separate local-only namespace, outside third-party binding/cloud sync.
final class SecureGenAiSessionStore implements GenAiSessionStore {
  SecureGenAiSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? appSecureStorage;

  final FlutterSecureStorage _storage;
  Future<void> _tail = Future.value();

  String _key(GenAiOwner owner) =>
      'techpie.genai.session.v1.${owner.storageId}';

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      try {
        return await operation();
      } catch (_) {
        throw const GenAiFailure(GenAiFailureKind.storage);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<GenAiSession?> read(GenAiOwner owner) => _serialize(() async {
        final raw = await _storage.read(key: _key(owner));
        if (raw == null) return null;
        try {
          final json = genAiObject(jsonDecode(raw));
          if (json['version'] != 1 || json['owner'] != owner.storageId) {
            throw const FormatException();
          }
          final expiry = json['expiresAt'];
          final expiresAt =
              expiry == null ? null : DateTime.parse(expiry as String);
          return GenAiSession(
            owner: owner,
            credential: GenAiCredential(
              token: genAiRequiredString(json, 'token'),
              expiresAt: expiresAt,
            ),
            profile: GenAiProfile(
              id: genAiRequiredString(json, 'userId'),
              username: genAiRequiredString(json, 'username'),
            ),
          );
        } catch (_) {
          // Corrupt or incompatible records cannot become authenticated state.
          await _storage.delete(key: _key(owner));
          return null;
        }
      });

  @override
  Future<void> write(GenAiSession session) => _serialize(
        () => _storage.write(
          key: _key(session.owner),
          value: jsonEncode({
            'version': 1,
            'owner': session.owner.storageId,
            'token': session.credential.token,
            'expiresAt':
                session.credential.expiresAt?.toUtc().toIso8601String(),
            'userId': session.profile.id,
            'username': session.profile.username,
          }),
        ),
      );

  @override
  Future<void> delete(GenAiOwner owner) =>
      _serialize(() => _storage.delete(key: _key(owner)));
}
