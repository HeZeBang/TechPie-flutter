import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';

const _campusNotice = '<!doctype html><html><body>'
    '<div class="info1">该服务暂不开放外网访问，仅支持校内访问</div>'
    '</body></html>';

GenAiResponse _campusDenied({int status = 404}) => response(
      status: status,
      type: 'text/html; charset=utf-8',
      text: _campusNotice,
    );

void main() {
  late ScriptedTransport transport;
  late GenAiApiClient api;
  late MemorySessionStore store;
  late CallbackIssuer issuer;
  late GenAiSessionService sessions;

  setUp(() async {
    transport = ScriptedTransport((_) async => profileResponse());
    api = GenAiApiClient(transport: transport);
    store = MemorySessionStore();
    issuer = CallbackIssuer((_, __) async => const GenAiCredential(token: 'renewed.jwt'));
    sessions = GenAiSessionService(api: api, store: store, issuer: issuer);
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'cached.jwt'));
  });
  tearDown(() => sessions.dispose());

  test('campus denial during restore keeps cached credentials and never renews', () async {
    final cached = store.records[ownerA.storageId];
    final restored = GenAiSessionService(api: api, store: store, issuer: issuer);
    addTearDown(restored.dispose);
    await restored.setOwner(ownerA);
    transport.handle = (_) async => _campusDenied();

    await expectLater(
      restored.requireSession(),
      throwsA(failure(GenAiFailureKind.campusNetworkRequired)),
    );
    expect(restored.lastFailure?.kind, GenAiFailureKind.campusNetworkRequired);
    expect(restored.session, isNull);
    expect(store.records[ownerA.storageId], same(cached));
    expect(store.writes, 1);
    expect(issuer.calls, 0);
    expect(transport.requests, hasLength(2));

    // A user retry after reconnecting can verify the original saved token.
    transport.handle = (_) async => profileResponse();
    final recovered = await restored.requireSession();
    expect(recovered.credential.token, 'cached.jwt');
    expect(restored.lastFailure, isNull);
    expect(issuer.calls, 0);
    expect(transport.requests, hasLength(3));
    expect(transport.requests.last.headers['X-Access-Token'], 'cached.jwt');
  });

  test('a real HTTP 401 during restore still renews the rejected credential', () async {
    final restored = GenAiSessionService(api: api, store: store, issuer: issuer);
    addTearDown(restored.dispose);
    await restored.setOwner(ownerA);
    transport.handle = (request) async => request.headers['X-Access-Token'] == 'cached.jwt'
        ? _campusDenied(status: 401)
        : profileResponse();

    final renewed = await restored.requireSession();
    expect(renewed.credential.token, 'renewed.jwt');
    expect(store.records[ownerA.storageId], same(renewed));
    expect(issuer.calls, 1);
    expect(transport.requests, hasLength(3));
    expect(restored.lastFailure, isNull);
  });

  test('campus denial preserves an active login for catalog history and chat without replay',
      () async {
    final active = sessions.session;
    final revision = sessions.revision;
    final repository = GenAiRepository(api: api, sessions: sessions);
    final chat = GenAiChatService(repository);
    addTearDown(chat.dispose);
    transport.handle = (_) async => _campusDenied();

    await expectLater(
      repository.listModels(GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.campusNetworkRequired)),
    );
    await expectLater(
      repository.loadConversation('saved-conversation', GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.campusNetworkRequired)),
    );
    await chat.send(chatRequest());

    expect(chat.failure?.kind, GenAiFailureKind.campusNetworkRequired);
    expect(chat.failure?.effectNotDispatched, isTrue);
    expect(chat.phase, GenAiChatPhase.failed);
    expect(sessions.session, same(active));
    expect(sessions.revision, revision);
    expect(store.records[ownerA.storageId], same(active));
    expect(store.writes, 1);
    expect(issuer.calls, 0);
    expect(transport.requests, hasLength(4));
    expect(transport.requests.where((request) => request.method == 'POST'), hasLength(1));
  });

  test('a real HTTP 401 during chat still invalidates login without replaying POST', () async {
    final chat = GenAiChatService(GenAiRepository(api: api, sessions: sessions));
    addTearDown(chat.dispose);
    transport.handle = (_) async => _campusDenied(status: 401);

    await chat.send(chatRequest());

    expect(chat.failure?.kind, GenAiFailureKind.authenticationRequired);
    expect(chat.phase, GenAiChatPhase.needsLogin);
    expect(sessions.session, isNull);
    expect(store.records, isEmpty);
    expect(issuer.calls, 0);
    expect(transport.requests.where((request) => request.method == 'POST'), hasLength(1));
  });
}
