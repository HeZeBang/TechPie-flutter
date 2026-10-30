import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'genai_visual_document.dart';

class GenAiVisualSurface extends StatefulWidget {
  const GenAiVisualSurface({
    super.key,
    required this.document,
    required this.onEvent,
    required this.theme,
    this.active = true,
    this.fullscreen = false,
  });
  final String document;
  final bool active;
  final bool fullscreen;
  final Map<String, String> theme;
  final void Function(String event, double? height) onEvent;

  @override
  State<GenAiVisualSurface> createState() => _GenAiVisualSurfaceState();
}

class _GenAiVisualSurfaceState extends State<GenAiVisualSurface> with WidgetsBindingObserver {
  WebViewController? _controller;
  bool _appActive = true;

  bool get _active => widget.active && _appActive;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    widget.onEvent('loading', null);
    WebViewController? controller;
    try {
      controller = WebViewController(
        onPermissionRequest: (request) => unawaited(request.deny()),
      );
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              const ['about:blank', 'about:srcdoc'].contains(request.url)
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) widget.onEvent('error', null);
          },
        ),
      );
      await controller.addJavaScriptChannel(
        'TechPieVisual',
        onMessageReceived: (message) {
          if (!mounted || message.message.length > 256) return;
          try {
            final value = jsonDecode(message.message);
            if (value is! Map || value['kind'] != 'techpie-visual') return;
            final kind = value['event'];
            if (kind is! String || !const ['ready', 'height', 'error', 'escape'].contains(kind)) {
              return;
            }
            if (kind == 'ready') {
              unawaited(_updateActivity());
              unawaited(_updateTheme());
            }
            final height = value['height'];
            widget.onEvent(kind, height is num ? height.toDouble() : null);
          } on FormatException {
            // Generated content has no host API; malformed status is ignored.
          }
        },
      );
      if (!mounted) return;
      // Only expose a configured view to rebuilds. Keep the local reference
      // for cleanup if initialization fails or disposal races with loading.
      setState(() => _controller = controller);
      await controller.loadHtmlString(
        GenAiVisualDocument.shell(
          widget.document,
          native: true,
          theme: widget.theme,
          active: _active,
        ),
      );
      if (mounted && identical(_controller, controller)) await _updateActivity();
    } catch (_) {
      if (mounted) {
        setState(() => _controller = null);
        widget.onEvent('error', null);
      }
    } finally {
      if (controller != null && (!mounted || !identical(_controller, controller))) {
        await _stop(controller);
      }
    }
  }

  @override
  void didUpdateWidget(GenAiVisualSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) unawaited(_updateActivity());
    if (!mapEquals(oldWidget.theme, widget.theme)) unawaited(_updateTheme());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    unawaited(_updateActivity());
  }

  Future<void> _updateActivity() async {
    try {
      final data = jsonEncode({'kind': 'techpie-visual-active', 'active': _active});
      await _controller?.runJavaScript("window.postMessage($data, '*');");
    } catch (_) {
      // A disposed platform view no longer needs activity updates.
    }
  }

  Future<void> _updateTheme() async {
    try {
      final data = jsonEncode({'kind': 'techpie-visual-theme', 'theme': widget.theme});
      await _controller?.runJavaScript("window.postMessage($data, '*');");
    } catch (_) {
      // A disposed platform view no longer needs theme updates.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) unawaited(_stop(controller));
    super.dispose();
  }

  Future<void> _stop(WebViewController controller) async {
    try {
      await controller.loadHtmlString('<!doctype html><html></html>');
    } catch (_) {
      // The platform view may already have been disposed.
    }
  }

  @override
  Widget build(BuildContext context) => _controller == null
      ? const SizedBox.shrink()
      : WebViewWidget(
          controller: _controller!,
          // Inline vertical drags belong to the chat. Unclaimed taps still
          // reach the platform view; horizontal drags keep sliders usable.
          // Distinct factory types let Flutter replace the gesture arena team.
          gestureRecognizers: widget.fullscreen
              ? const {Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new)}
              : const {
                  Factory<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new),
                },
        );
}
