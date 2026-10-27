import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';

void main() {
  late MemorySessionStore store;
  late ScriptedTransport transport;
  late GenAiSessionService service;

  setUp(() {
    store = MemorySessionStore();
    transport = ScriptedTransport((_) async => profileResponse());
    service = GenAiSessionService(
      api: GenAiApiClient(transport: transport),
      store: store,
    );
  });
  tearDown(() => service.dispose());

  test(
      'construction and owner attachment perform no storage reads or network work',
      () async {
    await service.setOwner(ownerA);
    expect(store.reads, 0);
    expect(transport.requests, isEmpty);
    await expectLater(
      service.requireSession(),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(transport.requests, isEmpty);
  });

  test(
      'persists only a server-verified credential with matching campus identity',
      () async {
    await service.setOwner(ownerA);
    final session =
        await service.connect(const GenAiCredential(token: 'synthetic.jwt'));
    expect(service.session, same(session));
    expect(store.records[ownerA.storageId], same(session));
    expect(session.toString(), isNot(contains('synthetic.jwt')));
    transport.handle = (_) async => profileResponse(ownerB.studentId);
    await expectLater(
      service.connect(const GenAiCredential(token: 'wrong.jwt')),
      throwsA(failure(GenAiFailureKind.identityMismatch)),
    );
    expect(service.session, isNull);
    expect(store.records, isEmpty);
  });

  test('cached tokens are revalidated once across concurrent consumers',
      () async {
    await service.setOwner(ownerA);
    await service.connect(const GenAiCredential(token: 'cached.jwt'));
    final restored = GenAiSessionService(
      api: GenAiApiClient(transport: transport),
      store: store,
    );
    addTearDown(restored.dispose);
    await restored.setOwner(ownerA);
    final gate = Completer<GenAiResponse>();
    transport.handle = (_) => gate.future;
    final one = restored.requireSession();
    final two = restored.requireSession();
    expect(one, same(two));
    gate.complete(profileResponse());
    expect(await one, same(await two));
    expect(transport.requests.length, 2); // Initial connection + one restore.
  });

  test(
      'account change during verification rejects stale result and deletes old record',
      () async {
    await service.setOwner(ownerA);
    final gate = Completer<GenAiResponse>();
    final started = Completer<void>();
    transport.handle = (_) {
      started.complete();
      return gate.future;
    };
    final pending = service.connect(const GenAiCredential(token: 'late.jwt'));
    final expectation =
        expectLater(pending, throwsA(failure(GenAiFailureKind.accountChanged)));
    await started.future;
    await service.setOwner(ownerB);
    await expectation;
    gate.complete(profileResponse());
    await Future<void>.delayed(Duration.zero);
    expect(service.owner, ownerB);
    expect(service.session, isNull);
    expect(store.records, isEmpty);
    expect(store.writes, 0);
  });

  test(
      'renewal issuer is single-flight and verifies identity before committing',
      () async {
    final gate = Completer<GenAiCredential>();
    final issuer = CallbackIssuer((_, __) => gate.future);
    final renewing = GenAiSessionService(
      api: GenAiApiClient(transport: transport),
      store: store,
      issuer: issuer,
    );
    addTearDown(renewing.dispose);
    await renewing.setOwner(ownerA);
    final one = renewing.requireSession();
    final two = renewing.requireSession();
    gate.complete(const GenAiCredential(token: 'renewed.jwt'));
    expect(await one, same(await two));
    expect(issuer.calls, 1);
    expect(transport.requests.single.headers['X-Access-Token'], 'renewed.jwt');
  });

  test(
      'expired credentials need reauthentication without assuming a JWT refresh route',
      () async {
    await service.setOwner(ownerA);
    await expectLater(
      service.connect(
        GenAiCredential(token: 'expired', expiresAt: DateTime(2000)),
      ),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
    expect(transport.requests, isEmpty);
  });

  test('an old rejection cannot disconnect a newer successful credential',
      () async {
    await service.setOwner(ownerA);
    final old = await service.connect(const GenAiCredential(token: 'old'));
    final current = await service.connect(const GenAiCredential(token: 'new'));
    await service.reject(old);
    expect(service.session, same(current));
    await service.reject(current);
    expect(service.session, isNull);
    expect(store.records, isEmpty);
  });

  test(
      'logout invalidates memory immediately and surfaces failed secure deletion',
      () async {
    await service.setOwner(ownerA);
    await service.connect(const GenAiCredential(token: 'token'));
    store.failDelete = true;
    final logout = service.setOwner(null);
    expect(service.owner, isNull);
    expect(service.session, isNull);
    await expectLater(logout, throwsA(failure(GenAiFailureKind.storage)));
    expect(service.lastFailure?.kind, GenAiFailureKind.storage);
  });
}
