import '../domain/genai_failure.dart';
import '../domain/genai_session.dart';

/// Matches only the documented university-owned landing URL, never a token
/// reflected through an arbitrary host, subframe, fragment, or redirect query.
final class GenAiLoginPolicy {
  static final loginUri =
      Uri.https('genai.shanghaitech.edu.cn', '/htk/user/login');

  static bool allowsNavigation(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      const ['genai.shanghaitech.edu.cn', 'ids.shanghaitech.edu.cn']
          .contains(uri.host);

  static GenAiCredential? callback(Uri uri) {
    if (!allowsNavigation(uri) ||
        uri.host != 'genai.shanghaitech.edu.cn' ||
        (uri.path != '/' && uri.path.isNotEmpty) ||
        uri.hasFragment) {
      return null;
    }
    final tokens = uri.queryParametersAll['token'];
    if (tokens == null || tokens.length != 1 || !_validToken(tokens.single)) {
      return null;
    }
    return GenAiCredential(token: tokens.single);
  }

  static GenAiCredential importCredential(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      final credential = callback(uri);
      if (credential != null) return credential;
    } else if (_validToken(value)) {
      return GenAiCredential(token: value);
    }
    throw const GenAiFailure(GenAiFailureKind.authenticationRequired);
  }

  static bool _validToken(String token) =>
      token.isNotEmpty &&
      token.length <= 8192 &&
      RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(token);
}
