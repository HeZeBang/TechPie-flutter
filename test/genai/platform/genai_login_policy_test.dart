import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/genai_login_policy.dart';

import '../support/fakes.dart';

void main() {
  test('accepts only the documented university landing URL', () {
    expect(
      GenAiLoginPolicy.callback(
        Uri.parse(
          'https://genai.shanghaitech.edu.cn/?token=synthetic.jwt',
        ),
      )?.token,
      'synthetic.jwt',
    );
    expect(
      GenAiLoginPolicy.callback(
        Uri.parse(
          'https://genai.shanghaitech.edu.cn:443?token=synthetic.jwt',
        ),
      )?.token,
      'synthetic.jwt',
    );
    expect(
      GenAiLoginPolicy.allowsNavigation(
        Uri.parse('https://ids.shanghaitech.edu.cn/authserver/login'),
      ),
      isTrue,
    );
  });

  for (final url in [
    'http://genai.shanghaitech.edu.cn/?token=secret',
    'https://genai.shanghaitech.edu.cn:8443/?token=secret',
    'https://genai.shanghaitech.edu.cn.evil.example/?token=secret',
    'https://genai.shanghaitech.edu.cn@evil.example/?token=secret',
    'https://user@genai.shanghaitech.edu.cn/?token=secret',
    'https://ids.shanghaitech.edu.cn/?token=secret',
    'https://genai.shanghaitech.edu.cn/other?token=secret',
    'https://genai.shanghaitech.edu.cn/?token=one&token=two',
    'https://genai.shanghaitech.edu.cn/?token=one#fragment',
    'https://genai.shanghaitech.edu.cn/?redirect=https://evil.example/?token=secret',
    'https://genai.shanghaitech.edu.cn/?token=bad%0Atoken',
  ]) {
    test('rejects an untrusted callback: $url', () {
      expect(GenAiLoginPolicy.callback(Uri.parse(url)), isNull);
      expect(
        () => GenAiLoginPolicy.importCredential(url),
        throwsA(failure(GenAiFailureKind.authenticationRequired)),
      );
    });
  }

  test('manual import trims but never guesses a token embedded in text', () {
    expect(
      GenAiLoginPolicy.importCredential('  synthetic.jwt  ').token,
      'synthetic.jwt',
    );
    for (final input in [
      '',
      'Bearer synthetic.jwt',
      'copy this token: abc',
      'a' * 8193,
    ]) {
      expect(
        () => GenAiLoginPolicy.importCredential(input),
        throwsA(failure(GenAiFailureKind.authenticationRequired)),
      );
    }
  });
}
