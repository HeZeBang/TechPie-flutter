import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_document.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_surface.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_view.dart';
// Test doubles use the platform interface pinned by the WebView override.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  late _Platform platform;
  late WebViewPlatform? previous;
  setUp(() {
    previous = WebViewPlatform.instance;
    platform = _Platform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    if (previous != null) WebViewPlatform.instance = previous;
  });

  testWidgets('fullscreen measurements do not overwrite the inline viewport', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GenAiVisualView(code: '<p>Example</p>', complete: true)),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byType(GenAiVisualSurface);
    void report(String event, [double? height]) =>
        tester.widget<GenAiVisualSurface>(surface).onEvent(event, height);
    report('ready');
    report('height', 240);
    await tester.pump();
    expect(tester.getSize(surface).height, 240);
    expect(tester.widget<GenAiVisualSurface>(surface).fullscreen, isFalse);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).fullscreen, isTrue);
    // The frame fills the padded overlay body instead of keeping the inline
    // measurement. The generated document owns the width cap and scrolling.
    final body = tester.getRect(find.byKey(const ValueKey('genai-visual-fullscreen-body')));
    expect(tester.getRect(surface), body.deflate(24));
    expect(tester.getCenter(surface).dx, body.center.dx);
    report('height', 900);
    await tester.pump();
    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    // The inline viewport is restored exactly, in both directions.
    expect(tester.getSize(surface).height, 240);
    expect(platform.controllers, hasLength(1));
    expect(tester.widget<GenAiVisualSurface>(surface).fullscreen, isFalse);
    // A measurement tagged for fullscreen may arrive after exit; it is stored
    // separately and cannot disturb the inline height.
    report('fullscreen-height', 900);
    await tester.pump();
    expect(tester.getSize(surface).height, 240);
    report('height', 280);
    await tester.pump();
    expect(tester.getSize(surface).height, 280);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('folding pauses the runtime while the source dialog leaves it running',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GenAiVisualView(code: '<p>Example</p>', complete: true)),
      ),
    );
    await tester.pumpAndSettle();
    final controller = platform.controllers.single;
    controller.report('ready');
    await tester.pumpAndSettle();
    final surface = find.byType(GenAiVisualSurface, skipOffstage: false);
    expect(tester.widget<GenAiVisualSurface>(surface).active, isTrue);

    await tester.tap(find.text('交互示例'));
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).active, isFalse);
    expect(controller.activities.last, isFalse);
    await tester.tap(find.text('交互示例'));
    await tester.pumpAndSettle();
    expect(controller.activities.last, isTrue);

    // Source is a separate dialog: the same runtime stays active behind it and
    // is never replaced, reloaded or paused by opening or closing it.
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-source')), findsOneWidget);
    expect(tester.widget<GenAiVisualSurface>(surface).active, isTrue);
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-source')), findsNothing);
    expect(tester.widget<GenAiVisualSurface>(surface).active, isTrue);
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('fullscreen activates an older scoped visual that started folded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GenAiVisualScope(
              latest: ('answer', 2),
              answerId: 'answer',
              child: Column(
                children: [
                  GenAiVisualView(code: '<p>Older</p>', index: 1, complete: true),
                  GenAiVisualView(code: '<p>Newer</p>', index: 2, complete: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Only the newest visual ran; the older one is folded and never activated.
    expect(platform.controllers, hasLength(1));
    final newerController = platform.controllers.single;
    final older = find.byWidgetPredicate(
      (widget) => widget is GenAiVisualView && widget.index == 1,
    );
    expect(find.descendant(of: older, matching: find.byType(GenAiVisualSurface)), findsNothing);
    final olderFullscreen = find.descendant(of: older, matching: find.byTooltip('全屏'));
    expect(olderFullscreen, findsOneWidget);

    await tester.tap(olderFullscreen);
    await tester.pumpAndSettle();

    // Entering fullscreen lazily mounts exactly one runtime for the older
    // visual and shows its active canvas.
    expect(platform.controllers, hasLength(2));
    final olderController = platform.controllers.last;
    expect(olderController.documents, hasLength(1));
    final fullscreen = find.byKey(const ValueKey('genai-visual-fullscreen'));
    expect(fullscreen, findsOneWidget);
    final canvas = find.descendant(of: fullscreen, matching: find.byType(GenAiVisualSurface));
    expect(canvas, findsOneWidget);
    expect(tester.widget<GenAiVisualSurface>(canvas).active, isTrue);
    expect(tester.widget<GenAiVisualSurface>(canvas).document, contains('Older'));

    // Leaving fullscreen does not load again.
    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(platform.controllers, hasLength(2));
    expect(platform.controllers.first, same(newerController));
    expect(olderController.documents, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('disposing the visual removes only its own source dialog route', (tester) async {
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

    final showingVisual = ValueNotifier<bool>(true);
    addTearDown(showingVisual.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showingVisual,
            builder: (context, visible, _) => visible
                ? const GenAiVisualView(
                    key: ValueKey('first'),
                    code: '<p>First</p>',
                    title: 'First',
                    complete: false,
                  )
                : const Text('Second conversation'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看源代码'));
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('genai-visual-source'));
    expect(source, findsOneWidget);

    // An unrelated route above the source dialog must survive. Disposal removes
    // the exact route this visual owns, not whatever is on top.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('其他页面'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('其他页面'), findsOneWidget);

    // Account/history switch removes the originating visual while the modal
    // is still open.
    showingVisual.value = false;
    await tester.pumpAndSettle();
    expect(source, findsNothing);
    expect(find.text('其他页面'), findsOneWidget);
    expect(copies, isEmpty);
    expect(tester.takeException(), isNull);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Second conversation'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('native gestures scroll chat inline and reach the visual in fullscreen',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Widget build(bool fullscreen) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  SizedBox(
                    height: 320,
                    child: GenAiVisualSurface(
                      document: '<button>Example</button>',
                      theme: const {},
                      fullscreen: fullscreen,
                      onEvent: (_, __) {},
                    ),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        );
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    final controller = platform.controllers.single;
    final events = controller.pointers.events;
    final view = find.byKey(const ValueKey('native-visual'));
    await tester.drag(view, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(events, isEmpty);

    scroll.jumpTo(0);
    await tester.pump();
    await tester.tap(view);
    await tester.pump();
    expect(events.whereType<PointerDownEvent>(), hasLength(1));
    expect(events.whereType<PointerUpEvent>(), hasLength(1));
    events.clear();
    await tester.drag(view, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(events.whereType<PointerMoveEvent>(), isNotEmpty);

    await tester.pumpWidget(build(true));
    events.clear();
    await tester.drag(view, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(events.whereType<PointerMoveEvent>(), isNotEmpty);

    await tester.pumpWidget(build(false));
    events.clear();
    await tester.drag(view, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(events, isEmpty);
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('entering and leaving fullscreen preserves the conversation scroll offset',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: const Column(
              children: [
                SizedBox(height: 500),
                GenAiVisualView(code: '<p>Example</p>', complete: true),
                SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(300);
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    expect(offset, 300);

    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-visual-fullscreen')), findsOneWidget);
    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(scroll.offset, offset);
    expect(platform.controllers, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('native activity combines app lifecycle and visibility without reloading',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    Widget build(bool active) => MaterialApp(
          home: GenAiVisualSurface(
            document: '<p>Example</p>',
            theme: const {},
            active: active,
            onEvent: (_, __) {},
          ),
        );
    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    final controller = platform.controllers.single;
    expect(
      controller.documents.single,
      GenAiVisualDocument.shell('<p>Example</p>', native: true, active: false),
    );
    expect(controller.activities.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.activities.last, isTrue);
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(controller.activities.last, isFalse);
    }
    await tester.pumpWidget(build(false));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(controller.activities.last, isFalse);
    await tester.pumpWidget(build(true));
    expect(controller.activities.last, isTrue);
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final scriptsAfterDisposal = controller.scripts.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.scripts, hasLength(scriptsAfterDisposal));
  });

  testWidgets('native initialization and ready delivery use the latest activity', (tester) async {
    final gate = Completer<void>();
    platform.setupGate = gate.future;
    Widget build(bool active) => MaterialApp(
          home: GenAiVisualSurface(
            document: '<p>Example</p>',
            theme: const {},
            active: active,
            onEvent: (_, __) {},
          ),
        );
    await tester.pumpWidget(build(true));
    await tester.pump();
    await tester.pumpWidget(build(false));
    gate.complete();
    await tester.pumpAndSettle();
    final controller = platform.controllers.single;
    expect(
      controller.documents.single,
      GenAiVisualDocument.shell('<p>Example</p>', native: true, active: false),
    );
    expect(controller.activities.last, isFalse);
    await tester.pumpWidget(build(true));
    controller.scripts.clear();
    // Messages sent while the document was loading may have been dropped.
    controller.report('ready');
    await tester.pump();
    expect(controller.activities, [true]);
    await tester.pumpWidget(build(false));
    controller.scripts.clear();
    controller.report('ready');
    await tester.pump();
    expect(controller.activities, [false]);
    expect(controller.documents, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('native layout messages follow fullscreen transitions and ready without reloading',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GenAiVisualView(code: '<p>Example</p>', complete: true)),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byType(GenAiVisualSurface);
    final controller = platform.controllers.single;
    controller.scripts.clear();
    controller.report('ready');
    await tester.pump();
    expect(controller.layouts, [false]);

    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).fullscreen, isTrue);
    expect(controller.layouts, [false, true]);

    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).fullscreen, isFalse);
    expect(controller.layouts, [false, true, false]);

    // A ready report repeats the current layout; the runtime is never reloaded.
    controller.report('ready');
    await tester.pump();
    expect(controller.layouts, [false, true, false, false]);
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('native initialization stays hidden and cleans up after disposal', (tester) async {
    final gate = Completer<void>();
    platform.setupGate = gate.future;
    Widget build(Brightness brightness) => MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: GenAiVisualSurface(
              document: '<p>Example</p>',
              theme: const {},
              onEvent: (_, __) {},
            ),
          ),
        );
    await tester.pumpWidget(build(Brightness.light));
    await tester.pump();
    await tester.pumpWidget(build(Brightness.dark));
    expect(find.byKey(const ValueKey('native-visual')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(platform.controllers.single.documents, ['<!doctype html><html></html>']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fullscreen uses bounded dialog geometry and a padded mobile body', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 820);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GenAiVisualView(code: '<p>Example</p>', complete: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('genai-visual-fullscreen'));
    expect(tester.getSize(dialog), const Size(1160, 780));
    expect(tester.getTopLeft(dialog).dx, 60);
    expect(
      (tester.widget<Material>(dialog).shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(18),
    );
    final desktopSurface = find.byType(GenAiVisualSurface);
    final desktopBody = tester.getRect(find.byKey(const ValueKey('genai-visual-fullscreen-body')));
    expect(tester.getSize(desktopSurface).width, 1112);
    expect(tester.getRect(desktopSurface), desktopBody.deflate(24));

    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(tester.getSize(dialog), const Size(375, 812));
    expect(
      (tester.widget<Material>(dialog).shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.zero,
    );
    final mobileSurface = find.byType(GenAiVisualSurface);
    final mobileBody = tester.getRect(find.byKey(const ValueKey('genai-visual-fullscreen-body')));
    expect(tester.getSize(mobileSurface).width, 351);
    expect(tester.getRect(mobileSurface), mobileBody.deflate(12));
    expect(mobileBody.contains(tester.getCenter(mobileSurface)), isTrue);
    expect(tester.getTopLeft(mobileSurface).dy, mobileBody.top + 12);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('theme and fullscreen changes keep the same runtime and document', (tester) async {
    Future<void> build(Brightness brightness) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: GenAiVisualView(code: '<p>Example</p>', complete: true),
            ),
          ),
        );
    await build(Brightness.light);
    await tester.pumpAndSettle();
    final surface = find.byType(GenAiVisualSurface);
    final controller = platform.controllers.single;
    expect(tester.widget<GenAiVisualSurface>(surface).theme['mode'], 'light');
    await build(Brightness.dark);
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).theme['mode'], 'dark');
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));

    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).theme['mode'], 'dark');
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

class _Platform extends WebViewPlatform {
  Future<void>? setupGate;
  final controllers = <_Controller>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params, setupGate);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _Delegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) =>
      _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.gate) : super.implementation();
  final Future<void>? gate;
  final documents = <String>[];
  final scripts = <String>[];
  final pointers = _PointerController();
  JavaScriptChannelParams? _channel;

  List<bool> get activities => scripts
      .where((script) => script.contains('techpie-visual-active'))
      .map((script) => script.contains('"active":true'))
      .toList();

  List<bool> get layouts => scripts
      .where((script) => script.contains('techpie-visual-layout'))
      .map((script) => script.contains('"fullscreen":true'))
      .toList();

  void report(String event) => _channel!.onMessageReceived(
        JavaScriptMessage(message: jsonEncode({'kind': 'techpie-visual', 'event': event})),
      );

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    await gate;
  }

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {
    _channel = javaScriptChannelParams;
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async => documents.add(html);

  @override
  Future<void> runJavaScript(String javaScript) async => scripts.add(javaScript);
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => PlatformViewSurface(
        key: const ValueKey('native-visual'),
        controller: (params.controller as _Controller).pointers,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        gestureRecognizers: params.gestureRecognizers,
      );
}

class _PointerController extends PlatformViewController {
  final events = <PointerEvent>[];

  @override
  final viewId = platformViewsRegistry.getNextPlatformViewId();

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async => events.add(event);

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispose() async {}
}
