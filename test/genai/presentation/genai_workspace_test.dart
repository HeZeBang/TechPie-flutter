import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/application/genai_chat_service.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/genai_thinking_view.dart';
import 'package:techpie/features/genai/presentation/genai_web_search_view.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';

import '../support/fakes.dart';

void main() {
  Future<GenAiDemo> show(
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
    final demo =
        await GenAiDemo.create(connected: connected, chunkDelay: delay);
    addTearDown(demo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: GenAiWorkspace(
          controller: demo.workspace,
          demo: true,
          audioRecorder: audioRecorder,
          picker: picker,
          login: (_) async =>
              const GenAiCredential(token: DemoGenAiBackend.token),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return demo;
  }

  testWidgets(
      'wide workspace has no suggested prompts and sends typed Markdown chat',
      (tester) async {
    final demo = await show(tester);
    expect(find.text('TechPie'), findsOneWidget);
    expect(find.text('本地演示 · 不访问校园服务，不产生费用'), findsOneWidget);
    expect(find.text('理清学习思路'), findsNothing);
    expect(find.text('一起写段代码'), findsNothing);
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

  testWidgets(
      'demo login connects without campus requests and logout clears the conversation',
      (tester) async {
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

  testWidgets('bound IDS without a school ID offers identity resolution',
      (tester) async {
    final demo = await GenAiDemo.create(connected: false);
    addTearDown(demo.dispose);
    await demo.sessions.setOwner(null);
    var connects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GenAiWorkspace(
          controller: demo.workspace,
          campusBound: true,
          login: (_) async => throw StateError('manual login must not run'),
          onPreviewLiveLogin: () => connects++,
          onBindCampus: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('校园身份待同步'), findsOneWidget);
    expect(find.text('绑定校园账号'), findsNothing);
    expect(find.text('管理校园账号'), findsOneWidget);
    await tester.tap(find.text('使用现有 IDS 会话连接'));
    await tester.pump();
    expect(connects, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialogue and image sit beside new chat and usage is in account',
      (tester) async {
    await show(tester, size: const Size(674, 1000));
    expect(find.text('更多功能'), findsNothing);
    final fresh = tester.getCenter(find.byTooltip('新的对话'));
    final history = tester.getCenter(find.byTooltip('会话记录'));
    final image = tester.getCenter(find.byTooltip('图片创作'));
    expect(fresh.dy, history.dy);
    expect(history.dy, image.dy);
    expect(fresh.dx, lessThan(history.dx));
    expect(history.dx, lessThan(image.dx));
    expect(find.text('用量统计'), findsNothing);
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

  testWidgets('stop preserves partial output and exposes an explicit retry',
      (tester) async {
    final demo = await show(tester, delay: const Duration(milliseconds: 20));
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      'test stop',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
    expect(demo.workspace.turns.single.phase, GenAiChatPhase.cancelled);
    expect(demo.workspace.turns.single.answer, isNotEmpty);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('narrow screen with large text and keyboard has no overflow',
      (tester) async {
    await show(tester, size: const Size(320, 740), scale: 1.6, keyboard: 280);
    expect(find.byKey(const ValueKey('genai-prompt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new conversation and account switch remove drafts and previous output',
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

  testWidgets('IME composition and Shift Enter do not submit a message',
      (tester) async {
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

  testWidgets('toggle thinking and net search chips updates controller state',
      (tester) async {
    final demo = await show(tester);
    final thinkingChip = find.byKey(const ValueKey('genai-thinking-toggle'));
    final searchChip = find.byKey(const ValueKey('genai-search-toggle'));
    expect(thinkingChip, findsOneWidget);
    expect(searchChip, findsOneWidget);

    expect(demo.workspace.thinkingEnabled, isFalse);
    await tester.tap(thinkingChip);
    await tester.pump();
    expect(demo.workspace.thinkingEnabled, isTrue);

    expect(demo.workspace.netSearchEnabled, isFalse);
    await tester.tap(searchChip);
    await tester.pump();
    expect(demo.workspace.netSearchEnabled, isTrue);
  });

  testWidgets(
      'chat with thinking and net search renders thinking and search views',
      (tester) async {
    final demo = await show(tester);
    await tester.tap(find.byKey(const ValueKey('genai-thinking-toggle')));
    await tester.tap(find.byKey(const ValueKey('genai-search-toggle')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '介绍上海科技大学',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    expect(demo.workspace.turns.single.phase, GenAiChatPhase.completed);
    expect(demo.workspace.turns.single.reasoning, isNotEmpty);
    expect(demo.workspace.turns.single.citations.length, 2);

    expect(find.byType(GenAiThinkingView), findsOneWidget);
    expect(find.byType(GenAiWebSearchView), findsOneWidget);
    expect(find.textContaining('已深度思考'), findsOneWidget);
    expect(find.textContaining('已检索 2 条网络参考来源'), findsOneWidget);
  });

  testWidgets('TTS voice playback button triggers without exception',
      (tester) async {
    await show(tester);
    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '测试语音播报',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    final ttsButton = find.byKey(const ValueKey('genai-tts-0'));
    expect(ttsButton, findsOneWidget);
    await tester.tap(ttsButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'microphone recording shows timer and waveform and can be cancelled',
      (tester) async {
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

  testWidgets(
      'finishing microphone recording stops recorder and transcribes audio to draft',
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

  testWidgets('microphone recording handles permission denial gracefully',
      (tester) async {
    final recorder = FakeGenAiAudioRecorder(permission: false);
    await show(tester, audioRecorder: recorder);

    await tester.tap(find.byKey(const ValueKey('genai-audio-stt')));
    await tester.pumpAndSettle();

    expect(recorder.startCalls, 0);
    expect(find.text('无法访问麦克风，请检查权限设置'), findsOneWidget);
  });

  testWidgets(
      'uploading image adds attachment chip without refreshing or resetting conversation',
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

  testWidgets(
      'failed upload blocks send, shows failure badge and warning, and allows retry',
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

    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    expect(demo.workspace.hasFailedUploads, isTrue);

    expect(find.text('上传失败'), findsOneWidget);
    expect(
      find.text('附件上传失败，已阻止发送。请点击重试或删除失败的附件。'),
      findsOneWidget,
    );

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
      contains('temp/demo-upload-'),
    );
    expect(find.text('上传失败'), findsNothing);
    expect(tester.widget<IconButton>(sendBtn).onPressed, isNotNull);

    await tester.tap(sendBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments, isEmpty);
    expect(demo.workspace.turns.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uploading image displays thumbnail in composer and tapping opens image dialog',
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

    final imageBtn = find.byKey(const ValueKey('genai-upload-image'));
    await tester.tap(imageBtn);
    await tester.pumpAndSettle();

    expect(demo.workspace.attachments.length, 1);
    final attId = demo.workspace.attachments.first.id;

    final thumbFinder =
        find.byKey(ValueKey('genai-attachment-thumbnail-$attId'));
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

  testWidgets(
      'message deletion, reversion, and edit actions are disabled on chat bubbles',
      (tester) async {
    final demo = await show(tester);

    await tester.enterText(
      find.byKey(const ValueKey('genai-prompt')),
      '测试消息',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('genai-send')));
    await tester.pumpAndSettle();

    expect(demo.workspace.turns.length, 1);

    // Scroll up so user bubble is in view
    await tester.drag(
      find.byKey(const ValueKey('genai-thread')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();

    // User bubble has copy button, but NO edit, delete, or revert buttons
    expect(find.byKey(const ValueKey('genai-user-copy-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-user-edit-0')), findsNothing);
    expect(find.byKey(const ValueKey('genai-user-delete-0')), findsNothing);

    // Assistant bubble has copy and tts buttons, but NO regenerate, delete or revert buttons
    expect(find.byKey(const ValueKey('genai-copy-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-tts-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('genai-regenerate-0')), findsNothing);
    expect(find.byKey(const ValueKey('genai-delete-0')), findsNothing);
  });

  testWidgets('sidebar session search filters in real time with debounce',
      (tester) async {
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

    Finder historyItem(String text) =>
        find.byWidgetPredicate((w) => w is Text && w.data == text);

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
