import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/services/uni_auth_service.dart';

void main() {
  group('extractUniAuthCallbackCode', () {
    test('extracts the code from the full custom-scheme callback URL', () {
      expect(
        extractUniAuthCallbackCode(
          'techpie://auth-callback?code=authorization-code&state=state-token',
        ),
        'authorization-code',
      );
    });

    test('decodes an encoded authorization code', () {
      expect(
        extractUniAuthCallbackCode(
          'techpie://auth-callback?code=a%2Fb%2Bc%3D&state=state-token',
        ),
        'a/b+c=',
      );
    });

    test('returns empty when the callback has no code', () {
      expect(
        extractUniAuthCallbackCode(
          'techpie://auth-callback?error=access_denied',
        ),
        isEmpty,
      );
      expect(extractUniAuthCallbackCode(''), isEmpty);
    });
  });
}
