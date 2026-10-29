import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

import '../support/fakes.dart';
import '../support/journal_server.dart';
import '../support/workspace_server.dart';

void main() {
  testWidgets('reopening variable-height history starts at the latest message', (tester) async {
    final server = JournalServer();
    server.rows['long'] = List.generate(
      18,
      (i) => {
        'id': 'row-$i',
        'question': i == 17
            ? 'Final saved question'
            : List.filled(100 + i * 13, 'Archive line $i').join('\n'),
        'answer': i == 17 ? 'Latest saved reply' : 'Archived reply $i',
        'aiType': 'Kimi-k3',
      },
    );
    final client = await JournalClient.create(server);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: client.workspace,
          login: (_) async => const GenAiCredential(token: FakeGenAiServer.token),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final opening = client.workspace.openConversation('long', GenAiCancellation());
    await tester.pumpAndSettle();
    await opening;
    await tester.pumpAndSettle();
    expect(find.text('Latest saved reply'), findsOneWidget);
    expect(
      tester
          .getRect(find.text('Latest saved reply'))
          .overlaps(tester.getRect(find.byKey(const ValueKey('genai-thread')))),
      true,
    );
    expect(tester.takeException(), isNull);
  });

  Future<TestGenAiWorkspace> show(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
    bool connected = true,
    double scale = 1,
    double keyboard = 0,
    Duration delay = const Duration(milliseconds: 1),
    GenAiAudioRecorder? audioRecorder,
    GenAiPicker? picker,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final demo = await TestGenAiWorkspace.create(connected: connected, chunkDelay: delay);
    addTearDown(demo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: AdaptiveFeedbackHost(
            key: adaptiveFeedbackHostKey,
            child: child!,
          ),
        ),
        home: GenAiWorkspace(
          controller: demo.workspace,
          audioRecorder: audioRecorder,
          picker: picker,
          login: (_) async => const GenAiCredential(token: FakeGenAiServer.token),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('message actions confirm, cancel and recover on $size', (tester) async {
      final demo = await show(tester, size: size, delay: Duration.zero);
      for (final prompt in ['first', 'second']) {
        final sending = demo.workspace.send(prompt);
        await tester.pumpAndSettle();
        await sending;
      }
      final group = demo.workspace.groupId;
      final target = demo.workspace.turns.last.id;
      final menu = find.byKey(ValueKey('genai-turn-menu-$target'));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除此轮及后续'));
      await tester.pumpAndSettle();
      expect(find.text('将永久删除 1 轮对话及其工具记录，所有设备同步生效。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(demo.workspace.turns, hasLength(2));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑并重新发送'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'edited',
      );
      await tester.tap(find.text('重新发送'));
      await tester.pumpAndSettle();
      expect(demo.workspace.turns.map((t) => t.prompt), ['first', 'edited']);
      demo.workspace.newConversation();
      final opening = demo.workspace.openConversation(group, GenAiCancellation());
      await tester.pumpAndSettle();
      await opening;
      expect(demo.workspace.turns.map((t) => t.prompt), ['first', 'edited']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final checkSync in [true, false]) {
    testWidgets(
        'uncertain deletion recovers via ${checkSync ? 'sync button' : 'current history item'}',
        (tester) async {
      final demo = await show(
        tester,
        size: checkSync ? const Size(390, 844) : const Size(1280, 900),
        delay: Duration.zero,
      );
      for (final prompt in ['recovery retained', 'recovery removed']) {
        final sending = demo.workspace.send(prompt);
        await tester.pumpAndSettle();
        await sending;
      }
      final group = demo.workspace.groupId;
      demo.backend.loseDeleteResponse = true;
      final menu = find.byKey(ValueKey('genai-turn-menu-${demo.workspace.turns.last.id}'));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除此轮及后续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(demo.workspace.archiveFailure, isNotNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(demo.workspace.turns, hasLength(2));
      await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'unsent draft');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('genai-send')));
      await tester.pumpAndSettle();
      expect(find.text('unsent draft'), findsOneWidget);
      expect(demo.workspace.turns, hasLength(2));
      if (checkSync) {
        await tester.tap(find.text('检查同步'));
      } else {
        await tester.tap(find.byTooltip('刷新历史'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('recovery retained').first);
      }
      await tester.pumpAndSettle();
      expect(demo.workspace.groupId, group);
      expect(demo.workspace.archiveFailure, isNull);
      expect(demo.workspace.turns.single.prompt, 'recovery retained');
      expect(find.text('检查同步'), findsNothing);
      expect(find.text('unsent draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed keyboard edit retains replacement and separate composer attachments',
      (tester) async {
    final demo = await show(tester, delay: Duration.zero);
    final sending = demo.workspace.send('original');
    await tester.pumpAndSettle();
    await sending;
    await demo.workspace.addImageAttachment('draft.png', [1, 2, 3]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('genai-prompt')), 'composer draft');
    demo.backend.loseDeleteResponse = true;
    await tester.tap(find.byKey(ValueKey('genai-turn-menu-${demo.workspace.turns.single.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑并重新发送'));
    await tester.pumpAndSettle();
    final editor = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(editor, 'valuable replacement');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(demo.workspace.archiveFailure, isNotNull);
    expect(find.text('valuable replacement'), findsOneWidget);
    expect(find.text('composer draft'), findsOneWidget);
    expect(demo.workspace.attachments.single.name, 'draft.png');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('reopening saved vision chat builds network thumbnails and image viewer',
      (tester) async {
    final demo = await show(tester, delay: Duration.zero);
    await demo.workspace.addImageAttachment('red.png', [1, 2, 3]);
    await demo.workspace.addImageAttachment('blue.png', [4, 5, 6]);
    final sending = demo.workspace.send('Saved vision thumbnails');
    await tester.pumpAndSettle();
    await sending;
    final urls = demo.workspace.turns.single.attachedImageUrls;
    final id = demo.workspace.groupId;
    demo.workspace.newConversation();
    // Pump server recovery in the widget's fake-async zone.
    final opening = demo.workspace.openConversation(id, GenAiCancellation());
    await tester.pumpAndSettle();
    await opening;
    final thumbnails = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is NetworkImage &&
          urls.contains((widget.image as NetworkImage).url),
    );
    expect(thumbnails, findsNWidgets(urls.length));
    await tester.ensureVisible(thumbnails.first);
    await tester.pumpAndSettle();
    await tester.tap(thumbnails.first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(thumbnails, findsNWidgets(urls.length + 1));
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('typed chat sends only on submission and renders the reply', (tester) async {
    final demo = await show(tester);
    expect(find.text('GenAI'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '帮我制定学习计划',
    );
    await tester.pump();
    expect(demo.workspace.turns, isEmpty);
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(find.byKey(const ValueKey('genai-copy-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login connects and logout clears the conversation', (tester) async {
    final demo = await show(tester, connected: false);
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-connect')));
    await tester.pumpAndSettle();
    expect(demo.workspace.connected, isTrue);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开 GenAI'));
    await tester.pumpAndSettle();
    expect(find.text('连接你的校园 AI'), findsOneWidget);
    expect(demo.sessions.session, isNull);
  });

  testWidgets('bound IDS without a school ID offers identity resolution', (tester) async {
    final demo = await TestGenAiWorkspace.create(connected: false);
    addTearDown(demo.dispose);
    await demo.sessions.setOwner(null);
    var connects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: demo.workspace,
          campusBound: true,
          login: (_) async => throw StateError('manual login must not run'),
          onCampusLogin: () => connects++,
          onBindCampus: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('校园身份待同步'), findsOneWidget);
    expect(find.text('绑定校园账号'), findsNothing);
    expect(find.text('管理校园账号'), findsNothing);
    await tester.tap(find.text('使用现有 IDS 会话连接'));
    await tester.pump();
    expect(connects, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact navigation opens history, image creation and account usage', (tester) async {
    await show(tester, size: const Size(674, 1000));
    await tester.tap(find.byTooltip('会话记录'));
    await tester.pumpAndSettle();
    expect(find.text('搜索对话'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图片创作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-image-prompt')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('GenAI 账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用量统计'));
    await tester.pumpAndSettle();
    expect(find.text('免费额度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape preserves draft and stopped turn retry expires after a new turn',
      (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 20));
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      List.filled(50, 'test stop').join(' '),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    for (var step = 0; step < 50 && demo.workspace.turns.single.answer.isEmpty; step++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(demo.workspace.sending, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      'Keep this next question',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('genai-prompt'))).controller!.text,
      'Keep this next question',
    );
    expect(demo.workspace.contextUsage, isNull);
    expect(demo.workspace.turns.single.phase, GenAiChatPhase.cancelled);
    expect(demo.workspace.turns.single.answer, isNotEmpty);
    expect(find.byKey(const ValueKey('genai-retry-0')), findsOneWidget);

    final sending = demo.workspace.send('Continue with another question');
    // Network delay timers can outlive a settled frame after layout changes.
    for (var step = 0; step < 500 && demo.workspace.sending; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(demo.workspace.sending, isFalse);
    await sending;
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('genai-thread')),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    expect(demo.workspace.turns, hasLength(2));
    expect(demo.workspace.turns.first.phase, GenAiChatPhase.cancelled);
    expect(demo.workspace.turns.last.phase, GenAiChatPhase.completed);
    expect(find.byKey(const ValueKey('genai-copy-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-retry-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('streaming respects reading position until return to latest', (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 10));
    final first = demo.workspace.send(List.generate(40, (i) => 'Paragraph $i.\n').join('\n'));
    for (var step = 0; step < 500 && demo.workspace.sending; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(demo.workspace.sending, isFalse);
    await first;
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byKey(const ValueKey('genai-thread')));
    final scroll = list.controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(200));

    final next = demo.workspace.send('Another Markdown example');
    await tester.pump(const Duration(milliseconds: 80));
    scroll.jumpTo(200);
    for (var step = 0; step < 500 && demo.workspace.sending; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(demo.workspace.sending, isFalse);
    await next;
    await tester.pumpAndSettle();
    expect(scroll.offset, 200);
    expect(find.byKey(const ValueKey('genai-scroll-latest')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-scroll-latest')));
    await tester.pumpAndSettle();
    expect(scroll.position.extentBefore, lessThan(1));
    expect(find.byKey(const ValueKey('genai-scroll-latest')), findsNothing);
    expect(find.byKey(const ValueKey('genai-context-status')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new conversation and account switch remove drafts and previous output',
      (tester) async {
    final demo = await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      'private draft',
    );
    await demo.sessions.setOwner(ownerB);
    await tester.pumpAndSettle();
    expect(find.text('private draft'), findsNothing);
    expect(find.byKey(const ValueKey('genai-prompt')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('IME composition and Shift Enter do not submit a message', (tester) async {
    final demo = await show(tester);
    final input = find.byKey(const ValueKey('genai-prompt'));
    await tester.enterText(input, 'hello');
    final controller = tester.widget<TextField>(input).controller!;
    controller.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(demo.workspace.turns, isEmpty);
    controller.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(demo.workspace.turns, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.length, 1);
  });

  testWidgets('native workspace hides unavailable audio and file actions', (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '测试语音播报',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    final ttsButton = find.byKey(const ValueKey('genai-tts-0'));
    expect(ttsButton, findsNothing);
    expect(find.byKey(const ValueKey('genai-audio-stt')), findsNothing);
    expect(find.byKey(const ValueKey('genai-upload-file')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('microphone recording shows timer and waveform and can be cancelled', (tester) async {
    final recorder = FakeGenAiAudioRecorder();
    await show(tester, audioRecorder: recorder);

    final micButton = find.byKey(const ValueKey('genai-audio-stt'));
    expect(micButton, findsOneWidget);

    await tester.tap(micButton);
    await tester.pump();
    expect(recorder.startCalls, 1);
    expect(recorder.isRecording, isTrue);

    expect(
      find.byKey(const ValueKey('genai-recording-duration')),
      findsOneWidget,
    );
    expect(find.text('正在录音 00:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('正在录音 00:02'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('genai-cancel-recording')));
    await tester.pumpAndSettle();

    expect(recorder.cancelCalls, 1);
    expect(recorder.isRecording, isFalse);
    expect(
      find.byKey(const ValueKey('genai-recording-duration')),
      findsNothing,
    );
  });

  testWidgets('finishing microphone recording stops recorder and transcribes audio to draft',
      (tester) async {
    final recorder = FakeGenAiAudioRecorder(
      recordedBytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    await show(tester, audioRecorder: recorder);

    await tester.tap(find.byKey(const ValueKey('genai-audio-stt')));
    await tester.pump();
    expect(recorder.isRecording, isTrue);

    await tester.tap(find.byKey(const ValueKey('genai-finish-recording')));
    await tester.pumpAndSettle();

    expect(recorder.stopCalls, 1);
    expect(recorder.isRecording, isFalse);
    expect(
      find.byKey(const ValueKey('genai-recording-duration')),
      findsNothing,
    );

    final promptFinder = find.byKey(const ValueKey('genai-prompt'));
    final textField = tester.widget<TextField>(promptFinder);
    expect(textField.controller!.text, '你好，这是通过语音识别转换的文字内容。');
  });

  testWidgets('microphone recording handles permission denial gracefully', (tester) async {
    final recorder = FakeGenAiAudioRecorder(permission: false);
    await show(tester, audioRecorder: recorder);

    await tester.tap(find.byKey(const ValueKey('genai-audio-stt')));
    await tester.pumpAndSettle();

    expect(recorder.startCalls, 0);
    expect(find.text('无法访问麦克风，请检查权限设置'), findsOneWidget);
  });

  testWidgets('uploading image adds attachment chip without refreshing or resetting conversation',
      (tester) async {
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'sample_photo.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      ),
    );
    final demo = await show(tester, picker: picker);

    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '分析这幅图片',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    expect(imageBtn, findsOneWidget);

    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(picker.pickImageCalls, 1);
    expect(demo.workspace.connected, isTrue);
    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.attachments.first.name, 'sample_photo.png');
    expect(find.text('sample_photo.png'), findsOneWidget);

    expect(find.text('分析这幅图片'), findsOneWidget);

    // Removing the attachment chip works and retains connected state
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.connected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uploading image and pressing send displays image in user bubble and preserves image bytes',
      (tester) async {
    final sampleBytes = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      11,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      96,
      0,
      0,
      0,
      2,
      0,
      1,
      226,
      33,
      188,
      51,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'sample_photo.png',
        bytes: sampleBytes,
      ),
    );
    final demo = await show(tester, picker: picker);

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.hasPendingUploads, isFalse);

    final sendBtn = find.byKey(const ValueKey('genai-send'));
    await tester.tap(sendBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.turns.length, 1);
    final turn = demo.workspace.turns.first;
    expect(turn.prompt, '请分析这张图片');
    expect(turn.attachedImageBytes, equals(sampleBytes));
    expect(turn.attachedImageUrl, isNotNull);

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed upload blocks send, shows failure badge and warning, and allows retry',
      (tester) async {
    final sampleBytes = Uint8List.fromList([1, 2, 3, 4]);
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'failed_image.png',
        bytes: sampleBytes,
      ),
    );
    final demo = await show(tester, picker: picker);

    demo.backend.failUpload = true;

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.hasFailedUploads, isTrue);

    expect(find.textContaining('上传失败'), findsOneWidget);

    final sendBtn = find.byKey(const ValueKey('genai-send'));
    expect(tester.widget<IconButton>(sendBtn).onPressed, isNull);

    final retryBtn = find.byKey(
      ValueKey(
        'genai-retry-attachment-${demo.workspace.attachments.first.id}',
      ),
    );
    expect(retryBtn, findsOneWidget);

    demo.backend.failUpload = false;

    await tester.tap(retryBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.hasFailedUploads, isFalse);
    expect(
      demo.workspace.attachments.first.imageUrl,
      contains('temp/test-upload-'),
    );
    expect(find.textContaining('上传失败'), findsNothing);
    expect(tester.widget<IconButton>(sendBtn).onPressed, isNotNull);

    await tester.tap(sendBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.turns.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uploading image displays thumbnail in composer and tapping opens image dialog',
      (tester) async {
    final sampleBytes = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      11,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      96,
      0,
      0,
      0,
      2,
      0,
      1,
      226,
      33,
      188,
      51,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
    final picker = FakeGenAiPicker(
      nextImage: GenAiPickedFile(
        name: 'thumbnail_test.png',
        bytes: sampleBytes,
      ),
    );
    final demo = await show(tester, picker: picker);

    await tester.tap(find.byKey(const ValueKey('genai-composer-more')));
    await tester.pumpAndSettle();
    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    final attId = demo.workspace.attachments.first.id;

    final thumbFinder = find.byKey(ValueKey('genai-attachment-thumbnail-$attId'));
    expect(thumbFinder, findsOneWidget);

    await tester.tap(thumbFinder);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar session search filters in real time with debounce', (tester) async {
    final demo = await show(
      tester,
      size: const Size(1200, 900),
      delay: Duration.zero,
    );
    await demo.workspace.reloadModels();
    await tester.pumpAndSettle();

    // Send first conversation
    final send1 = demo.workspace.send('alpha physics research');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await send1;
    await tester.pumpAndSettle();

    // Start new conversation and send second
    demo.workspace.newConversation();
    final send2 = demo.workspace.send('beta chemistry notes');
    for (var i = 0; i < 300 && demo.workspace.sending; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await send2;
    await tester.pumpAndSettle();

    // Refresh history in sidebar
    await tester.tap(find.byTooltip('刷新历史'));
    await tester.pumpAndSettle();

    Finder historyItem(String text) => find.byWidgetPredicate((w) => w is Text && w.data == text);

    expect(historyItem('alpha physics research'), findsOneWidget);
    expect(historyItem('beta chemistry notes'), findsOneWidget);

    final sidebarSearch = find.widgetWithText(TextField, '搜索历史对话');
    expect(sidebarSearch, findsOneWidget);

    // Type 'alpha' in sidebar search
    await tester.enterText(sidebarSearch, 'alpha');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(historyItem('alpha physics research'), findsOneWidget);
    expect(historyItem('beta chemistry notes'), findsNothing);

    // Clear search
    await tester.enterText(sidebarSearch, '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(historyItem('alpha physics research'), findsOneWidget);
    expect(historyItem('beta chemistry notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
