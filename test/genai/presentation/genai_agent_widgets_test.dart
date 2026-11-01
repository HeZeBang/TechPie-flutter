import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_agent_contract.dart';
import 'package:techpie/features/genai/presentation/genai_activity_line.dart';
import 'package:techpie/features/genai/presentation/genai_agent_widgets.dart';
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/genai_theme.dart';
import 'package:techpie/features/genai/presentation/genai_thinking_view.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_code_font.dart';

void main() {
  Finder genAiIcon(GenAiGlyph glyph) => find.byWidgetPredicate(
        (widget) => widget is GenAiIcon && widget.glyph == glyph,
      );

  Finder stepDots() => find.byWidgetPredicate(
        (widget) =>
            widget is Positioned &&
            widget.left == -24 &&
            widget.top == 16 &&
            widget.width == 6 &&
            widget.height == 6,
      );

  Finder railDecoration() => find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border is BorderDirectional,
      );

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

  testWidgets('disclosure keeps a plain body by default and dots each step on the rail',
      (tester) async {
    Future<void> show({required bool steps}) => tester.pumpWidget(
          MaterialApp(
            theme: genAiTheme(ThemeData()),
            home: Scaffold(
              body: GenAiDisclosure(
                leading: const GenAiIcon(GenAiGlyph.tools),
                title: '处理过程 · 2 个步骤',
                steps: steps,
                initiallyExpanded: true,
                children: const [Text('step one'), Text('step two')],
              ),
            ),
          ),
        );

    await show(steps: false);
    expect(find.text('step one'), findsOneWidget);
    expect(stepDots(), findsNothing);
    expect(railDecoration(), findsOneWidget);

    await show(steps: true);
    expect(find.text('step one'), findsOneWidget);
    expect(find.text('step two'), findsOneWidget);
    expect(stepDots(), findsNWidgets(2));
    final railLeft = tester.getTopLeft(railDecoration()).dx;
    for (var index = 0; index < 2; index++) {
      final dot = stepDots().at(index);
      expect(tester.getSize(dot), const Size(6, 6));
      final rect = tester.getRect(dot);
      expect(rect.center.dx, closeTo(railLeft, .5));
      expect(
        rect.top - tester.getTopLeft(find.text(index == 0 ? 'step one' : 'step two')).dy,
        closeTo(9, .5),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished thinking floors seconds at one and omits an unknown duration',
      (tester) async {
    Future<void> show({
      String reasoning = 'reasoning',
      bool thinking = false,
      int? durationMs,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            theme: genAiTheme(ThemeData()),
            home: Scaffold(
              body: GenAiThinkingView(
                key: UniqueKey(),
                reasoning: reasoning,
                isThinking: thinking,
                durationMs: durationMs,
              ),
            ),
          ),
        );

    await show(durationMs: 900);
    expect(find.text('已完成思考 · 1 秒'), findsOneWidget);
    await show(durationMs: 2800);
    expect(find.text('已完成思考 · 2 秒'), findsOneWidget);
    await show(durationMs: 9000);
    expect(find.text('已完成思考 · 9 秒'), findsOneWidget);
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
    expect(find.text('正在重试请求'), findsOneWidget);
    await show(false);
    expect(find.text('正在重试请求'), findsNothing);
    expect(find.text('请求格式有误'), findsOneWidget);
    await show(false, id: 'restored');
    await tester.tap(find.byKey(const ValueKey('agent-tool-activity-heading')));
    await tester.pumpAndSettle();
    expect(find.text('正在重试请求'), findsNothing);
    expect(find.text('请求格式有误'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity heading counts steps and appends live, stopped and failure states',
      (tester) async {
    final ok = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 1,
      call: GenAiAgentToolCall(
        id: 'time',
        name: 'get_current_time',
        arguments: const {},
      ),
      result: const {'ok': true},
    );
    final failed = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 2,
      call: GenAiAgentToolCall(
        id: 'semester',
        name: 'get_semesters',
        arguments: const {},
      ),
      result: const {'ok': false},
    );
    Future<void> show({required bool running, required bool stopped}) => pumpCard(
          tester,
          GenAiAgentToolActivity(
            events: [ok, failed],
            activity: [ok, failed],
            running: running,
            stopped: stopped,
          ),
        );

    await show(running: true, stopped: false);
    expect(find.text('查看当前时间与查看学期 · 2 个步骤 · 进行中'), findsOneWidget);
    expect(stepDots(), findsNWidgets(2));

    await show(running: false, stopped: false);
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间与查看学期 · 2 个步骤 · 有未完成项'), findsOneWidget);
    expect(genAiIcon(GenAiGlyph.info), findsWidgets);

    await show(running: false, stopped: true);
    await tester.pumpAndSettle();
    expect(find.text('查看当前时间与查看学期 · 2 个步骤 · 已停止'), findsOneWidget);

    final success = GenAiAgentEvent(
      kind: GenAiAgentEventKind.toolFinished,
      turn: 3,
      call: GenAiAgentToolCall(
        id: 'sources',
        name: 'web_search',
        arguments: const {},
      ),
      result: const {'ok': true},
    );
    await pumpCard(
      tester,
      GenAiAgentToolActivity(
        events: [success],
        activity: [success],
        running: false,
        stopped: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('联网搜索 · 1 个步骤'), findsOneWidget);
    expect(genAiIcon(GenAiGlyph.checkCircle), findsOneWidget);
    expect(stepDots(), findsOneWidget);
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
    final thoughts = find.text('已完成思考');
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
    expect(find.text('确认生成图片'), findsOneWidget);
    expect(find.text('确认后才会执行，可能扣除学校额度'), findsOneWidget);
    expect(genAiIcon(GenAiGlyph.image), findsOneWidget);
    expect(find.text('分辨率'), findsOneWidget);
    expect(find.text('1024 × 1024'), findsOneWidget);
    expect(find.text('普通'), findsOneWidget);
    expect(find.text('changed-after-preparation'), findsNothing);
    expect(find.text('untrusted-size'), findsNothing);
    final card = tester.widget<Container>(find.byKey(const ValueKey('agent-approval')));
    expect(card.padding, const EdgeInsets.all(17));
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(13));
    final palette = GenAiPalette.of(tester.element(find.byKey(const ValueKey('agent-approval'))));
    expect(decoration.color, palette.raised);
    expect((decoration.border! as Border).top.color, palette.line);
    final heading = tester.widget<Text>(find.text('确认生成图片'));
    expect(heading.style?.fontSize, 15);
    expect(heading.style?.fontWeight, FontWeight.w600);
    final value = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '1024 × 1024',
      ),
    );
    expect(value.style?.fontSize, 12);
    final label = tester.widget<Text>(find.text('分辨率'));
    expect(label.style?.fontSize, 11);
    expect(label.style?.color, palette.muted);
    expect(find.widgetWithText(OutlinedButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认生成'), findsOneWidget);
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
    expect(genAiIcon(GenAiGlyph.calendar), findsOneWidget);
    // The slip composes 场地 from the prepared sport and court.
    expect(find.text('网球 · 网球1号场'), findsOneWidget);
    expect(find.text('2026-10-26'), findsOneWidget);
    expect(find.text('18:00-19:00'), findsOneWidget);
    expect(find.text('以场馆确认为准'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // Booking order: 场地, 日期, 时段, 费用, then extra fields.
    final labels = ['场地', '日期', '时段', '费用', '人数'];
    for (var index = 0; index < labels.length - 1; index++) {
      expect(
        tester.getTopLeft(find.text(labels[index])).dy,
        lessThan(tester.getTopLeft(find.text(labels[index + 1])).dy),
      );
    }
    expect(find.textContaining('Reserve all gyms'), findsNothing);
    await tester.tap(find.text('确认这一场'));
    expect(approved, 1);
  });

  testWidgets('booking approval turns into a confirmed notice after the decision', (tester) async {
    var approved = 0;
    final call = GenAiAgentToolCall(
      id: 'court',
      name: 'reserve_court',
      arguments: const {},
    );
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
        'result': {
          'status': 'booked',
          'success': true,
          'date': '2026-10-31',
          'court_number': 3,
        },
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
    expect(genAiIcon(GenAiGlyph.check), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '确认这一场'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected booking turns into a cancelled notice without submitting', (tester) async {
    var rejected = 0;
    final call = GenAiAgentToolCall(
      id: 'court',
      name: 'reserve_court',
      arguments: const {},
    );
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
      GenAiAgentToolActivity(
        events: [decided],
        activity: [decided],
        running: true,
        stopped: false,
      ),
    );
    expect(find.byKey(const ValueKey('agent-approval')), findsNothing);
    expect(find.text('已取消预约'), findsOneWidget);
    expect(find.text('没有提交任何预约。'), findsOneWidget);
    expect(genAiIcon(GenAiGlyph.close), findsOneWidget);
    expect(find.textContaining('declined'), findsNothing);
    expect(tester.takeException(), isNull);
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

  testWidgets('tool card keeps a muted summary line above a soft monospaced technical box',
      (tester) async {
    await pumpCard(
      tester,
      GenAiAgentToolCard(
        event: GenAiAgentEvent(
          kind: GenAiAgentEventKind.toolFinished,
          turn: 1,
          call: GenAiAgentToolCall(
            id: 'semester',
            name: 'get_semesters',
            arguments: const {},
          ),
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
    final context = tester.element(find.text('查看学期'));
    final palette = GenAiPalette.of(context);
    final title = tester.widget<Text>(find.text('查看学期'));
    expect(title.style?.fontSize, 12);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(title.style?.color, Theme.of(context).colorScheme.onSurface);
    final subtitle = tester.widget<Text>(find.text('已完成'));
    expect(subtitle.style?.fontSize, 12);
    expect(subtitle.style?.color, palette.muted);
    final summary = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(summary.data, '2026–2027 秋季学期');
    expect(summary.style?.fontSize, 12);
    expect(summary.style?.color, palette.muted);
    // At reading width the status and summary share the second header row.
    expect(
      tester.getCenter(find.text('已完成')).dy,
      closeTo(tester.getCenter(find.text('2026–2027 秋季学期')).dy, 1),
    );
    expect(find.text('2026–2027 秋季学期'), findsOneWidget);
    await tester.tap(find.text('查看学期'));
    await tester.pumpAndSettle();
    expect(find.text('技术详情'), findsOneWidget);
    // Expanding must not repeat or push the summary below the technical body.
    expect(find.text('2026–2027 秋季学期'), findsOneWidget);
    await tester.tap(find.text('技术详情'));
    await tester.pumpAndSettle();
    final technical = tester.widget<SelectableText>(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.style?.fontFamily == kGenAiMonospaceFamily,
      ),
    );
    expect(technical.style?.fontFamily, kGenAiMonospaceFamily);
    final technicalFinder = find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.style?.fontFamily == kGenAiMonospaceFamily,
    );
    // The header summary stays above the expanded technical box.
    expect(
      tester.getTopLeft(find.text('2026–2027 秋季学期')).dy,
      lessThan(tester.getTopLeft(technicalFinder).dy),
    );
    final softBox = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == palette.soft,
    );
    expect(softBox, findsOneWidget);
    final decoration = tester.widget<Container>(softBox).decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));
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
      if (event.result?['ok'] == false) expect(find.text('查看图片'), findsNothing);
      expect(find.byTooltip('点击放大'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('图片未能直接预览，可查看图片记录。'), findsOneWidget);
  });

  testWidgets('image viewer closes with source card', (tester) async {
    final present = ValueNotifier(true);
    addTearDown(present.dispose);
    await pumpCard(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: present,
        builder: (_, visible, __) => visible
            ? GenAiAgentToolCard(
                event: generatedEvent([campusImage]),
                stopped: false,
              )
            : const SizedBox.shrink(),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byTooltip('点击放大'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('关闭图片预览'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byTooltip('点击放大'));
    await tester.pumpAndSettle();
    present.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
