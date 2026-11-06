import '../../../services/session/cookie_provider.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';

final class NativeGenAiIdsExchange {
  Future<GenAiCredential> exchange(
    CookieProvider provider,
    GenAiCancellation cancellation,
  ) async =>
      throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
}
