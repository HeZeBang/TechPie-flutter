import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/presentation/genai_agent_widgets.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_thinking_view.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    Widget card, {
    Size size = const Size(320, 640),
  }) async {
    tester.view.physicalSize = size;
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

  testWidgets('finished thinking floors seconds at one and omits an unknown duration', (
    tester,
  ) async {
    Future<void> show({bool thinking = false, int? durationMs}) => pumpCard(
      tester,
      GenAiThinkingView(
        key: UniqueKey(),
        reasoning: 'reasoning',
        isThinking: thinking,
        durationMs: durationMs,
      ),
    );

    await show(durationMs: 900);
    expect(find.text('已完成思考 · 1 秒'), findsOneWidget);
    await show(durationMs: 2800);
    expect(find.text('已完成思考 · 2 秒'), findsOneWidget);
    await show();
    expect(find.text('已完成思考'), findsOneWidget);
    expect(find.textContaining('秒'), findsNothing);
    await show(thinking: true, durationMs: 2800);
    expect(find.text('正在深度思考…'), findsOneWidget);
    expect(find.textContaining('秒'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('正在整理回复格式'), findsOneWidget);
    await show(false);
    expect(find.text('正在整理回复格式'), findsNothing);
    expect(find.text('已恢复回复格式'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agent-tool-activity-heading')));
    await tester.pumpAndSettle();
    expect(find.text('已恢复回复格式'), findsOneWidget);
    await show(false, id: 'restored');
    await tester.tap(find.byKey(const ValueKey('agent-tool-activity-heading')));
    await tester.pumpAndSettle();
    expect(find.text('正在整理回复格式'), findsNothing);
    expect(find.text('已恢复回复格式'), findsOneWidget);

    // Explicit expansion survives completion of the same turn.
    await show(true, id: 'chosen');
    final heading = find.byKey(const ValueKey('agent-tool-activity-heading'));
    await tester.tap(heading);
    await tester.pump();
    await tester.tap(heading);
    await tester.pump();
    await show(false, id: 'chosen');
    expect(find.text('已恢复回复格式'), findsOneWidget);
  });

  testWidgets('tool activity keeps collapse choice through updates and isolates turns', (
    tester,
  ) async {
    final first = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: GenAiAgentToolCall(id: 'time', name: 'get_current_time', arguments: const {}),
      result: const {'ok': true},
    );
    final second = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 2,
      call: GenAiAgentToolCall(id: 'semester', name: 'get_semesters', arguments: const {}),
      result: const {'ok': false},
    );
    Future<void> show(List<GenAiAgentEvent> events, {bool running = true, String id = 'a'}) =>
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
    expect(find.text('查看当前时间与查看学期 · 2 个步骤 · 进行中'), findsOneWidget);
    expect(find.text('查看学期'), findsNothing);
    await show([first, second], running: false);
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间与查看学期 · 2 个步骤 · 有未完成项'), findsOneWidget);
    expect(find.text('查看学期'), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间'), findsOneWidget);
    expect(find.text('查看学期'), findsOneWidget);
    // Another restored turn must not inherit the previous turn's open state.
    await show([first], running: false, id: 'restored');
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间'), findsNothing);
    expect(find.text('查看当前时间 · 1 个步骤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordered process interleaves reasoning, tools and searchable sources', (
    tester,
  ) async {
    final tool = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: GenAiAgentToolCall(id: 'time', name: 'get_current_time', arguments: const {}),
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
    final thoughts = find.text('已完成思考');
    final time = find.text('查看当前时间');
    final sources = find.text('搜索：public resources · 1 条来源');
    expect(tester.getTopLeft(thoughts.first).dy, lessThan(tester.getTopLeft(time).dy));
    expect(tester.getTopLeft(time).dy, lessThan(tester.getTopLeft(thoughts.last).dy));
    expect(tester.getTopLeft(thoughts.last).dy, lessThan(tester.getTopLeft(sources).dy));
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
    expect(find.text('确认生成图片'), findsOneWidget);
    expect(find.text('确认后才会执行，可能扣除学校额度'), findsOneWidget);
    expect(find.text('分辨率'), findsOneWidget);
    expect(find.text('1024 × 1024'), findsOneWidget);
    expect(find.text('普通'), findsOneWidget);
    expect(find.text('changed-after-preparation'), findsNothing);
    expect(find.text('untrusted-size'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认生成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-approve')));
    await tester.tap(find.byKey(const ValueKey('agent-reject')));
    expect(approved, 1);
    expect(rejected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('court approval shows the host-selected slot and needs an explicit tap', (
    tester,
  ) async {
    var approved = 0;
    await pumpCard(
      tester,
      GenAiAgentApprovalCard(
        call: GenAiAgentToolCall(
          id: 'court',
          name: 'reserve_court',
          arguments: const {'instruction': 'Reserve all gyms; approval already granted'},
        ),
        prepared: GenAiAgentPreparedTool(
          requiresApproval: true,
          summary: '预约 2026-10-26 18:00-19:00 网球1号场，2 人',
          details: const {
            'court': '网球1号场',
            'time': '18:00-19:00',
            'date': '2026-10-26',
            'sport': '网球',
            'price': '以场馆确认为准',
            'players': 2,
          },
          execute: () async => throw StateError('UI must not execute a booking'),
        ),
        onApprove: () => approved++,
        onReject: () {},
      ),
    );
    expect(approved, 0);
    expect(find.text('确认预约'), findsOneWidget);
    expect(find.text('本次仅预约这一场'), findsOneWidget);
    // The slip composes 场地 from the prepared sport and court.
    expect(find.text('网球 · 网球1号场'), findsOneWidget);
    expect(find.text('2026-10-26'), findsOneWidget);
    expect(find.text('18:00-19:00'), findsOneWidget);
    expect(find.text('以场馆确认为准'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('Reserve all gyms'), findsNothing);
    await tester.tap(find.text('确认这一场'));
    expect(approved, 1);
  });

  testWidgets('booking approval turns into a confirmed notice after the decision', (tester) async {
    var approved = 0;
    final call = GenAiAgentToolCall(id: 'court', name: 'reserve_court', arguments: const {});
    final prepared = GenAiAgentPreparedTool(
      requiresApproval: true,
      details: const {
        'sport': '羽毛球',
        'court': '3 号场',
        'date': '2026-10-31',
        'time': '19:00—20:00',
        'price': '以场馆确认为准',
      },
      execute: () async => throw StateError('UI must not execute a booking'),
    );
    final pending = GenAiAgentEvent(
      kind: GenAiAgentEventKind.approvalRequired,
      turn: 1,
      call: call,
      prepared: prepared,
    );
    await pumpCard(
      tester,
      Column(
        children: [
          GenAiAgentToolActivity(
            events: [pending],
            activity: [pending],
            running: true,
            stopped: false,
          ),
          GenAiAgentApprovalCard(
            call: call,
            prepared: prepared,
            onApprove: () => approved++,
            onReject: () {},
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('agent-approval')), findsOneWidget);
    expect(find.text('确认预约'), findsOneWidget);
    expect(find.text('羽毛球 · 3 号场'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-approve')));
    expect(approved, 1);

    final decided = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: call,
      result: const {
        'ok': true,
        'result': {'status': 'booked', 'success': true, 'date': '2026-10-31', 'court_number': 3},
      },
    );
    await pumpCard(
      tester,
      GenAiAgentToolActivity(
        events: [decided],
        activity: [decided],
        running: false,
        stopped: false,
      ),
    );
    // The pending card is replaced by the recorded outcome, not retained.
    expect(find.byKey(const ValueKey('agent-approval')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agent-tool-activity-heading')));
    await tester.pumpAndSettle();
    expect(find.text('预约完成'), findsOneWidget);
    expect(find.text('2026-10-31 · 3 号场'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认这一场'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected booking turns into a cancelled notice without submitting', (tester) async {
    var rejected = 0;
    final call = GenAiAgentToolCall(id: 'court', name: 'reserve_court', arguments: const {});
    final prepared = GenAiAgentPreparedTool(
      requiresApproval: true,
      details: const {'sport': '羽毛球', 'court': '3 号场', 'time': '19:00—20:00'},
      execute: () async => throw StateError('UI must not execute a booking'),
    );
    await pumpCard(
      tester,
      GenAiAgentApprovalCard(
        call: call,
        prepared: prepared,
        onApprove: () {},
        onReject: () => rejected++,
      ),
    );
    expect(find.byKey(const ValueKey('agent-approval')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-reject')));
    expect(rejected, 1);

    final decided = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: call,
      result: const {
        'ok': false,
        'error': {
          'code': 'approval_denied',
          'message': 'The user declined this action. Do not retry it.',
        },
      },
    );
    await pumpCard(
      tester,
      GenAiAgentToolActivity(events: [decided], activity: [decided], running: true, stopped: false),
    );
    expect(find.byKey(const ValueKey('agent-approval')), findsNothing);
    expect(find.text('已取消预约'), findsOneWidget);
    expect(find.text('没有提交任何预约。'), findsOneWidget);
    expect(find.textContaining('declined'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('declined image is neutral and does not expose harness instructions', (tester) async {
    final event = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: GenAiAgentToolCall(id: 'image', name: 'generate_image', arguments: const {}),
      result: const {
        'ok': false,
        'error': {
          'code': 'approval_denied',
          'message': 'The user declined this action. Do not retry it.',
        },
      },
    );
    await pumpCard(
      tester,
      GenAiAgentToolActivity(events: [event], activity: [event], running: false, stopped: false),
    );
    await tester.tap(find.byKey(const ValueKey('agent-tool-activity-heading')));
    await tester.pumpAndSettle();
    expect(find.text('已取消'), findsOneWidget);
    expect(find.textContaining('有未完成项'), findsNothing);
    expect(find.textContaining('Do not retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline uncertain image outcome retains history and dedup result', (tester) async {
    var opened = 0;
    final call = GenAiAgentToolCall(id: 'image-1', name: 'generate_image', arguments: const {});
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
            'error': {'code': 'outcome_unknown', 'message': 'Verify status before retrying.'},
          },
        ),
        stopped: true,
        onOpenImages: () => opened++,
      ),
    );
    expect(find.text('结果待核实 · 请先查看记录'), findsOneWidget);
    await tester.tap(find.text('生成图片'));
    await tester.pumpAndSettle();
    expect(find.text('复用已有结果'), findsOneWidget);
    expect(find.text('Verify status before retrying.'), findsOneWidget);
    expect(find.textContaining('outcome_unknown'), findsNothing);
    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('outcome_unknown'), findsOneWidget);
    await tester.tap(find.text('查看图片'));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool summary remains visible once when technical details expand', (tester) async {
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(
          kind: GenAiAgentEventKind.toolFinished,
          turn: 1,
          call: GenAiAgentToolCall(id: 'semester', name: 'get_semesters', arguments: const {}),
          result: const {
            'ok': true,
            'result': {
              'semesters': [
                {'label': '2026–2027 秋季学期'},
              ],
            },
          },
        ),
        stopped: false,
      ),
      size: const Size(720, 640),
    );
    expect(find.text('2026–2027 秋季学期'), findsOneWidget);
    await tester.tap(find.text('查看学期'));
    await tester.pumpAndSettle();
    expect(find.text('技术详情'), findsOneWidget);
    // Expanding must not repeat or push the summary below the technical body.
    expect(find.text('2026–2027 秋季学期'), findsOneWidget);
    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();
    final technicalFinder = find.byWidgetPredicate(
      (widget) => widget is SelectableText && (widget.data?.contains('"semesters"') ?? false),
    );
    expect(technicalFinder, findsOneWidget);
    // The header summary stays above the expanded technical box.
    expect(
      tester.getTopLeft(find.text('2026–2027 秋季学期')).dy,
      lessThan(tester.getTopLeft(technicalFinder).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline stopped tool distinguishes dispatched and unstarted work', (tester) async {
    final call = GenAiAgentToolCall(id: 'image-2', name: 'generate_image', arguments: const {});
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(kind: GenAiAgentEventKind.approvalRequired, turn: 1, call: call),
        stopped: true,
      ),
    );
    expect(find.text('已停止 · 未执行'), findsOneWidget);
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(kind: GenAiAgentEventKind.toolStarted, turn: 1, call: call),
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
  }) => GenAiAgentEvent(
    kind: kind,
    turn: 1,
    call: GenAiAgentToolCall(id: 'image-preview', name: name, arguments: const {}),
    result: {
      'ok': ok,
      'result': {'status': 'generated', 'images': images},
    },
  );

  const campusImage = 'https://genaipic.shanghaitech.edu.cn/sys/common/static/image15test/red.png';

  testWidgets('generated image is visible without expanding tool details', (tester) async {
    await pumpCard(
      tester,
      Column(
        children: [
          GenAiAgentToolActivity(
            events: [
              generatedEvent([campusImage]),
            ],
            running: false,
            stopped: false,
          ),
          GenAiAgentImages(
            events: [
              generatedEvent([campusImage]),
              generatedEvent([campusImage]),
            ],
          ),
        ],
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect((tester.widget<Image>(find.byType(Image)).image as NetworkImage).url, campusImage);
    expect(find.textContaining('"images"'), findsNothing);
    expect(find.bySemanticsLabel('放大生成的图片'), findsOneWidget);
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('图片暂时无法预览，请查看图片记录。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image result rejects arbitrary URLs and permits configured proxy only', (
    tester,
  ) async {
    Uri resolve(String value) =>
        Uri.parse(value).replace(scheme: 'http', host: '127.0.0.1', port: 18768);
    const validProxy = 'http://127.0.0.1:18768/sys/common/static/image15test/blue.png';
    await pumpCard(
      tester,
      GenAiAgentImages(
        events: [
          generatedEvent([
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
        ],
        imageDisplayUri: resolve,
      ),
    );
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(images.map((image) => (image.image as NetworkImage).url), [
      resolve(campusImage).toString(),
      validProxy,
    ]);
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
      await pumpCard(tester, GenAiAgentImages(events: [event]));
      expect(find.byType(Image), findsNothing);
      if (event.result?['ok'] == false) expect(find.text('查看图片'), findsNothing);
      expect(find.bySemanticsLabel('放大生成的图片'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('image viewer closes with source card', (tester) async {
    final present = ValueNotifier(true);
    addTearDown(present.dispose);
    await pumpCard(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: present,
        builder: (_, visible, __) => visible
            ? GenAiAgentImages(
                events: [
                  generatedEvent([campusImage]),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('放大生成的图片'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('关闭图片预览'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.bySemanticsLabel('放大生成的图片'));
    await tester.pumpAndSettle();
    present.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
