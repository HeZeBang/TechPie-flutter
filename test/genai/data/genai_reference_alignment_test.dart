import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_context_compactor.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

import '../support/fakes.dart';

void main() {
  test('V2 enriches matching routes without hiding images or masking auth failure', () async {
    var status = 200;
    final transport = ScriptedTransport((r) async {
      final v2 = r.uri.path.endsWith('/V2');
      if (v2 && status != 200) return response(status: status, json: {});
      return response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': [
              if (!v2)
                {'aiName': 'Image', 'aiType': 'GPT-Image-2', 'rootAiType': 'azure', 'status': 2},
              {
                'aiName': v2 ? 'Kimi K3.1 Pro' : 'Kimi-K3',
                'aiType': 'Kimi-k3',
                'rootAiType': 'xinference',
                'status': '3',
                'enableDeepThink': v2 ? 1 : 0,
                if (v2) 'longContextTokenThreshold': 272000,
                if (v2) 'promptPrice': '0.000002',
              },
            ],
          },
        },
      );
    });
    final api = GenAiApiClient(transport: transport);
    final models = await api.listModels('token', GenAiCancellation());
    expect(models, hasLength(2));
    expect(models.first.isImage, isTrue);
    expect(models.last.name, 'Kimi K3.1 Pro');
    expect(models.last.supportsThinking, isTrue);
    expect(models.last.longContextTokenThreshold, 272000);
    status = 404;
    expect(await api.listModels('token', GenAiCancellation()), hasLength(2));
    status = 401;
    await expectLater(
      api.listModels('token', GenAiCancellation()),
      throwsA(failure(GenAiFailureKind.authenticationRequired)),
    );
  });

  test('unassigned and utility V2 rows cannot break or pollute a usable catalog', () async {
    final transport = ScriptedTransport(
      (r) async => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'records': r.uri.path.endsWith('/V2')
                ? [
                    {'aiName': 'Unassigned', 'aiType': 'orphan', 'status': '3'},
                    {
                      'aiName': 'Speech',
                      'aiType': 'tts',
                      'rootAiType': 'other_resource',
                      'status': '5',
                    },
                    {
                      'aiName': 'Retired',
                      'aiType': 'retired',
                      'rootAiType': 'azure',
                      'status': '1',
                    },
                    {'aiName': 'No type', 'aiType': 'unknown', 'rootAiType': 'future-provider'},
                    {
                      'aiName': null,
                      'aiType': 'Kimi-k3',
                      'rootAiType': 'xinference',
                      'payType': null,
                      'status': '3',
                      'enableDeepThink': 1,
                      'thinkingFieldValue': 4,
                    },
                    {
                      'aiName': 'New chat',
                      'aiType': 'new-chat',
                      'rootAiType': 'litellm',
                      'status': '3',
                    },
                    {'aiName': 'Image', 'aiType': 'image', 'rootAiType': 'azure', 'status': '2'},
                    'unreadable row',
                  ]
                : [
                    {
                      'aiName': 'Kimi',
                      'aiType': 'Kimi-k3',
                      'rootAiType': 'xinference',
                      'status': '3',
                      'payType': 'FREE',
                    },
                  ],
          },
        },
      ),
    );
    final models = await GenAiApiClient(
      transport: transport,
    ).listModels('token', GenAiCancellation());
    expect(models.map((m) => m.aiType), ['Kimi-k3', 'new-chat', 'image']);
    expect(models.first.name, 'Kimi');
    expect(models.first.payType, 'FREE');
    expect(models.first.supportsThinking, isTrue);
    expect(models.first.thinkingFieldValue, isNull);
    expect(models.last.isImage, isTrue);
  });

  test('school receipt and end markers complete non-Azure streamed answers', () async {
    for (final ending in [
      {
        'other': jsonEncode({'answerGroupId': 'saved', 'totalTokens': 42}),
      },
      {'isEnd': 1},
      {'is_end': 1},
    ]) {
      final transport = ScriptedTransport(
        (_) async => response(
          type: 'text/event-stream',
          text:
              'data: {"choices":[{"delta":{"content":"Answer"}}]}\n\ndata: ${jsonEncode(ending)}\n\n',
        ),
      );
      final events = await GenAiApiClient(transport: transport)
          .streamChat(
            GenAiChatRequest(
              chatGroupId: 'g',
              prompt: 'q',
              aiType: 'Kimi-k3',
              rootAiType: 'xinference',
            ),
            'token',
            GenAiCancellation(),
          )
          .toList();
      expect(events.whereType<GenAiTextDelta>().single.text, 'Answer');
      expect(events.last, isA<GenAiChatFinished>());
    }
  });

  test('large original context survives beyond old window and metadata price threshold', () async {
    final compactor = GenAiContextCompactor();
    final request = GenAiChatRequest(
      chatGroupId: 'long-context',
      prompt: 'Recall the original number',
      aiType: 'Kimi-k3',
      rootAiType: 'xinference',
      history: [
        GenAiMessage(role: GenAiRole.user, content: 'Original number: 5837. ${'context ' * 80000}'),
        const GenAiMessage(role: GenAiRole.assistant, content: 'Recorded'),
        for (var i = 0; i < 80; i++)
          GenAiMessage(role: GenAiRole.values[i % 2], content: 'Earlier turn $i'),
      ],
    );
    final prepared = await compactor.prepare(request, GenAiCancellation(), (_, __) async* {
      fail('A valid context below the documented window must not be summarized');
    });
    expect(prepared.history.first.content, request.history.first.content);
    expect(prepared.contextCompacted, isFalse);
    expect(prepared.history, hasLength(request.history.length));
    compactor.checkWireBudget(prepared);
    final withFile = GenAiChatRequest(
      chatGroupId: 'g',
      prompt: ' ',
      aiType: 'Kimi-k3',
      rootAiType: 'xinference',
      fileIds: ['doc'],
    );
    expect(withFile.toJson()['chatInfo'], '请分析所附内容。');
    final boundary = GenAiChatRequest(
      chatGroupId: 'g',
      prompt: 'x' * 900000,
      aiType: 'Kimi-k3',
      rootAiType: 'xinference',
      history: [GenAiMessage(role: GenAiRole.user, content: 'y' * 950000)],
    );
    expect(boundary.toJson()['chatInfo'], hasLength(900000));
    expect(
      () => boundary.withRecord({'extra': 'metadata'}).toJson(),
      throwsA(failure(GenAiFailureKind.messageTooLarge)),
    );
  });

  test('history larger than the former JSON cap is readable by a fresh client', () async {
    final original = '证据' * 400000;
    final transport = ScriptedTransport(
      (_) async => response(
        json: {
          'success': true,
          'code': 200,
          'result': [
            {'id': 'row', 'question': original, 'answer': 'Recorded'},
          ],
        },
      ),
    );
    final rows = await GenAiApiClient(
      transport: transport,
    ).loadConversation('token', 'group', GenAiCancellation());
    expect(rows.single.prompt, original);
    expect(rows.single.isHistoryGap, isFalse);
  });

  test('session metadata operations use POST bodies without model generation', () async {
    final transport = ScriptedTransport(
      (_) async => response(json: {'success': true, 'code': 200}),
    );
    final api = GenAiApiClient(transport: transport);
    await api.renameConversation('token', 'g', 'A new title', GenAiCancellation());
    await api.pinConversations('token', ['g'], true, GenAiCancellation());
    await api.deleteConversations('token', ['g', 'h'], GenAiCancellation());
    expect(transport.requests.map((r) => r.uri.path), [
      '/htk/ai/history/group/rename',
      '/htk/ai/history/group/pin',
      '/htk/ai/history/group/delete',
    ]);
    expect(transport.requests.every((r) => r.method == 'POST'), isTrue);
    expect(jsonDecode(transport.requests[0].body!), {'chatGroupId': 'g', 'title': 'A new title'});
    expect(jsonDecode(transport.requests[1].body!), {
      'chatGroupIds': ['g'],
      'pinned': true,
    });
  });
}
