import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../genai_web_input_scope.dart';
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
  web.HTMLDivElement? _host;
  web.HTMLIFrameElement? _frame;
  web.ResizeObserver? _attachmentObserver;
  web.IntersectionObserver? _visibilityObserver;
  bool _inViewport = false;
  bool _inputBlocked = false;
  int? _animationFrame;
  late final JSFunction _listener;
  late final JSFunction _visibilityListener;

  bool get _active => widget.active && _inViewport && !web.document.hidden;

  /// A Flutter barrier (the drawer scrim, a dialog, a sheet, a menu) cannot
  /// intercept pointer or wheel events that land in the iframe's own document,
  /// so the platform view is made non-interactive while one is open. The host
  /// and the frame both have to be switched off: the host swallows taps that
  /// miss the frame, and the frame swallows everything inside it. `inert` also
  /// covers keyboard focus, so a focused frame cannot keep receiving keys. A
  /// frame that already owns focus is blurred only in that case, never to take
  /// focus away from a drawer or dialog. Nothing about the browsing context
  /// changes, so srcdoc, scheduler and activity updates continue untouched.
  void _applyInputBlock(bool blocked) {
    _inputBlocked = blocked;
    final value = blocked ? 'none' : 'auto';
    final host = _host;
    if (host != null) {
      host.style.pointerEvents = value;
      host.inert = blocked;
    }
    final frame = _frame;
    if (frame != null) {
      frame.style.pointerEvents = value;
      frame.inert = blocked;
      final active = web.document.activeElement;
      if (blocked && active != null && frame.strictEquals(active).toDart) {
        frame.blur();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      final frame = _frame;
      if (frame == null || !event.source.strictEquals(frame.contentWindow).toDart) return;
      final value = event.data.dartify();
      if (value is! Map || value['kind'] != 'techpie-visual') return;
      final kind = value['event'];
      if (kind is! String ||
          (!GenAiVisualDocument.statusEvents.contains(kind) && kind != 'scroll')) {
        return;
      }
      if (kind == 'ready') {
        _updateActivity();
        _updateTheme();
        _updateLayout();
      }
      if (kind == 'scroll' && (_inputBlocked || !widget.active || widget.fullscreen)) return;
      final amount = value[kind == 'scroll' ? 'delta' : 'height'];
      widget.onEvent(kind, amount is num ? amount.toDouble() : null);
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
    if (oldWidget.fullscreen != widget.fullscreen) _updateLayout();
  }

  void _updateLayout() {
    _frame?.contentWindow?.postMessage(
      GenAiVisualDocument.layoutMessage(widget.fullscreen).jsify(),
      '*'.toJS,
    );
  }

  void _updateTheme() {
    _frame?.contentWindow?.postMessage(
      GenAiVisualDocument.themeMessage(widget.theme).jsify(),
      '*'.toJS,
    );
  }

  void _updateActivity() {
    _frame?.contentWindow?.postMessage(
      GenAiVisualDocument.activityMessage(_active).jsify(),
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
    _frame = null;
    _host = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Block while the workspace drawer is open (an own overlay, not a route)
    // or while a modal route sits above this route (dialog, sheet, menu). A
    // missing route or scope means this surface is hosted directly, never a
    // blocked one. The read registers dependencies, so opening and closing
    // either surface rebuilds this widget and re-applies the DOM state.
    _applyInputBlock(GenAiWebInputScope.blocks(context));
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        final host = element as web.HTMLDivElement;
        _host = host;
        host.style
          ..width = '100%'
          ..height = '100%'
          // The element may be created while a barrier is already open; the
          // build above has already resolved the current state.
          ..pointerEvents = _inputBlocked ? 'none' : 'auto';
        host.inert = _inputBlocked;
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
              ..border = '0'
              // A late attach must honor the barrier that is open now, not the
              // one that was open when this callback was scheduled.
              ..pointerEvents = _inputBlocked ? 'none' : 'auto';
            frame.inert = _inputBlocked;
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
                      fullscreen: widget.fullscreen,
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
}
