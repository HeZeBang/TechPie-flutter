import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_repository.dart';
import 'package:techpie/features/genai/application/genai_session_service.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';

void main() {
  late ScriptedTransport transport;
  late MemorySessionStore store;
  late GenAiSessionService sessions;
  late GenAiChatService chat;

  setUp(() async {
    transport = ScriptedTransport((_) async => profileResponse());
    final api = GenAiApiClient(transport: transport);
    store = MemorySessionStore();
    sessions = GenAiSessionService(api: api, store: store);
    chat = GenAiChatService(GenAiRepository(api: api, sessions: sessions));
    await sessions.setOwner(ownerA);
    await sessions.connect(const GenAiCredential(token: 'synthetic.jwt'));
  });
  tearDown(() {
    chat.dispose();
    sessions.dispose();
  });

  test('completed turn preserves answer, reasoning, and termination reason',
      () async {
    transport.handle = (_) async => response(
          type: 'text/event-stream',
          text: sseChunk(reasoning: 'reasoning') +
              sseChunk(text: 'answer') +
              sseChunk(finish: 'stop'),
        );
    await chat.send(chatRequest());
    expect(chat.phase, GenAiChatPhase.completed);
    expect(chat.answer, 'answer');
    expect(chat.reasoning, 'reasoning');
    expect(chat.failure, isNull);
  });

  test('EOF preserves partial answer as interrupted without replaying POST',
      () async {
    transport.handle = (_) async =>
        response(type: 'text/event-stream', text: sseChunk(text: 'partial'));
    await chat.send(chatRequest());
    expect(chat.phase, GenAiChatPhase.interrupted);
    expect(chat.answer, 'partial');
    expect(transport.requests.where((r) => r.method == 'POST').length, 1);
  });

  test('auth failure drops credential and prompts login without replaying POST',
      () async {
    transport.handle =
        (_) async => response(json: {'success': false, 'code': 401});
    await chat.send(chatRequest());
    expect(chat.phase, GenAiChatPhase.needsLogin);
    expect(sessions.session, isNull);
    expect(store.records, isEmpty);
    expect(transport.requests.where((r) => r.method == 'POST').length, 1);
  });

  test(
      'stop before response headers allows a new turn and rejects stale callbacks',
      () async {
    final header = Completer<GenAiResponse>();
    final started = Completer<void>();
    transport.handle = (r) {
      started.complete();
      return r.cancellation.race(header.future);
    };
    final old = chat.send(chatRequest());
    await started.future;
    await expectLater(
      chat.send(chatRequest()),
      throwsA(failure(GenAiFailureKind.busy)),
    );
    chat.stop();
    expect(chat.phase, GenAiChatPhase.cancelled);
    transport.handle = (_) async => response(
          type: 'text/event-stream',
          text: sseChunk(text: 'new answer', finish: 'stop'),
        );
    await chat.send(chatRequest());
    header.complete(
      response(type: 'text/event-stream', text: sseChunk(text: 'stale')),
    );
    await old;
    expect(chat.phase, GenAiChatPhase.completed);
    expect(chat.answer, 'new answer');
  });

  test('owner change cancels active stream and removes private partial output',
      () async {
    final wire = StreamController<List<int>>();
    final partial = Completer<void>();
    late RecordedRequest active;
    transport.handle = (request) async {
      active = request;
      request.cancellation.onCancel(() {
        wire.addError(const GenAiFailure(GenAiFailureKind.accountChanged));
        unawaited(wire.close());
      });
      return response(type: 'text/event-stream', bytes: wire.stream);
    };
    chat.addListener(() {
      if (chat.answer.isNotEmpty && !partial.isCompleted) partial.complete();
    });
    final turn = chat.send(chatRequest());
    wire.add(utf8.encode(sseChunk(text: 'private partial')));
    await partial.future;
    await sessions.setOwner(ownerB);
    await turn;
    expect(active.cancellation.isCancelled, isTrue);
    expect(chat.answer, isEmpty);
    expect(chat.reasoning, isEmpty);
    expect(chat.failure?.kind, GenAiFailureKind.accountChanged);
  });

  test('oversized output fails and closes the operation', () async {
    final limited = GenAiChatService(
      GenAiRepository(
        api: GenAiApiClient(transport: transport),
        sessions: sessions,
      ),
      maxOutputCharacters: 3,
    );
    addTearDown(limited.dispose);
    transport.handle = (_) async =>
        response(type: 'text/event-stream', text: sseChunk(text: 'too long'));
    await limited.send(chatRequest());
    expect(limited.phase, GenAiChatPhase.failed);
    expect(limited.failure?.kind, GenAiFailureKind.protocol);
    expect(transport.requests.last.cancellation.isCancelled, isTrue);
  });
}
