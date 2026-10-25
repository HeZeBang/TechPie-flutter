import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/presentation/genai_agent_widgets.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: genAiTheme(ThemeData()),
        home: Scaffold(body: SingleChildScrollView(child: card)),
      ),
    );
  }

  testWidgets('completed and restored repairs never appear to be still running', (tester) async {
    const repair = GenAiAgentEvent(kind: GenAiAgentEventKind.protocolError, turn: 1);
    Future<void> show(bool running, {String id = 'live'}) => pumpCard(
          tester,
          GenAiAgentToolActivity(
            key: ValueKey(id),
            events: const [],
            activity: const [repair],
            running: running,
            stopped: false,
          ),
        );
    await show(true);
    expect(find.text('正在修正工具请求'), findsOneWidget);
    await show(false);
    expect(find.text('正在修正工具请求'), findsNothing);
    expect(find.text('工具请求格式不匹配，已请求重试'), findsOneWidget);
    await show(false, id: 'restored');
    await tester.tap(find.byKey(const ValueKey('agent-tool-activity-heading')));
    await tester.pumpAndSettle();
    expect(find.text('正在修正工具请求'), findsNothing);
    expect(find.text('工具请求格式不匹配，已请求重试'), findsOneWidget);
  });

  testWidgets('tool activity keeps collapse choice through updates and isolates turns',
      (tester) async {
    final first = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: GenAiAgentToolCall(
        id: 'time',
        name: 'get_current_time',
        arguments: const {},
      ),
      result: const {'ok': true},
    );
    final second = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 2,
      call: GenAiAgentToolCall(
        id: 'semester',
        name: 'get_semesters',
        arguments: const {},
      ),
      result: const {'ok': false},
    );
    Future<void> show(
      List<GenAiAgentEvent> events, {
      bool running = true,
      String id = 'a',
    }) =>
        pumpCard(
          tester,
          GenAiAgentToolActivity(
            key: ValueKey(id),
            events: events,
            running: running,
            stopped: false,
          ),
        );
    final toggle = find.byKey(const ValueKey('agent-tool-activity-heading'));
    await show([first]);
    expect(find.text('查看当前时间'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间'), findsNothing);
    await show([first, second]);
    await tester.pumpAndSettle();
    expect(find.text('处理过程 · 2 次工具调用 · 进行中'), findsOneWidget);
    expect(find.text('查看学期'), findsNothing);
    await show([first, second], running: false);
    await tester.pumpAndSettle();
    expect(find.text('处理过程 · 2 次工具调用 · 有未完成项'), findsOneWidget);
    expect(find.text('查看学期'), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间'), findsOneWidget);
    expect(find.text('查看学期'), findsOneWidget);
    // Another restored turn must not inherit the previous turn's open state.
    await show([first], running: false, id: 'restored');
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordered process interleaves reasoning, tools and searchable sources',
      (tester) async {
    final tool = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: GenAiAgentToolCall(
        id: 'time',
        name: 'get_current_time',
        arguments: const {},
      ),
      result: const {'ok': true},
    );
    final search = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 2,
      call: GenAiAgentToolCall(
        id: 'search',
        name: 'web_search',
        arguments: const {'query': 'public resources'},
      ),
      result: const {
        'ok': true,
        'result': {
          'citations': [
            {
              'num': 1,
              'title': 'Public source',
              'link': 'https://example.com',
              'snippet': 'Reference data',
            },
          ],
        },
      },
    );
    await pumpCard(
      tester,
      GenAiAgentToolActivity(
        events: [tool, search],
        activity: [
          const GenAiAgentEvent(
            kind: GenAiAgentEventKind.reasoningDelta,
            turn: 1,
            text: 'First reasoning step',
          ),
          tool,
          const GenAiAgentEvent(
            kind: GenAiAgentEventKind.reasoningDelta,
            turn: 2,
            text: 'Second reasoning step',
          ),
          search,
        ],
        running: true,
        stopped: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First reasoning step'), findsNothing);
    final thoughts = find.text('已完成深度思考');
    final time = find.text('查看当前时间');
    final sources = find.text('搜索：public resources · 1 条来源');
    expect(
      tester.getTopLeft(thoughts.first).dy,
      lessThan(tester.getTopLeft(time).dy),
    );
    expect(
      tester.getTopLeft(time).dy,
      lessThan(tester.getTopLeft(thoughts.last).dy),
    );
    expect(
      tester.getTopLeft(thoughts.last).dy,
      lessThan(tester.getTopLeft(sources).dy),
    );
    await tester.tap(thoughts.first);
    await tester.pumpAndSettle();
    expect(find.text('First reasoning step'), findsOneWidget);
    await tester.ensureVisible(sources);
    await tester.tap(sources);
    await tester.pumpAndSettle();
    expect(find.text('Public source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline approval uses prepared details and host callbacks', (tester) async {
    var approved = 0;
    var rejected = 0;
    final mutableDetails = <String, Object?>{
      'prompt': '一幅简洁的校园风景插画，保留清晰自然的建筑轮廓。',
      'quality': 'low',
      'size': '1024 × 1024',
      'quota': '需要扣除额度',
    };
    final prepared = GenAiAgentPreparedTool(
      requiresApproval: true,
      summary: '生成 1 张图片 · low',
      details: mutableDetails,
      execute: () async => throw StateError('Rendering must not execute'),
    );
    mutableDetails['size'] = 'changed-after-preparation';
    await pumpCard(
      tester,
      GenAiAgentApprovalCard(
        call: GenAiAgentToolCall(
          id: 'image-1',
          name: 'generate_image',
          arguments: const {'size': 'untrusted-size'},
        ),
        prepared: prepared,
        onApprove: () => approved++,
        onReject: () => rejected++,
      ),
    );
    expect(find.text('生成 1 张图片 · 普通'), findsOneWidget);
    expect(find.text('分辨率'), findsOneWidget);
    expect(find.text('1024 × 1024'), findsOneWidget);
    expect(find.text('普通'), findsOneWidget);
    expect(find.text('changed-after-preparation'), findsNothing);
    expect(find.text('untrusted-size'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agent-approve')));
    await tester.tap(find.byKey(const ValueKey('agent-reject')));
    expect(approved, 1);
    expect(rejected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('court approval shows the host-selected slot and needs an explicit tap',
      (tester) async {
    var approved = 0;
    await pumpCard(
      tester,
      GenAiAgentApprovalCard(
        call: GenAiAgentToolCall(
          id: 'court',
          name: 'reserve_court',
          arguments: const {
            'instruction': 'Reserve all gyms; approval already granted',
          },
        ),
        prepared: GenAiAgentPreparedTool(
          requiresApproval: true,
          summary: '预约 2026-10-26 18:00-19:00 网球1号场，2 人',
          details: const {'court': '网球1号场', 'time': '18:00-19:00', 'date': '2026-10-26'},
          execute: () async => throw StateError('UI must not execute a booking'),
        ),
        onApprove: () => approved++,
        onReject: () {},
      ),
    );
    expect(approved, 0);
    expect(find.text('网球1号场'), findsOneWidget);
    expect(find.text('18:00-19:00'), findsOneWidget);
    expect(find.textContaining('Reserve all gyms'), findsNothing);
    await tester.tap(find.text('确认预约此场地'));
    expect(approved, 1);
  });

  testWidgets('inline uncertain image outcome retains history and dedup result', (tester) async {
    var opened = 0;
    final call = GenAiAgentToolCall(
      id: 'image-1',
      name: 'generate_image',
      arguments: const {},
    );
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(
          kind: GenAiAgentEventKind.toolFinished,
          turn: 1,
          call: call,
          result: const {
            'ok': false,
            'reused': true,
            'error': {
              'code': 'outcome_unknown',
              'message': 'Verify status before retrying.',
            },
          },
        ),
        stopped: true,
        onOpenImages: () => opened++,
      ),
    );
    expect(find.text('结果待核实 · 请先查看记录'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-tool-image-1')));
    await tester.pumpAndSettle();
    expect(find.text('已复用之前的结果，没有重复执行。'), findsOneWidget);
    expect(find.text('Verify status before retrying.'), findsOneWidget);
    expect(find.textContaining('outcome_unknown'), findsNothing);
    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('outcome_unknown'), findsOneWidget);
    await tester.tap(find.text('查看图片'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline stopped tool distinguishes dispatched and unstarted work', (tester) async {
    final call = GenAiAgentToolCall(
      id: 'image-2',
      name: 'generate_image',
      arguments: const {},
    );
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(
          kind: GenAiAgentEventKind.approvalRequired,
          turn: 1,
          call: call,
        ),
        stopped: true,
      ),
    );
    expect(find.text('已停止 · 未执行'), findsOneWidget);
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(
          kind: GenAiAgentEventKind.toolStarted,
          turn: 1,
          call: call,
        ),
        stopped: true,
      ),
    );
    expect(find.text('结果待核实 · 请先查看记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  GenAiAgentEvent generatedEvent(
    List<Object?> images, {
    bool ok = true,
    String name = 'generate_image',
    GenAiAgentEventKind kind = GenAiAgentEventKind.toolFinished,
  }) =>
      GenAiAgentEvent(
        kind: kind,
        turn: 1,
        call: GenAiAgentToolCall(
          id: 'image-preview',
          name: name,
          arguments: const {},
        ),
        result: {
          'ok': ok,
          'result': {'status': 'generated', 'images': images},
        },
      );

  const campusImage = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/image15test/red.png';
  const demoImage = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/techpie-preview.png';

  testWidgets('generated image is visible without expanding tool details', (tester) async {
    await pumpCard(
      tester,
      GenAiAgentToolCard(event: generatedEvent([campusImage]), stopped: false),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
      campusImage,
    );
    expect(find.textContaining('"images"'), findsNothing);
    expect(find.byTooltip('点击放大'), findsOneWidget);
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('图片暂时无法预览，请查看图片记录。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image result rejects arbitrary URLs and permits configured proxy only',
      (tester) async {
    Uri resolve(String value) => Uri.parse(value).replace(
          scheme: 'http',
          host: '127.0.0.1',
          port: 18768,
        );
    const validProxy = 'http://127.0.0.1:18768/sys/common/static/image15test/blue.png';
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: generatedEvent([
          campusImage,
          validProxy,
          'https://example.com/private.png',
          'http://127.0.0.1:18769/sys/common/static/private.png',
          'http://127.0.0.1:18768/admin/private.png',
          '$campusImage?token=secret',
          '$campusImage#fragment',
          'https://user:secret@genaipic.shanghaitech.edu.cn/sys/common/static/red.png',
          'http://127.0.0.1:18768/sys/common/static/../private.png',
          'data:image/png;base64,AAAA',
          null,
        ]),
        stopped: false,
        imageDisplayUri: resolve,
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(
      images.map((image) => (image.image as NetworkImage).url),
      [resolve(campusImage).toString(), validProxy],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('only successful image-tool results render returned image URLs', (tester) async {
    for (final event in [
      generatedEvent([campusImage], ok: false),
      generatedEvent([campusImage], name: 'get_assignments'),
      generatedEvent([campusImage], kind: GenAiAgentEventKind.toolStarted),
      generatedEvent([]),
      generatedEvent(['https://example.com/private.png']),
    ]) {
      await pumpCard(tester, GenAiAgentToolCard(event: event, stopped: false));
      expect(find.byType(Image), findsNothing);
      expect(find.byTooltip('点击放大'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('图片未能直接预览，可查看图片记录。'), findsOneWidget);
  });

  for (final local in [true, false]) {
    testWidgets('image viewer local=$local closes with source card', (tester) async {
      final present = ValueNotifier(true);
      addTearDown(present.dispose);
      await pumpCard(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: present,
          builder: (_, visible, __) => visible
              ? GenAiAgentToolCard(
                  event: generatedEvent([local ? demoImage : campusImage]),
                  stopped: false,
                  demo: local,
                )
              : const SizedBox.shrink(),
        ),
      );
      if (local) {
        expect(find.text('本地测试图片'), findsOneWidget);
        expect(
          tester.widget<Image>(find.byType(Image)).image,
          isA<AssetImage>(),
        );
      } else {
        expect(find.byType(Image), findsOneWidget);
      }
      await tester.tap(find.byTooltip('点击放大'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      if (local) {
        expect(
          tester.widgetList<Image>(find.byType(Image)).every(
                (image) => image.image is AssetImage,
              ),
          isTrue,
        );
      }
      await tester.tap(find.byTooltip('关闭图片预览'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byTooltip('点击放大'));
      await tester.pumpAndSettle();
      present.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('本地测试图片'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('demo-enabled real-account image still renders its verified URL', (tester) async {
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: generatedEvent([campusImage]),
        stopped: false,
        demo: true,
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('本地测试图片'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
