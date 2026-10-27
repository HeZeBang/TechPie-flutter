import '../../../services/session/cookie_provider.dart';
import '../../../services/session/session_tree.dart';
import '../../../services/third_party_auth_service.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';

typedef GenAiCampusExchange = Future<GenAiCredential> Function(
  CookieProvider provider,
  GenAiCancellation cancellation,
);

/// Reuses the IDS parent and its existing scheduled/401 renewal budget.
/// SMS bindings may lack a school ID. The GenAI profile verifier must still
/// match every issued credential to the resolved owner before persistence.
final class CampusGenAiSessionIssuer implements GenAiSessionIssuer {
  CampusGenAiSessionIssuer({
    required this.thirdPartyAuth,
    required this.exchange,
  });
  final ThirdPartyAuthService thirdPartyAuth;
  final GenAiCampusExchange exchange;

  @override
  Future<GenAiCredential> issue(
    GenAiOwner owner,
    GenAiCancellation cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final initial = thirdPartyAuth.cpdailyNode.cookieProvider;
    if (initial == null ||
        !initial.cookies.split(';').any(
              (c) => c.trim().startsWith('CASTGC=') && c.trim() != 'CASTGC=',
            )) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    if (owner.studentId.isNotEmpty &&
        initial.studentId.isNotEmpty &&
        initial.studentId != owner.studentId) {
      throw const GenAiFailure(GenAiFailureKind.identityMismatch);
    }
    final credential = await cancellation.race(
      thirdPartyAuth.sessionTree.withCookie<GenAiCredential?>(
        thirdPartyAuth.cpdailyNode,
        (provider) async {
          cancellation.throwIfCancelled();
          // An SMS bootstrap starts without a school ID; renewal may discover
          // it. Runtime still verifies the GenAI profile against that binding
          // before connecting. A known owner must always match immediately.
          if (owner.studentId.isNotEmpty &&
              provider.studentId.isNotEmpty &&
              provider.studentId != owner.studentId) {
            throw const GenAiFailure(GenAiFailureKind.identityMismatch);
          }
          try {
            final value =
                await cancellation.race(exchange(provider, cancellation));
            return CookieAction<GenAiCredential?>(value, expired: false);
          } on GenAiFailure catch (error) {
            if (error.kind != GenAiFailureKind.authenticationRequired) rethrow;
            return const CookieAction<GenAiCredential?>(null, expired: true);
          }
        },
      ),
    );
    cancellation.throwIfCancelled();
    if (credential == null) {
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
    }
    return credential;
  }
}
