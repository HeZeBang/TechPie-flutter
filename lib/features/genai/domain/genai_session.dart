import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'genai_cancellation.dart';
import 'genai_contract.dart';

final class GenAiOwner {
  const GenAiOwner({
    required this.primaryUserId,
    required this.studentId,
    required this.bindingId,
  });

  final String primaryUserId;
  final String studentId;
  final String bindingId;

  String get storageId => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            primaryUserId,
            studentId,
            bindingId,
          ]),
        ),
      )
      .toString();

  @override
  bool operator ==(Object other) =>
      other is GenAiOwner &&
      other.primaryUserId == primaryUserId &&
      other.studentId == studentId &&
      other.bindingId == bindingId;

  @override
  int get hashCode => Object.hash(primaryUserId, studentId, bindingId);
}

final class GenAiCredential {
  const GenAiCredential({required this.token, this.expiresAt});

  final String token;
  final DateTime? expiresAt;

  @override
  String toString() => 'GenAiCredential(redacted)';
}

final class GenAiSession {
  const GenAiSession({
    required this.owner,
    required this.credential,
    required this.profile,
  });

  final GenAiOwner owner;
  final GenAiCredential credential;
  final GenAiProfile profile;

  bool isExpired(DateTime now) =>
      credential.expiresAt != null && !credential.expiresAt!.isAfter(now);

  @override
  String toString() => 'GenAiSession(redacted)';
}

abstract interface class GenAiSessionStore {
  Future<GenAiSession?> read(GenAiOwner owner);
  Future<void> write(GenAiSession session);
  Future<void> delete(GenAiOwner owner);
}

/// A future verified CAS/gateway exchange can implement this port. It receives
/// an identity scope, never a GeekPie/CpDaily token masquerading as a GenAI JWT.
abstract interface class GenAiSessionIssuer {
  Future<GenAiCredential> issue(
    GenAiOwner owner,
    GenAiCancellation cancellation,
  );
}
