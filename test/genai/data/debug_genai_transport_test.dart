import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/debug_genai_transport.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

import '../support/fakes.dart';

void main() {
  test('synthetic credentials never reach the real transport', () async {
    final live = ScriptedTransport((_) async => profileResponse());
    final transport = DebugGenAiTransport(live: live, proxyOrigin: '');
    addTearDown(transport.dispose);
    final response = await transport.send(
      method: 'GET',
      uri: Uri.parse(
        'https://genai.shanghaitech.edu.cn/htk/user/info/${DemoGenAiBackend.token}',
      ),
      cancellation: GenAiCancellation(),
      headers: {'X-Access-Token': DemoGenAiBackend.token},
    );
    await response.bytes.drain<void>();
    response.close();
    expect(live.requests, isEmpty);
  });

  test(
      'a real credential uses the production adapter through only a local proxy',
      () async {
    final live = ScriptedTransport((_) async => profileResponse());
    final transport =
        DebugGenAiTransport(live: live, proxyOrigin: 'http://127.0.0.1:18768');
    addTearDown(transport.dispose);
    final response = await transport.send(
      method: 'GET',
      uri: Uri.parse(
        'https://genai.shanghaitech.edu.cn/htk/user/info/real-token?_t=1',
      ),
      cancellation: GenAiCancellation(),
      headers: {'X-Access-Token': 'real-token'},
    );
    expect(
      live.requests.single.uri.toString(),
      'http://127.0.0.1:18768/htk/user/info/real-token?_t=1',
    );
    expect(live.requests.single.headers['X-Access-Token'], 'real-token');
    response.close();
  });

  test('preview refuses remote proxies and token-bearing proxy URLs', () {
    for (final origin in [
      'https://evil.example',
      'http://evil.example',
      'http://127.0.0.1:18768/?token=private',
      'http://user:password@127.0.0.1:18768',
    ]) {
      expect(
        () => DebugGenAiTransport(proxyOrigin: origin),
        throwsArgumentError,
      );
    }
  });
  test('real credentials cannot be sent to a foreign destination', () async {
    final live = ScriptedTransport((_) async => profileResponse());
    final transport = DebugGenAiTransport(live: live, proxyOrigin: '');
    addTearDown(transport.dispose);
    expect(
      () => transport.send(
        method: 'GET',
        uri: Uri.parse('https://evil.example/htk/user/info/real-token'),
        cancellation: GenAiCancellation(),
        headers: {'X-Access-Token': 'real-token'},
      ),
      throwsA(isA<GenAiFailure>()),
    );
    expect(live.requests, isEmpty);
  });
}
