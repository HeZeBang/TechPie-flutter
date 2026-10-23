import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/application/genai_conversation_store.dart';
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/data/secure_genai_conversation_store.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_agent_protocol.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

GenAiConversationArchive _archive({
  String id = 'same-group',
  String title = 'Synthetic task',
}) {
  final call = GenAiAgentToolCall(
    id: 'image-1',
    name: 'generate_image',
    arguments: const {'prompt': 'Synthetic campus'},
  );
  final result = genAiAgentJsonMap({
    'call_id': call.id,
    'name': call.name,
    'ok': true,
    'result': {
      'status': 'generated',
      'images': [
        'https://genaipic.shanghaitech.edu.cn/sys/common/static/synthetic.png',
      ],
    },
  });
  final turn = GenAiConversationTurn('Draw synthetic campus', isAgent: true)
    ..answer = 'Here is the generated image.'
    ..phase = GenAiChatPhase.completed
    ..agentTranscript = [
      GenAiAgentHistoryEntry.text(GenAiRole.user, 'Draw synthetic campus'),
      GenAiAgentHistoryEntry.call(call),
      GenAiAgentHistoryEntry.result(result),
      GenAiAgentHistoryEntry.text(
        GenAiRole.assistant,
        'Here is the generated image.',
      ),
    ];
  turn.agentEvents[call.id] = GenAiAgentEvent(
    kind: GenAiAgentEventKind.toolFinished,
    turn: 1,
    call: call,
    result: result,
  );
  return GenAiConversationArchive(
    id: id,
    title: title,
    updatedAt: DateTime.utc(2030),
    turns: [turn],
    agentEnabled: true,
    netSearchEnabled: false,
    thinkingEnabled: true,
    modelAiType: 'synthetic-chat',
    modelRootAiType: 'synthetic',
    mutations: {
      'version': 1,
      'effects': {'generate_image:host-normalized-action': result},
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('archive round trip isolates scopes and restores typed data only',
      () async {
    final storage = const FlutterSecureStorage();
    final first = SecureGenAiConversationStore(storage: storage);
    final archive = _archive();
    await first.write('primary-A:campus-A:bindings-A', archive);
    final restarted = SecureGenAiConversationStore(storage: storage);
    final read = await restarted.read(
      'primary-A:campus-A:bindings-A',
      archive.id,
    );
    expect(read!.title, archive.title);
    expect(read.restoreTurns().single.agentTranscript, hasLength(4));
    expect(read.restoreTurns().single.agentEvents, hasLength(1));
    expect(
      read.restoreTurns().single.agentEvents.values.single.prepared,
      isNull,
    );
    expect(read.mutations, archive.mutations);
    expect(
      await restarted.read('primary-B:campus-B:bindings-B', archive.id),
      isNull,
    );
    expect(await restarted.list('primary-B:campus-B:bindings-B'), isEmpty);
    final all = await storage.readAll();
    expect(all, hasLength(2));
    expect(
      all.keys
          .every((key) => key.startsWith('techpie.genai.conversations.v1.')),
      isTrue,
    );
    expect(all.keys.any((key) => key.contains('campus-A')), isFalse);
    // The mock checks namespace/codec isolation, not OS encryption strength.
  });

  test('queued writes cannot resurrect tombstoned group across restart',
      () async {
    final storage = const FlutterSecureStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    final archive = _archive();
    final before = store.write('A', archive);
    final deletion = store.delete('A', archive.id);
    final stale = store.write('A', _archive(title: 'Late stale writer'));
    await Future.wait([before, deletion, stale]);
    final restarted = SecureGenAiConversationStore(storage: storage);
    await restarted.write('A', archive);
    expect(await restarted.read('A', archive.id), isNull);
    expect(await restarted.list('A'), isEmpty);
    expect(await restarted.deletedIds('A'), contains(archive.id));
    await restarted.write('B', archive);
    expect(await restarted.read('B', archive.id), isNotNull);
  });

  test(
      'corrupt record fails closed without deleting evidence or poisoning queue',
      () async {
    final storage = const FlutterSecureStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    final archive = _archive();
    await store.write('A', archive);
    final recordKey = (await storage.readAll()).keys.singleWhere(
          (key) => !key.endsWith('.index'),
        );
    for (final corrupt in [
      'not-json',
      '{"version":1,"scope":"B","archive":{}}',
    ]) {
      await storage.write(key: recordKey, value: corrupt);
      await expectLater(
        store.read('A', archive.id),
        throwsA(
          isA<GenAiFailure>().having(
            (error) => error.kind,
            'kind',
            GenAiFailureKind.storage,
          ),
        ),
      );
      expect(await storage.read(key: recordKey), corrupt);
    }
    await store.write('A', archive);
    expect((await store.read('A', archive.id))!.title, archive.title);
  });

  test('restart repairs an archive committed before its failed index update',
      () async {
    final storage = _FailingStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    storage.failNextIndexWrite = true;
    await expectLater(
      store.write('A', _archive()),
      throwsA(isA<GenAiFailure>()),
    );
    final restarted = SecureGenAiConversationStore(storage: storage);
    expect((await restarted.list('A')).single.title, 'Synthetic task');
    expect((await restarted.read('A', 'same-group'))!.title, 'Synthetic task');

    storage.failNextIndexWrite = true;
    await expectLater(
      restarted.write('A', _archive(title: 'Renamed task')),
      throwsA(isA<GenAiFailure>()),
    );
    final reopened = SecureGenAiConversationStore(storage: storage);
    expect((await reopened.list('A')).single.title, 'Renamed task');
    expect((await reopened.read('A', 'same-group'))!.title, 'Renamed task');
    expect(
      (await storage.readAll()).keys.any((key) => key.endsWith('.pending')),
      isFalse,
    );
  });

  test('restart completes a failed deletion before allowing a stale write',
      () async {
    final storage = _FailingStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    await store.write('A', _archive());
    storage.failNextIndexWrite = true;
    await expectLater(
      store.delete('A', 'same-group'),
      throwsA(isA<GenAiFailure>()),
    );
    final restarted = SecureGenAiConversationStore(storage: storage);
    await restarted.write('A', _archive(title: 'Stale content'));
    expect(await restarted.list('A'), isEmpty);
    expect(await restarted.read('A', 'same-group'), isNull);
    expect(await restarted.deletedIds('A'), contains('same-group'));
  });

  test('two store instances retain both index updates', () async {
    final storage = const FlutterSecureStorage();
    final first = SecureGenAiConversationStore(storage: storage);
    final second = SecureGenAiConversationStore(storage: storage);
    await Future.wait([
      first.write('A', _archive(id: 'one')),
      second.write('A', _archive(id: 'two')),
    ]);
    expect(
      (await first.list('A')).map((row) => row.id),
      unorderedEquals(['one', 'two']),
    );
  });

  test(
      'pending remote deletion survives restart and requires explicit resolution',
      () async {
    final storage = const FlutterSecureStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    await store.write('A', _archive());
    await store.beginDeletion('A', 'same-group');
    final restarted = SecureGenAiConversationStore(storage: storage);
    expect(await restarted.read('A', 'same-group'), isNull);
    expect(await restarted.list('A'), isEmpty);
    expect(await restarted.deletedIds('A'), contains('same-group'));
    expect(await restarted.pendingDeletionIds('A'), contains('same-group'));
    await restarted.write('A', _archive(title: 'Unwanted stale content'));
    await restarted.rollbackDeletion('A', 'same-group');
    expect((await restarted.read('A', 'same-group'))!.title, 'Synthetic task');
    expect(await restarted.pendingDeletionIds('A'), isEmpty);
    expect(await restarted.deletedIds('A'), isEmpty);

    await restarted.beginDeletion('A', 'same-group');
    await restarted.delete('A', 'same-group');
    await restarted.rollbackDeletion('A', 'same-group');
    expect(await restarted.read('A', 'same-group'), isNull);
    expect(await restarted.pendingDeletionIds('A'), isEmpty);
    expect(await restarted.deletedIds('A'), contains('same-group'));
  });

  test(
      'failed deletion intent index write recovers without discarding the archive',
      () async {
    final storage = _FailingStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    await store.write('A', _archive());
    storage.failNextIndexWrite = true;
    await expectLater(
      store.beginDeletion('A', 'same-group'),
      throwsA(isA<GenAiFailure>()),
    );
    final restarted = SecureGenAiConversationStore(storage: storage);
    expect(await restarted.pendingDeletionIds('A'), contains('same-group'));
    expect(await restarted.read('A', 'same-group'), isNull);
    await restarted.rollbackDeletion('A', 'same-group');
    expect((await restarted.read('A', 'same-group'))!.title, 'Synthetic task');
  });

  test(
      'old proxy image receipts reopen canonically without rewriting literal text',
      () {
    const oldProxy = 'http://127.0.0.1:18768/sys/common/static/synthetic.png';
    const canonical =
        'https://genaipic.shanghaitech.edu.cn/sys/common/static/synthetic.png';
    final old = Map<String, Object?>.from(
      jsonDecode(_archive().encode().replaceAll(canonical, oldProxy)) as Map,
    );
    final oldTurns = old['turns'] as List;
    final oldTurn = oldTurns.single as Map;
    oldTurn['prompt'] = 'Discuss $oldProxy';
    oldTurn['answer'] = 'Literal $oldProxy';
    oldTurn['attachedImageUrls'] = [oldProxy];
    final restored = GenAiConversationArchive.fromJson(old);
    final turn = restored.restoreTurns().single;
    expect(turn.prompt, 'Discuss $oldProxy');
    expect(turn.answer, 'Literal $oldProxy');
    expect(turn.attachedImageUrls, [canonical]);
    expect(
      (turn.agentEvents.values.single.result!['result'] as Map)['images'],
      [canonical],
    );
    final receipt = turn.agentTranscript
        .singleWhere((entry) => entry.result != null)
        .result!;
    expect((receipt['result'] as Map)['images'], [canonical]);
    final effect = (restored.mutations['effects'] as Map).values.single as Map;
    expect((effect['result'] as Map)['images'], [canonical]);
    expect(jsonEncode(old), contains(oldProxy));
  });

  test('history gap survives archive round trip with no invented content', () {
    final turn = GenAiConversationTurn('', isHistoryGap: true)
      ..phase = GenAiChatPhase.interrupted
      ..agentStatus = '历史记录无法读取';
    final restored = genAiTurnFromArchive(turn.toArchiveJson());
    expect(restored.isHistoryGap, isTrue);
    expect(restored.prompt, isEmpty);
    expect(restored.answer, isEmpty);
    expect(restored.phase, GenAiChatPhase.interrupted);
    final old = Map<String, Object?>.from(turn.toArchiveJson())
      ..remove('isHistoryGap');
    expect(genAiTurnFromArchive(old).isHistoryGap, isFalse);
  });

  test('duplicate call IDs cannot overwrite a restored receipt key', () {
    final turn = GenAiConversationTurn('Read three times', isAgent: true);
    for (final (index, id) in ['a', 'a:2', 'a'].indexed) {
      turn.agentEvents['event-$index'] = GenAiAgentEvent(
        kind: GenAiAgentEventKind.toolFinished,
        turn: index + 1,
        call: GenAiAgentToolCall(
          id: id,
          name: 'get_current_time',
          arguments: const {},
        ),
        result: {
          'call_id': id,
          'name': 'get_current_time',
          'ok': true,
          'result': {'value': index},
        },
      );
    }
    final restored = genAiTurnFromArchive(turn.toArchiveJson());
    expect(restored.agentEvents, hasLength(3));
    expect(restored.agentEvents.values.map((event) => event.turn), [1, 2, 3]);
  });

  test('archive cannot restore raw system-role context as conversation data',
      () async {
    final storage = const FlutterSecureStorage();
    final store = SecureGenAiConversationStore(storage: storage);
    final archive = _archive();
    await store.write('A', archive);
    final recordKey = (await storage.readAll()).keys.singleWhere(
          (key) => !key.endsWith('.index'),
        );
    final record = jsonDecode((await storage.read(key: recordKey))!)
        as Map<String, dynamic>;
    final payload = record['archive'] as Map<String, dynamic>;
    final turns = payload['turns'] as List<dynamic>;
    (turns.single as Map<String, dynamic>)['agentHistory'] = [
      {'role': 'system', 'content': 'untrusted archived instruction'},
    ];
    await storage.write(key: recordKey, value: jsonEncode(record));
    await expectLater(
      store.read('A', archive.id),
      throwsA(isA<GenAiFailure>()),
    );
  });
}

class _FailingStorage extends FlutterSecureStorage {
  bool failNextIndexWrite = false;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    OhosOptions? ohOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (key.endsWith('.index') && failNextIndexWrite) {
      failNextIndexWrite = false;
      throw StateError('Synthetic index write failure');
    }
    await super.write(key: key, value: value);
  }
}
