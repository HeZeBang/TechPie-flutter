import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/secure_genai_session_store.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
      'credentials round-trip only in the dedicated owner-scoped secure namespace',
      () async {
    final store = SecureGenAiSessionStore();
    final session = GenAiSession(
      owner: ownerA,
      credential: GenAiCredential(
        token: 'synthetic.jwt',
        expiresAt: DateTime.utc(2030),
      ),
      profile: const GenAiProfile(id: 'genai-user', username: '20240001'),
    );
    await store.write(session);
    expect((await store.read(ownerA))?.credential.token, 'synthetic.jwt');
    expect(
      (await store.read(ownerA))?.credential.expiresAt,
      DateTime.utc(2030),
    );
    expect(await store.read(ownerB), isNull);
    final all = await const FlutterSecureStorage().readAll();
    expect(all.keys.single, 'techpie.genai.session.v1.${ownerA.storageId}');
    expect(all.keys.single, isNot(contains(ownerA.studentId)));
    expect(jsonDecode(all.values.single)['owner'], ownerA.storageId);
    await store.delete(ownerA);
    expect(await store.read(ownerA), isNull);
  });

  test('a queued logout deletion cannot be overtaken by a pending write',
      () async {
    final store = SecureGenAiSessionStore();
    final write = store.write(
      const GenAiSession(
        owner: ownerA,
        credential: GenAiCredential(token: 'token'),
        profile: GenAiProfile(id: 'user', username: '20240001'),
      ),
    );
    final deletion = store.delete(ownerA);
    await Future.wait([write, deletion]);
    expect(await store.read(ownerA), isNull);
  });

  test('corrupt or mismatched records are removed without authenticating',
      () async {
    final key = 'techpie.genai.session.v1.${ownerA.storageId}';
    final storage = const FlutterSecureStorage();
    final store = SecureGenAiSessionStore(storage: storage);
    for (final raw in [
      'not-json',
      '{"version":1,"owner":"wrong","token":"private"}',
    ]) {
      await storage.write(key: key, value: raw);
      expect(await store.read(ownerA), isNull);
      expect(await storage.read(key: key), isNull);
    }
  });
}
