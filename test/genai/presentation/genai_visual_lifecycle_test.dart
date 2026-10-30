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
    report('height', 900);
    await tester.pump();
    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.getSize(surface).height, 240);
    expect(platform.controllers, hasLength(1));
    expect(tester.widget<GenAiVisualSurface>(surface).fullscreen, isFalse);
    report('height', 280);
    await tester.pump();
    expect(tester.getSize(surface).height, 280);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('folding and source view pause the same visual runtime', (tester) async {
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

    await tester.tap(find.byTooltip('查看源码'));
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).active, isFalse);
    expect(controller.activities.last, isFalse);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).active, isFalse);
    await tester.tap(find.byTooltip('显示示例').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.widget<GenAiVisualSurface>(surface).active, isTrue);
    expect(controller.activities.last, isTrue);
    await tester.tap(find.byTooltip('退出全屏').hitTestable());
    await tester.pumpAndSettle();
    expect(platform.controllers.single, same(controller));
    expect(controller.documents, hasLength(1));
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
