import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

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

class _GenAiVisualSurfaceState extends State<GenAiVisualSurface> {
  web.HTMLIFrameElement? _frame;
  web.ResizeObserver? _attachmentObserver;
  web.IntersectionObserver? _visibilityObserver;
  bool _inViewport = false;
  int? _animationFrame;
  late final JSFunction _listener;
  late final JSFunction _visibilityListener;

  bool get _active => widget.active && _inViewport && !web.document.hidden;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      final frame = _frame;
      if (frame == null || !event.source.strictEquals(frame.contentWindow).toDart) return;
      final value = event.data.dartify();
      if (value is! Map || value['kind'] != 'techpie-visual') return;
      final kind = value['event'];
      if (kind is! String || !const ['ready', 'height', 'error', 'escape'].contains(kind)) return;
      if (kind == 'ready') {
        _updateActivity();
        _updateTheme();
      }
      final height = value['height'];
      widget.onEvent(kind, height is num ? height.toDouble() : null);
    }).toJS;
    web.window.addEventListener('message', _listener);
    _visibilityListener = ((web.Event _) => _updateActivity()).toJS;
    web.document.addEventListener('visibilitychange', _visibilityListener);
  }

  @override
  void didUpdateWidget(GenAiVisualSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _updateActivity();
    if (!mapEquals(oldWidget.theme, widget.theme)) _updateTheme();
  }

  void _updateTheme() {
    _frame?.contentWindow?.postMessage(
      {'kind': 'techpie-visual-theme', 'theme': widget.theme}.jsify(),
      '*'.toJS,
    );
  }

  void _updateActivity() {
    _frame?.contentWindow?.postMessage(
      {'kind': 'techpie-visual-active', 'active': _active}.jsify(),
      '*'.toJS,
    );
  }

  @override
  void dispose() {
    _attachmentObserver?.disconnect();
    _visibilityObserver?.disconnect();
    final animationFrame = _animationFrame;
    if (animationFrame != null) web.window.cancelAnimationFrame(animationFrame);
    web.window.removeEventListener('message', _listener);
    web.document.removeEventListener('visibilitychange', _visibilityListener);
    _frame?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'div',
        onElementCreated: (element) {
          final host = element as web.HTMLDivElement;
          host.style
            ..width = '100%'
            ..height = '100%';
          _visibilityObserver = web.IntersectionObserver(
            (
              JSArray<web.IntersectionObserverEntry> entries,
              web.IntersectionObserver observer,
            ) {
              if (!mounted) return;
              for (final entry in entries.toDart) {
                _inViewport = entry.isIntersecting;
              }
              _updateActivity();
            }.toJS,
          )..observe(host);
          // Flutter attaches and slots platform elements after creation. Create
          // the browsing context only once its host is in the rendered DOM.
          _attachmentObserver = web.ResizeObserver(
            (
              JSArray<web.ResizeObserverEntry> entries,
              web.ResizeObserver observer,
            ) {
              if (!mounted) {
                observer.disconnect();
                return;
              }
              if (!host.isConnected || host.clientWidth == 0 || host.clientHeight == 0) return;
              observer.disconnect();
              _attachmentObserver = null;
              final frame = web.HTMLIFrameElement()
                ..title = '交互示例'
                ..setAttribute('sandbox', 'allow-scripts')
                ..referrerPolicy = 'no-referrer'
                ..setAttribute('allow', "camera 'none'; microphone 'none'; geolocation 'none'");
              frame.style
                ..width = '100%'
                ..height = '100%'
                ..border = '0';
              _frame = frame;
              host.append(frame);
              // Let the newly attached browsing context finish its initial
              // about:blank navigation before assigning srcdoc. Navigating in
              // the ResizeObserver callback can be lost while Flutter is still
              // attaching the platform view (especially when reopening a chat).
              _animationFrame = web.window.requestAnimationFrame(
                ((num _) {
                  _animationFrame = web.window.requestAnimationFrame(
                    ((num _) {
                      _animationFrame = null;
                      if (!mounted || !identical(_frame, frame)) return;
                      widget.onEvent('loading', null);
                      frame.srcdoc = GenAiVisualDocument.shell(
                        widget.document,
                        native: false,
                        active: _active,
                        theme: widget.theme,
                      ).toJS;
                    }).toJS,
                  );
                }).toJS,
              );
            }.toJS,
          )..observe(host);
        },
      );
}
