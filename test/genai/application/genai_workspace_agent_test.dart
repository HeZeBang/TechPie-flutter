import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';

import '../support/fakes.dart';
import '../support/journal_server.dart';

GenAiAgentTool testTool({bool mutation = false, Future<Object?> Function()? execute}) =>
    GenAiAgentTool(
      name: mutation ? 'reserve_court' : 'get_semesters',
      description: 'Test campus service',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {'type': 'string'},
        },
        'additionalProperties': false,
      },
      maxApprovalsPerRun: mutation ? 1 : null,
      prepare: (_, __) async => GenAiAgentPreparedTool(
        requiresApproval: mutation,
        effectKey: mutation ? 'court/date/slot' : null,
        execute: execute ?? () async => {'semester': 3},
      ),
    );

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 500 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(ready(), true);
}

void main() {
  test('new task after a timed-out tool turn has its own control on every step', () async {
    final server = JournalServer();
    var executions = 0;
    final client = await JournalClient.create(
      server,
      tools: [
        testTool(execute: () async => {'semester': ++executions}),
      ],
    );
    addTearDown(client.dispose);
    client.workspace.setAgentEnabled(true);
    server.onGenerate = (body) {
      if (decodeGenAiAgentRecord(server.input(body))?.result == null) return server.call(body);
      throw const GenAiFailure(GenAiFailureKind.timeout);
    };
    await client.workspace.send('Old task: read and compare semesters');
    expect(executions, 1);
    expect(client.workspace.turns.last.failure?.kind, GenAiFailureKind.timeout);
    var steps = 0;
    server.onGenerate = (body) {
      final messages = body['messages'] as List<dynamic>;
      expect((messages.last as Map)['role'], 'system');
      final control =
          jsonDecode((messages[messages.length - 2] as Map)['content'] as String) as Map;
      expect(control['current_task'], steps == 0 ? isNull : 'Only read the new semester');
      expect(
        control['current_step'],
        genAiAgentNonceFromSystem((messages.first as Map)['content'] as String),
      );
      expect(messages.toString(), contains('techpie_turn_end'));
      steps++;
      return decodeGenAiAgentRecord(server.input(body))?.result == null
          ? encodeGenAiCompactCall(
              'get_semesters',
              {},
              nonce: genAiAgentNonceFromSystem((messages.first as Map)['content'] as String)!,
            )
          : server.finalAnswer(body, 'New semester $executions');
    };
    await client.workspace.send('Only read the new semester');
    expect(steps, 2);
    expect(executions, 2);
    expect(client.workspace.turns.last.answer, 'New semester 2');
    final fresh = await JournalClient.create(server, tools: [testTool()]);
    addTearDown(fresh.dispose);
    await fresh.workspace.openConversation(client.workspace.groupId, GenAiCancellation());
    expect(fresh.workspace.turns.last.prompt, 'Only read the new semester');
    expect(fresh.workspace.turns.last.answer, 'New semester 2');
  });

  test('edited agent turns run the full loop and recover on a fresh client in both modes',
      () async {
    final server = JournalServer();
    var executions = 0;
    final tool = testTool(execute: () async => {'semester': ++executions});
    final client = await JournalClient.create(server, tools: [tool]);
    addTearDown(client.dispose);
    client.workspace.setAgentEnabled(true);
    server.onGenerate = (body) => decodeGenAiAgentRecord(server.input(body))?.result == null
        ? server.call(body)
        : server.finalAnswer(body, 'Semester $executions.');
    await client.workspace.send('original question');
    final group = client.workspace.groupId;
    final target = client.workspace.turns.single.id;
    await client.workspace.send('discarded followup');
    await client.workspace.changeTurn(target, replacement: 'edited question');
    expect(executions, 3);
    expect(client.workspace.turns.single.answer, 'Semester 3.');
    expect(server.rows[group], hasLength(2)); // Proposal plus receipt/final, no bookkeeping POST.
    for (final agent in [true, false]) {
      final fresh = await JournalClient.create(server, tools: [tool]);
      addTearDown(fresh.dispose);
      await fresh.workspace.openConversation(group, GenAiCancellation());
      expect(fresh.workspace.turns.first.prompt, 'edited question');
      expect(fresh.workspace.turns.first.agentEvents.values.single.result!['ok'], true);
      fresh.workspace.setAgentEnabled(agent);
      server.onGenerate = (body) {
        expect(body['messages'].toString(), contains('semester'));
        expect(body['messages'].toString(), isNot(contains('discarded followup')));
        expect(body['messages'].toString(), isNot(contains('original question')));
        return agent ? server.finalAnswer(body, 'Recall 3.') : 'Recall 3.';
      };
      await fresh.workspace.send('follow up');
      expect(fresh.workspace.turns.last.phase, GenAiChatPhase.completed);
    }
    expect(executions, 3); // Recovery never replays a tool.
  });

  for (final name in ['generate_image', 'reserve_court']) {
    test('explicit $name edit renews approval while keeping external receipts recoverable',
        () async {
      final server = JournalServer();
      var executions = 0;
      var slot = 'first';
      final tool = GenAiAgentTool(
        name: name,
        description: 'Test mutation',
        parameters: {'type': 'object', 'properties': <String, Object?>{}},
        maxApprovalsPerRun: name == 'reserve_court' ? 1 : null,
        prepare: (_, __) async => GenAiAgentPreparedTool(
          requiresApproval: true,
          effectKey: slot,
          execute: () async => {'completed': ++executions},
        ),
      );
      final client = await JournalClient.create(server, tools: [tool]);
      addTearDown(client.dispose);
      client.workspace.setAgentEnabled(true);
      server.onGenerate = (body) => decodeGenAiAgentRecord(server.input(body))?.result == null
          ? encodeGenAiCompactCall(name, {}, nonce: server.nonce(body))
          : server.finalAnswer(body, 'Done.');
      final sending = client.workspace.send('original');
      await until(() => client.workspace.pendingAgentApproval != null);
      client.workspace.resolveAgentApproval(name != 'generate_image');
      await sending;
      final group = client.workspace.groupId;
      final original = client.workspace.turns.single;
      slot = 'second';
      final editing = client.workspace.changeTurn(original.id, replacement: 'revised');
      await until(() => client.workspace.pendingAgentApproval != null);
      client.workspace.resolveAgentApproval(true);
      await editing;
      expect(
        client.workspace.turns.single.actionScopeId,
        isNot(original.actionScopeId ?? original.id),
      );
      expect(executions, name == 'generate_image' ? 1 : 2);
      final fresh = await JournalClient.create(server, tools: [tool]);
      addTearDown(fresh.dispose);
      await fresh.workspace.openConversation(group, GenAiCancellation());
      expect(fresh.workspace.turns.single.prompt, 'revised');
      if (name == 'reserve_court') {
        slot = 'first';
        await fresh.workspace.send('same previously booked court');
        expect(fresh.workspace.pendingAgentApproval, isNull);
        expect(executions, 2); // Old receipt survives deletion and a fresh client.
      }
    });
  }

  for (final cancel in [false, true]) {
    test('live mutation stays running until completion or cancellation: cancel=$cancel', () async {
      final server = JournalServer();
      final started = Completer<void>();
      final finish = Completer<Object?>();
      final client = await JournalClient.create(
        server,
        tools: [
          testTool(
            mutation: true,
            execute: () {
              started.complete();
              return finish.future;
            },
          ),
        ],
      );
      addTearDown(client.dispose);
      client.workspace.setAgentEnabled(true);
      server.onGenerate = (body) => server.generations.length == 1
          ? server.call(body, name: 'reserve_court', arguments: {'action': 'book'})
          : server.finalAnswer(body, 'Done.');
      final sending = client.workspace.send('Book one court');
      await until(() => client.workspace.pendingAgentApproval != null);
      client.workspace.resolveAgentApproval(true);
      await started.future;
      final turn = client.workspace.turns.single;
      expect(turn.agentEvents.values.single.kind, GenAiAgentEventKind.toolStarted);
      expect(turn.agentEvents.values.single.result, isNull);
      // The unknown receipt still exists for recovery even while the UI runs.
      expect(turn.agentTranscript.last.result?['error'], containsPair('code', 'outcome_unknown'));
      if (cancel) client.workspace.stop();
      finish.complete({'status': 'booked'});
      await sending;
      final result = turn.agentEvents.values.single.result!;
      expect(turn.agentEvents.values.single.kind, GenAiAgentEventKind.toolFinished);
      if (cancel) {
        expect(result['error'], containsPair('code', 'outcome_unknown'));
      } else {
        expect(result['ok'], true);
      }
    });
  }

  test('generated-image receipts supply visual context after remote recovery in both modes',
      () async {
    final server = JournalServer();
    const image = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/generated.png';
    const revision = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/revised.png';
    var executions = 0;
    final imageTool = GenAiAgentTool(
      name: 'generate_image',
      description: 'Test image',
      parameters: {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
      prepare: (_, __) async => GenAiAgentPreparedTool(
        execute: () async => {
          'status': 'generated',
          'images': [++executions == 1 ? image : revision],
        },
      ),
    );
    final a = await JournalClient.create(server, tools: [imageTool]);
    addTearDown(a.dispose);
    a.workspace.setAgentEnabled(true);
    server.onGenerate = (body) {
      expect(body['netGo'], false);
      if (decodeGenAiAgentRecord(server.input(body))?.result == null) {
        return server.call(body, name: 'generate_image');
      }
      expect(body['imageUrls'], [executions == 1 ? image : revision]);
      expect(body['messages'].toString(), contains('images: true'));
      expect(body['imageUrl'], executions == 1 ? image : revision);
      if (executions == 1) return server.call(body, name: 'generate_image');
      expect(body['imageUrls'], [revision]);
      return server.finalAnswer(body, 'Created.');
    };
    await a.workspace.send('Create a campus image');
    final id = a.workspace.groupId;
    for (final enabled in [false, true]) {
      final b = await JournalClient.create(server, tools: [imageTool]);
      addTearDown(b.dispose);
      expect(await b.workspace.openConversation(id, GenAiCancellation()), true);
      b.workspace.setAgentEnabled(enabled);
      server.onGenerate = (body) {
        expect(body['imageUrls'], enabled ? [revision] : [image, revision]);
        if (enabled) expect(body['messages'].toString(), contains(image));
        expect(body['imageUrl'], revision);
        expect(body['netGo'], false);
        return enabled ? server.finalAnswer(body, 'The saved picture.') : 'The saved picture.';
      };
      await b.workspace.send('Describe the image');
      expect(b.workspace.turns.last.phase, GenAiChatPhase.completed);
    }
    expect(server.transport.requests.any((r) => r.uri.path.endsWith('/net/search')), false);
  });

  test('fresh clients recover tools and documents; mode switches share one canonical context',
      () async {
    final server = JournalServer();
    final a = await JournalClient.create(server, tools: [testTool()]);
    addTearDown(a.dispose);
    a.workspace.setAgentEnabled(true);
    a.workspace.setThinking(true);
    await a.workspace.addDocumentAttachment('notes.txt', [65, 66]);
    server.onGenerate = (body) => decodeGenAiAgentRecord(server.input(body))?.result == null
        ? server.call(body)
        : server.finalAnswer(body, 'Semester 3; number 5837.');
    await a.workspace.send('Read the document and semester');
    expect(a.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(server.generations, hasLength(2)); // No metadata-only generation.
    final group = a.workspace.groupId;
    final b = await JournalClient.create(server, tools: [testTool()]);
    addTearDown(b.dispose);
    expect(await b.workspace.openConversation(group, GenAiCancellation()), true);
    final recovered = b.workspace.turns.single;
    expect(recovered.answer, 'Semester 3; number 5837.');
    expect(recovered.attachedFileContents['doc-1'], contains('5837'));
    expect(recovered.agentEvents.values.single.result!['ok'], true);
    expect(b.workspace.agentEnabled, true);
    b.workspace.setAgentEnabled(false);
    server.onGenerate = (_) => 'It is 5837.';
    await b.workspace.send('What was the number?');
    expect(b.workspace.turns.last.answer, 'It is 5837.');
    expect(server.generations.last['fileIds'], ['doc-1']);
    expect(server.generations.last['messages'].toString(), contains('Semester 3'));
    a.workspace.setAgentEnabled(false);
    await a.workspace.send('Another device continued; use that history');
    expect(a.workspace.turns, hasLength(3));
    expect(server.generations.last['messages'].toString(), contains('It is 5837.'));
  });

  test('mutation requires persisted proposal and explicit confirmation; retry cannot book twice',
      () async {
    final server = JournalServer();
    var executions = 0;
    final client = await JournalClient.create(
      server,
      tools: [testTool(mutation: true, execute: () async => ++executions)],
    );
    addTearDown(client.dispose);
    client.workspace.setAgentEnabled(true);
    server.onGenerate = (body) => decodeGenAiAgentRecord(server.input(body))?.result == null
        ? server.call(body, name: 'reserve_court', arguments: {'action': 'book'})
        : server.finalAnswer(body, 'Booked.');
    final sending = client.workspace.send('Book one court');
    await until(() => client.workspace.pendingAgentApproval != null);
    expect(executions, 0);
    client.workspace.resolveAgentApproval(true);
    await sending;
    expect(executions, 1);
    expect(client.workspace.turns.single.phase, GenAiChatPhase.completed);
    final fresh = await JournalClient.create(
      server,
      tools: [testTool(mutation: true, execute: () async => ++executions)],
    );
    addTearDown(fresh.dispose);
    await fresh.workspace.openConversation(client.workspace.groupId, GenAiCancellation());
    await fresh.workspace.retryTurn(0);
    expect(executions, 1);
    expect(fresh.workspace.pendingAgentApproval, isNull);
    expect(fresh.workspace.turns, hasLength(1));
  });

  test('missing persisted proposal fails closed before approval or mutation', () async {
    final server = JournalServer()..hideHistory = true;
    var executions = 0;
    final client = await JournalClient.create(
      server,
      tools: [testTool(mutation: true, execute: () async => ++executions)],
    );
    addTearDown(client.dispose);
    client.workspace.setAgentEnabled(true);
    server.onGenerate =
        (body) => server.call(body, name: 'reserve_court', arguments: {'action': 'book'});
    await client.workspace.send('Book one court');
    expect(executions, 0);
    expect(client.workspace.pendingAgentApproval, isNull);
    expect(client.workspace.turns.single.failure?.kind, GenAiFailureKind.storage);
    expect(server.generations, hasLength(1));
  });

  test('account switch during approval cancels the old execution', () async {
    final server = JournalServer();
    var executions = 0;
    final client = await JournalClient.create(
      server,
      tools: [testTool(mutation: true, execute: () async => ++executions)],
    );
    addTearDown(client.dispose);
    client.workspace.setAgentEnabled(true);
    server.onGenerate =
        (body) => server.call(body, name: 'reserve_court', arguments: {'action': 'book'});
    final pending = client.workspace.send('Book');
    await until(() => client.workspace.pendingAgentApproval != null);
    await client.sessions.setOwner(ownerB);
    client.workspace.resolveAgentApproval(true);
    await pending;
    expect(executions, 0);
    expect(client.workspace.turns, isEmpty);
  });

  test('late server open cannot replace a new chat; uncertain delete only reconciles', () async {
    final server = JournalServer();
    final client = await JournalClient.create(server);
    addTearDown(client.dispose);
    await client.workspace.send('Original');
    final group = client.workspace.groupId;
    server.readGate = Completer<void>();
    final opening = client.workspace.openConversation(group, GenAiCancellation());
    await Future<void>.delayed(Duration.zero);
    client.workspace.newConversation();
    server.readGate!.complete();
    server.readGate = null;
    expect(await opening, false);
    expect(client.workspace.turns, isEmpty);
    server.failDelete = true;
    await expectLater(
      client.workspace.deleteConversation(group, GenAiCancellation()),
      throwsA(isA<GenAiFailure>()),
    );
    expect(client.workspace.uncertainDeletionCount, 1);
    await client.workspace.reconcilePendingDeletions(GenAiCancellation());
    expect(server.deletes, 1);
    expect(client.workspace.uncertainDeletionCount, 0);
    expect(server.rows[group], isNotEmpty);
  });

  test('unsaved exchange blocks automatic continuation and opening does not reorder messages',
      () async {
    final server = JournalServer();
    final client = await JournalClient.create(server);
    addTearDown(client.dispose);
    await client.workspace.send('Original');
    final group = client.workspace.groupId;
    final time = server.rows[group]!.single['createTime'];
    await client.workspace.openConversation(group, GenAiCancellation());
    expect(server.rows[group]!.single['createTime'], time);
    server.hideHistory = true;
    await client.workspace.send('Must not silently replace history');
    expect(server.generations, hasLength(1));
    expect(client.workspace.archiveFailure, isNotNull);
  });

  test('rename is marked in the next real message without a bookkeeping generation', () async {
    final server = JournalServer();
    final client = await JournalClient.create(server);
    addTearDown(client.dispose);
    await client.workspace.send('Original');
    await client.workspace.renameConversation(client.workspace.groupId, 'Named chat');
    expect(server.generations, hasLength(1));
    await client.workspace.send('Followup');
    expect(
      decodeGenAiRemoteRecord(server.generations.last['chatInfo'] as String)!['title'],
      'Named chat',
    );
    final fresh = await JournalClient.create(server);
    addTearDown(fresh.dispose);
    await fresh.workspace.openConversation(client.workspace.groupId, GenAiCancellation());
    expect(fresh.workspace.title, 'Named chat');
  });
}
