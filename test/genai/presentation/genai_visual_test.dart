import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:techpie/features/genai/presentation/genai_icons.dart';
import 'package:techpie/features/genai/presentation/markdown/genai_latex.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_document.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_runtime.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_syntax.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_view.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';

void main() {
  Future<void> pumpVisual(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AdaptiveFeedbackHost(
          key: adaptiveFeedbackHostKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(
          body: GenAiVisualView(code: '<p>Example</p>', complete: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
  }

  bool menuItemEnabled(WidgetTester tester, String label) {
    final popup = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    );
    if (popup.evaluate().isNotEmpty) {
      return tester.widget<PopupMenuItem<dynamic>>(popup.first).enabled;
    }
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byType(MenuItemButton),
    );
    if (button.evaluate().isNotEmpty) {
      return tester.widget<MenuItemButton>(button.first).onPressed != null;
    }
    fail('No menu control found for "$label"');
  }

  test('streamed fences stay inert and preserve JavaScript until the actual closing fence', () {
    for (final fence in ['```', '~~~~']) {
      final input = '$fence' 'techpie-visual\n<script>const math = "\$\$x\$\$";</script>\n';
      for (var i = 0; i < fence.length; i++) {
        final text = preprocessLatexBlocks('$input${fence.substring(0, i)}');
        final nodes =
            md.Document(blockSyntaxes: [GenAiVisualSyntax()]).parseLines(text.split('\n'));
        final visual = nodes.whereType<md.Element>().single;
        expect(visual.attributes['complete'], 'false');
        expect(visual.textContent, contains('const math = "\$\$x\$\$";'));
      }
      final nodes = md.Document(blockSyntaxes: [GenAiVisualSyntax()])
          .parseLines(preprocessLatexBlocks('$input$fence\n\nAfter').split('\n'));
      expect((nodes.first as md.Element).attributes['complete'], 'true');
      expect(nodes.last.textContent, 'After');
    }
  });

  testWidgets('manual expansion survives theme changes until a newer visual arrives',
      (tester) async {
    Future<void> show((String, int) latest, Brightness brightness) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: GenAiVisualScope(
                latest: latest,
                answerId: 'old',
                child: const GenAiVisualView(code: '', complete: false),
              ),
            ),
          ),
        );
    await show(('new', 1), Brightness.light);
    expect(find.text('正在生成交互示例…'), findsNothing);
    await tester.tap(find.text('交互示例'));
    await tester.pump();
    expect(find.text('正在生成交互示例…'), findsOneWidget);
    await show(('new', 1), Brightness.dark);
    expect(find.text('正在生成交互示例…'), findsOneWidget);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pump();
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    // A second visual in the same later answer also folds manually opened history.
    await show(('new', 2), Brightness.dark);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('退出全屏'), findsNothing);
    expect(find.text('正在生成交互示例…'), findsNothing);
    await tester.tap(find.text('交互示例'));
    await tester.pump();
    expect(find.text('正在生成交互示例…'), findsOneWidget);
  });

  testWidgets('incomplete visual keeps secondary actions behind the more menu', (tester) async {
    await pumpVisual(tester);
    expect(find.text('交互示例'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);
    for (final tooltip in ['重新运行', '查看源代码', '显示示例', '复制内容', '复制', '关闭']) {
      expect(find.byTooltip(tooltip), findsNothing);
    }

    await openActions(tester);
    expect(find.text('重新运行'), findsOneWidget);
    expect(find.text('查看源代码'), findsOneWidget);
    expect(find.text('复制内容'), findsOneWidget);
    expect(menuItemEnabled(tester, '重新运行'), isFalse);
    expect(menuItemEnabled(tester, '查看源代码'), isTrue);
    expect(menuItemEnabled(tester, '复制内容'), isTrue);

    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-source')), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('示例源代码'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    // Source no longer replaces the inline example.
    expect(find.text('正在生成交互示例…'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-source')), findsNothing);
    expect(find.text('正在生成交互示例…'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);

    await openActions(tester);
    expect(find.text('查看源代码'), findsOneWidget);
    expect(find.text('显示示例'), findsNothing);
  });

  testWidgets('folding the heading hides only the inline body', (tester) async {
    await pumpVisual(tester);
    expect(find.text('正在生成交互示例…'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);

    await tester.tap(find.text('交互示例'));
    await tester.pumpAndSettle();
    expect(find.text('正在生成交互示例…'), findsNothing);
    // Header actions stay available while folded.
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);

    // The more menu still exposes the source dialog while folded.
    await openActions(tester);
    expect(find.text('查看源代码'), findsOneWidget);
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-source')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('交互示例'));
    await tester.pumpAndSettle();
    expect(find.text('正在生成交互示例…'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('fullscreen is a titled overlay with only an exit action', (tester) async {
    await pumpVisual(tester);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-fullscreen')), findsOneWidget);
    expect(find.text('交互示例'), findsOneWidget);
    expect(find.text('示例源代码'), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(find.byTooltip('全屏'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(find.byTooltip('重新运行'), findsNothing);
    expect(find.byTooltip('查看源代码'), findsNothing);
    expect(find.byTooltip('复制内容'), findsNothing);

    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-fullscreen')), findsNothing);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('explicit title replaces the generic label and HTML titles are ignored',
      (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenAiVisualView(
            code: '<title>Line Chart</title><h1>Heading</h1><p>x</p>',
            title: '曲线与切线',
            complete: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('曲线与切线'), findsOneWidget);
    expect(find.text('交互示例'), findsNothing);
    // Only the explicit label is used; markup can never reach the text layer.
    expect(find.text('Line Chart'), findsNothing);
    expect(find.text('Heading'), findsNothing);
    expect(tester.widget<Text>(find.text('曲线与切线')).style?.fontSize, 13);

    await tester.tap(find.text('曲线与切线'));
    await tester.pumpAndSettle();
    expect(find.text('正在生成交互示例…'), findsNothing);

    // The title still fits on a narrow card without a duplicate label.
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    expect(find.text('曲线与切线'), findsOneWidget);
    expect(find.text('交互示例'), findsNothing);
  });

  testWidgets('blank or absent title leaves only the generic tag', (tester) async {
    Future<void> pump(String? title) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GenAiVisualView(
                code: '<title>Line Chart</title><h1>Heading</h1><p>x</p>',
                title: title,
                complete: false,
              ),
            ),
          ),
        );
    for (final title in [null, '', '   ']) {
      await pump(title);
      await tester.pumpAndSettle();
      expect(find.text('交互示例'), findsOneWidget);
      expect(find.text('Line Chart'), findsNothing);
      expect(find.text('Heading'), findsNothing);
    }
  });

  testWidgets('more menu items carry their own icons and exact labels', (tester) async {
    await pumpVisual(tester);
    await openActions(tester);
    final entries = find.byWidgetPredicate((widget) => widget is PopupMenuItem<String>);
    expect(entries, findsNWidgets(3));
    for (final label in ['重新运行', '查看源代码', '复制内容']) {
      final item = find.ancestor(of: find.text(label), matching: entries);
      expect(item, findsOneWidget);
      expect(find.descendant(of: item, matching: find.byType(GenAiIcon)), findsOneWidget);
    }
  });

  testWidgets('more menu opens anchored clear of its button and preserves its rows',
      (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpVisual(tester);
    // The tooltip's child is inset from the IconButton the menu anchors to.
    final anchor =
        find.ancestor(of: find.byTooltip('更多操作'), matching: find.byType(IconButton)).first;
    final anchorRect = tester.getRect(anchor);
    await openActions(tester);

    final menu = find.byKey(const ValueKey('genai-anchored-menu'));
    expect(menu, findsOneWidget);
    final menuRect = tester.getRect(menu);
    expect(menuRect.overlaps(anchorRect), isFalse);
    expect(menuRect.top, closeTo(anchorRect.bottom + 7, 0.01));
    expect(menuItemEnabled(tester, '重新运行'), isFalse);
    expect(menuItemEnabled(tester, '查看源代码'), isTrue);
    expect(menuItemEnabled(tester, '复制内容'), isTrue);

    // Selecting from the shared route still opens the source dialog.
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-source')), findsOneWidget);
  });

  testWidgets('source opens in a separate rounded dialog at min(500, screen - 32)', (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpVisual(tester);
    await openActions(tester);
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();

    final dialog = find.byKey(const ValueKey('genai-visual-source'));
    expect(dialog, findsOneWidget);
    expect(tester.getSize(dialog).width, 500);
    expect(
      (tester.widget<Dialog>(find.ancestor(of: dialog, matching: find.byType(Dialog))).shape!
              as RoundedRectangleBorder)
          .borderRadius,
      BorderRadius.circular(18),
    );
    expect(find.text('示例源代码'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(
      tester
          .widget<Padding>(
            find.ancestor(of: find.text('示例源代码'), matching: find.byType(Padding)).first,
          )
          .padding,
      const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    );
    expect(tester.getSize(find.byTooltip('关闭')), const Size(36, 36));
    final code = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(code.textSpan!.toPlainText(), '<p>Example</p>');
    expect(code.style?.fontSize, 12);
    expect(code.style?.height, 1.7);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.descendant(of: dialog, matching: find.byType(SingleChildScrollView)),
          )
          .padding,
      const EdgeInsets.all(24),
    );
    // Copy lives in the dialog footer rather than the card header.
    expect(find.descendant(of: dialog, matching: find.text('复制')), findsOneWidget);
    // Only the header carries a divider; the draft has no footer divider.
    expect(find.descendant(of: dialog, matching: find.byType(Divider)), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);

    // On a phone the dialog leaves 16px on each side.
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    await openActions(tester);
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    expect(tester.getSize(dialog).width, 343);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('copy source writes the clipboard and reports the copied message', (tester) async {
    final copies = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpVisual(tester);
    await openActions(tester);
    await tester.tap(find.text('复制内容'));
    await tester.pumpAndSettle();
    expect(copies, ['<p>Example</p>']);
    expect(find.text('已复制源码'), findsOneWidget);

    // The source dialog footer copies the same code.
    await openActions(tester);
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copies, ['<p>Example</p>', '<p>Example</p>']);
    expect(find.text('已复制源码'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('已复制源码'), findsNothing);
  });

  test('visual ordering ignores quoted code examples and incomplete fences', () {
    expect(
      GenAiVisualSyntax.countComplete(
        '````text\n```techpie-visual\nnot a visual\n```\n````\n'
        '```techpie-visual\n<p>one</p>\n```\n'
        '```techpie-visual\n<p>still streaming',
      ),
      1,
    );
  });

  test('math loads only when used and its download failure leaves the demo usable', () async {
    final calls = <Uri>[];
    Future<String> loader(Uri uri) async {
      calls.add(uri);
      return 'window.katex={};';
    }

    await GenAiVisualDocument.prepare('<button>Play</button>', loadLibrary: loader);
    expect(calls, isEmpty);
    final prepared = await GenAiVisualDocument.prepare(
      r'<span data-latex="\frac{1}{2}"></span><button>Play</button>',
      loadLibrary: loader,
    );
    expect(calls, [Uri.parse(GenAiVisualDocument.mathLibrary)]);
    final doc = html.parse(prepared);
    expect(doc.querySelector('span')!.attributes['data-latex'], r'\frac{1}{2}');
    expect(doc.querySelectorAll('link, script[src]'), isEmpty);
    final fallback = await GenAiVisualDocument.prepare(
      r'<span data-latex="x^2"></span><script>const demoStillWorks=true;</script>',
      loadLibrary: (_) => Future.error(StateError('offline')),
    );
    expect(fallback, contains('demoStillWorks=true'));
    expect(fallback, contains('window.techpieMath'));
    final shell = GenAiVisualDocument.shell(fallback, native: false, active: false);
    expect(shell, contains('setActive(false)'));
    expect(shell, isNot(contains('/*techpie-active*/')));
  });

  test('documents wrap content and declare the fullscreen, reporting and math replay contracts',
      () async {
    final prepared = await GenAiVisualDocument.prepare('<p>Ready</p>');
    final document = html.parse(prepared);
    final content = document.querySelector('#techpie-visual-content');
    expect(content, isNotNull);
    expect(content!.querySelector('p')!.text, 'Ready');

    // The generated document, not Flutter, owns the fullscreen width cap,
    // centring margins and scrolling; mobile drops the vertical centring.
    final style = document.querySelector('style')!.text;
    expect(
      style,
      contains('html[data-techpie-fullscreen=true]{height:100%;overflow:auto!important}'),
    );
    expect(style, contains('width:min(900px,100%)'));
    expect(style, contains('margin-block:auto'));
    expect(style, contains('@media(max-width:600px)'));
    expect(
      style,
      contains('html[data-techpie-fullscreen=true] #techpie-visual-content{margin-block:0}'),
    );

    // A shell opened in fullscreen starts that way; the iframe measures tagged
    // for fullscreen are reported as fullscreen-height, not as the inline height.
    final fullscreenShell = GenAiVisualDocument.shell(prepared, native: false, fullscreen: true);
    expect(fullscreenShell, contains('let fullscreen=true;'));
    expect(
      fullscreenShell,
      contains("safe.event=d.fullscreen===true?'fullscreen-height':'height';"),
    );
    final inlineShell = GenAiVisualDocument.shell(prepared, native: false);
    expect(inlineShell, contains('let fullscreen=false;'));

    // Deferred math keeps only the latest request per element and replays it
    // once the optional renderer arrives.
    expect(genAiVisualMath, contains('pending.set(element,{tex,displayMode});armRetry();'));
    expect(genAiVisualMath, contains('const entries=Array.from(pending);pending.clear();'));
    expect(genAiVisualMath, contains('for(const [element,item] of entries)'));
  });

  test('delimited math libraries download concurrently and execute in dependency order', () async {
    final pending = <Uri, Completer<String>>{};
    final preparation = GenAiVisualDocument.prepare(
      r'<p>Inline \(x^2\), display \[y^2\] and $$z^2$$.</p>',
      loadLibrary: (uri) => (pending[uri] = Completer<String>()).future,
    );
    expect(pending.keys, [
      Uri.parse(GenAiVisualDocument.mathLibrary),
      Uri.parse(GenAiVisualDocument.mathAutoRenderLibrary),
    ]);
    pending[Uri.parse(GenAiVisualDocument.mathAutoRenderLibrary)]!
        .complete('window.renderMathInElement=function(){};');
    pending[Uri.parse(GenAiVisualDocument.mathLibrary)]!.complete('window.katex={};');
    final document = html.parse(await preparation);
    final scripts = document.querySelectorAll('script').map((script) => script.text).toList();
    final renderer = scripts.indexOf('window.katex={};');
    final autoRenderer = scripts.indexOf('window.renderMathInElement=function(){};');
    final bridge = scripts.indexWhere((script) => script.contains('window.techpieMath='));
    expect(renderer, greaterThanOrEqualTo(0));
    expect(autoRenderer, greaterThan(renderer));
    expect(bridge, greaterThan(autoRenderer));
    expect(document.querySelectorAll('script[src], link'), isEmpty);
  });

  test('script-created labels and aliased helper calls load math but currency does not', () async {
    final calls = <Uri>[];
    Future<String> loader(Uri uri) async {
      calls.add(uri);
      return 'window.katex={};';
    }

    await GenAiVisualDocument.prepare(r'<p>Costs $5 or $10.</p>', loadLibrary: loader);
    expect(calls, isEmpty);
    for (final source in [
      '<script>const math=window.techpieMath; math.render(label, "x^2");</script>',
      '<span id="label"></span><script>label.dataset.latex="x^2";</script>',
      '<script>label.dataset[ "latex" ]="x^2";</script>',
      '<script>const label=document.createElement("span");'
          'label.setAttribute("data-latex", "x^2"); document.body.append(label);</script>',
    ]) {
      calls.clear();
      final prepared = await GenAiVisualDocument.prepare(source, loadLibrary: loader);
      expect(calls, [Uri.parse(GenAiVisualDocument.mathLibrary)]);
      for (final script in html.parse(source).querySelectorAll('script')) {
        expect(prepared, contains(script.text));
      }
    }
  });

  test('an unavailable auto-render extension keeps the core renderer and demo scripts', () async {
    final prepared = await GenAiVisualDocument.prepare(
      r'<p>\(x^2\)</p><span data-latex="y^2"></span>'
      '<script>window.demoStillWorks=true;</script>',
      loadLibrary: (uri) async {
        if (uri.toString() == GenAiVisualDocument.mathAutoRenderLibrary) {
          throw StateError('offline');
        }
        return 'window.katex={};';
      },
    );
    final document = html.parse(prepared);
    expect(document.querySelector('p')!.text, r'\(x^2\)');
    expect(
      document.querySelectorAll('script').any((script) => script.text == 'window.katex={};'),
      isTrue,
    );
    expect(prepared, contains('window.demoStillWorks=true;'));
    expect(document.querySelector('span')!.attributes['data-latex'], 'y^2');
  });

  test('escaped JavaScript delimiters enable dynamic text rendering without altering scripts',
      () async {
    const source = r'<span id="output"></span>'
        r'<script>output.textContent="\\(x^2\\) and \\[y^2\\]";</script>';
    final calls = <Uri>[];
    final prepared = await GenAiVisualDocument.prepare(
      source,
      loadLibrary: (uri) async {
        calls.add(uri);
        return '// loaded';
      },
    );
    expect(calls, [
      Uri.parse(GenAiVisualDocument.mathLibrary),
      Uri.parse(GenAiVisualDocument.mathAutoRenderLibrary),
    ]);
    final sourceScript = html.parse(source).querySelector('script')!.text;
    expect(
      html.parse(prepared).querySelectorAll('script').any((script) => script.text == sourceScript),
      isTrue,
    );
  });

  test('sandbox policy precedes hostile metadata and only exact library URLs reach the loader',
      () async {
    final loaded = <Uri>[];
    final source = '<html><head><meta http-equiv="Content-Security-Policy" content="default-src *">'
        '<base href="https://example.com"><script src="${genAiVisualLibraries.first}"></script>'
        '</head><body><p>Ready</p><script>const x = "</iframe>";</script></body></html>';
    final prepared = await GenAiVisualDocument.prepare(
      source,
      loadLibrary: (uri) async {
        loaded.add(uri);
        return 'const library = "</script>";';
      },
    );
    final document = html.parse(prepared);
    expect(loaded, [Uri.parse(genAiVisualLibraries.first)]);
    expect(document.querySelectorAll('base, script[src], link'), isEmpty);
    expect(document.querySelectorAll('meta[http-equiv]'), hasLength(1));
    expect(document.head!.children.first.attributes['content'], genAiVisualCsp);
    final shell = html.parse(
      GenAiVisualDocument.shell(
        prepared,
        native: false,
        theme: const {'mode': 'dark', 'bg': '#101010'},
      ),
    );
    expect(shell.querySelectorAll('iframe'), hasLength(1));
    expect(shell.querySelector('iframe')!.attributes['sandbox'], 'allow-scripts');
    expect(shell.querySelector('iframe')!.attributes['src'], isNull);
    expect(shell.querySelectorAll('script'), hasLength(1));
    expect(shell.querySelector('script')!.text, contains('#101010'));
    expect(shell.querySelector('script')!.text, isNot(contains('{/*techpie-theme*/}')));
    for (final url in ['${genAiVisualLibraries.first}?secret=1', 'https://example.com/code.js']) {
      await expectLater(
        GenAiVisualDocument.prepare(
          '<script src="$url"></script>',
          loadLibrary: (_) async {
            fail('Untrusted URL must never reach the network');
          },
        ),
        throwsA(isA<GenAiVisualException>()),
      );
    }
  });
}
