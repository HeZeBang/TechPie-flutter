import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/genai/app/genai_runtime.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
      'wiring stays lazy and follows campus binding rather than the primary student id',
      () async {
    final storage = StorageService(await SharedPreferences.getInstance());
    final logging = LoggingHttpClient(DebugLogger());
    final auth = AuthService(storage, logging, UniAuthService());
    await storage.saveSession(
      UserSession(
        userId: 'primary',
        userName: 'Fixture',
        schoolName: 'Fixture',
        studentId: 'unrelated-primary-id',
        createdAt: DateTime(2026),
      ),
    );
    await auth.loadSession();
    final bindings = ThirdPartyAuthService(storage, logging);
    await bindings.replaceAll([
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '20240001',
        token: 'cpdaily-token-must-not-be-used',
        boundAt: DateTime(2026),
      ),
    ]);
    final transport = ScriptedTransport((_) async => profileResponse());
    final store = MemorySessionStore();
    final runtime = GenAiRuntime(
      auth: auth,
      thirdPartyAuth: bindings,
      transport: transport,
      store: store,
    );
    addTearDown(runtime.dispose);
    expect(runtime.sessions.owner?.studentId, '20240001');
    expect(store.reads, 0);
    expect(transport.requests, isEmpty);
    await runtime.sessions.connect(const GenAiCredential(token: 'genai-token'));
    expect(transport.requests.single.headers['X-Access-Token'], 'genai-token');
    await bindings.unbind(ThirdPartyPlatform.cpdaily);
    expect(runtime.sessions.owner, isNull);
    expect(runtime.sessions.session, isNull);
    expect(runtime.chat.answer, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(store.records, isEmpty);
  });
}
