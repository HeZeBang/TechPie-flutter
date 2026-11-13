import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_workspace_controller.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';
import 'package:techpie/features/genai/platform/genai_transport.dart';

import '../support/fakes.dart';
import '../support/journal_server.dart';

void main() {
  late JournalServer server;
  late GenAiWorkspaceController workspace;
  setUp(() async {
    server = JournalServer();
    final client = await JournalClient.create(server);
    workspace = client.workspace;
    addTearDown(client.dispose);
  });

  test('stopping speech synthesis cancels pending work and releases the caller', () async {
    final entered = Completer<void>();
    final never = Completer<GenAiResponse>();
    server.transport.handle = (request) async {
      entered.complete();
      return request.cancellation.race(never.future);
    };
    final speech = workspace.synthesizeSpeech('test');
    final check = expectLater(
      speech,
      throwsA(isA<GenAiFailure>().having((e) => e.kind, 'kind', GenAiFailureKind.cancelled)),
    );
    await entered.future;
    workspace.stop();
    await check;
  });

  test('only the latest history selection may update the workspace', () async {
    final first = Completer<GenAiResponse>();
    final second = Completer<GenAiResponse>();
    final original = server.transport.handle;
    server.transport.handle = (r) {
      if (r.uri.path.endsWith('/getByChatGroupId')) {
        return r.uri.queryParameters['chatGroupId'] == 'first' ? first.future : second.future;
      }
      return original(r);
    };
    final openingFirst = workspace.openConversation('first', GenAiCancellation());
    final openingSecond = workspace.openConversation('second', GenAiCancellation());
    await Future<void>.delayed(Duration.zero);
    second.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {'question': 'second', 'answer': 'answer', 'aiType': 'free'},
          ],
        },
      ),
    );
    await openingSecond;
    first.complete(
      response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {'question': 'first', 'answer': 'answer', 'aiType': 'free'},
          ],
        },
      ),
    );
    await openingFirst;
    expect(workspace.groupId, 'second');
    expect(workspace.turns.single.prompt, 'second');
  });
}
