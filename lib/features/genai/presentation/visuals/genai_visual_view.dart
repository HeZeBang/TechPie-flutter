import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../markdown/genai_code_font.dart';
import '../markdown/genai_copy_button.dart';
import '../markdown/genai_syntax_highlighter.dart';
import 'genai_visual_document.dart';
import 'genai_visual_surface.dart';

/// The latest complete visual is expanded on reopen. User overrides last until
/// another complete visual arrives; no conversation-local persistence is needed.
class GenAiVisualScope extends InheritedWidget {
  const GenAiVisualScope({
    super.key,
    required this.latest,
    required this.answerId,
    required super.child,
  });
  final (String, int)? latest;
  final String answerId;

  @override
  bool updateShouldNotify(GenAiVisualScope oldWidget) =>
      latest != oldWidget.latest || answerId != oldWidget.answerId;
}

/// A complete example stays inline; only its canvas moves into the fullscreen
/// overlay, retaining the same JS runtime and local interaction state.
class GenAiVisualView extends StatefulWidget {
  const GenAiVisualView({super.key, required this.code, required this.complete, this.index = 1});
  final String code;
  final int index;
  final bool complete;

  @override
  State<GenAiVisualView> createState() => _GenAiVisualViewState();
}

class _GenAiVisualViewState extends State<GenAiVisualView> {
  final _overlay = OverlayPortalController();
  final _fullscreenFocus = FocusScopeNode();
  final _inlineContentKey = GlobalKey();
  GlobalKey _surfaceKey = GlobalKey();
  String? _document;
  String? _error;
  bool _ready = false;
  bool _timedOut = false;
  bool _source = false;
  bool _full = false;
  bool _collapsed = false;
  bool _activated = false;
  (String, int)? _latestVisual;
  double _height = 360;
  double? _inlineHeight;
  int _revision = 0;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<GenAiVisualScope>();
    if (!_activated || scope?.latest != _latestVisual) {
      _latestVisual = scope?.latest;
      _collapsed = scope?.latest != null && scope!.latest != (scope.answerId, widget.index);
      if (!_collapsed && !_activated) {
        _activated = true;
        if (widget.complete) unawaited(_load());
      }
      if (_collapsed && _full) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _collapsed && _full) _fullscreen(false);
        });
      }
    }
  }

  void _toggleCollapsed() {
    setState(() => _collapsed = !_collapsed);
    if (!_collapsed && !_activated) {
      _activated = true;
      if (widget.complete) unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(GenAiVisualView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code || oldWidget.complete != widget.complete) {
      _timeout?.cancel();
      _revision++;
      _document = null;
      _ready = false;
      _timedOut = false;
      _error = null;
      if (widget.complete && _activated) unawaited(_load());
    }
  }

  Future<void> _load() async {
    final revision = ++_revision;
    _timeout?.cancel();
    setState(() {
      _error = null;
      _ready = false;
      _timedOut = false;
      _document = null;
      _surfaceKey = GlobalKey();
    });
    if (!kIsWeb &&
        const [TargetPlatform.windows, TargetPlatform.linux].contains(defaultTargetPlatform)) {
      setState(() {
        _error = '此平台暂不支持内嵌交互示例';
        _source = true;
      });
      return;
    }
    try {
      final document = await GenAiVisualDocument.prepare(widget.code);
      if (!mounted || revision != _revision) return;
      setState(() => _document = document);
    } on GenAiVisualException catch (error) {
      if (mounted && revision == _revision) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _error = '无法运行此示例');
    }
  }

  void _event(String event, double? height) {
    if (!mounted) return;
    if (event == 'loading') {
      // Hidden/offscreen platform views may not attach until later. Measure
      // startup from navigation, not from preparing their saved HTML.
      final revision = _revision;
      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 25), () {
        if (mounted && revision == _revision && !_ready && _error == null) {
          setState(() => _timedOut = true);
        }
      });
    } else if (event == 'escape') {
      if (_full) _fullscreen(false);
    } else if (event == 'ready') {
      _timeout?.cancel();
      setState(() {
        _ready = true;
        _timedOut = false;
      });
    } else if (event == 'error') {
      _timeout?.cancel();
      setState(() => _error = '示例运行出错');
    } else if (event == 'height' && height != null && height.isFinite) {
      // Fullscreen has a different viewport; retain the inline measurement.
      // ResizeObserver measures again when the canvas returns inline.
      if (_full) return;
      final next = height.clamp(180.0, 560.0);
      if ((next - _height).abs() > 2) setState(() => _height = next);
    }
  }

  void _fullscreen(bool value) {
    if (value) {
      final box = _inlineContentKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) _inlineHeight = box.size.height;
    }
    setState(() => _full = value);
    if (value) {
      _overlay.show();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _full) _fullscreenFocus.requestFocus();
      });
    } else {
      _overlay.hide();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _fullscreenFocus.dispose();
    super.dispose();
  }

  Widget _canvas() {
    if (!widget.complete) return const Center(child: Text('正在生成交互示例…'));
    if (_document == null) {
      return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!));
    }
    final colors = Theme.of(context).colorScheme;
    String hex(Color color) =>
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    final theme = <String, String>{
      'mode': Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
      'bg': hex(colors.surface),
      'surface': hex(colors.surfaceContainerLow),
      'text': hex(colors.onSurface),
      'muted': hex(colors.onSurfaceVariant),
      'primary': hex(colors.primary),
      'on-primary': hex(colors.onPrimary),
      'border': hex(colors.outlineVariant),
    };
    final revision = _revision;
    final error = _error ?? (_timedOut ? '示例未能启动' : null);
    return Stack(
      children: [
        Positioned.fill(
          child: GenAiVisualSurface(
            key: _surfaceKey,
            document: _document!,
            active: !_source && (!_collapsed || _full),
            fullscreen: _full,
            theme: theme,
            onEvent: (event, height) {
              if (revision == _revision) _event(event, height);
            },
          ),
        ),
        if (!_ready && error == null)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
        if (error != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(10), child: Text(error)),
            ),
          ),
      ],
    );
  }

  bool _compactToolbar(double width) =>
      width < 360 * MediaQuery.textScalerOf(context).scale(14) / 14;

  Widget _toolbar() => LayoutBuilder(
        builder: (context, constraints) {
          final title = _full
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('交互示例', maxLines: 1, overflow: TextOverflow.ellipsis),
                )
              : TextButton.icon(
                  onPressed: _toggleCollapsed,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  icon: Icon(_collapsed ? Icons.chevron_right : Icons.expand_more, size: 20),
                  label: const Text('交互示例', maxLines: 1, overflow: TextOverflow.ellipsis),
                );
          if (_collapsed && !_full) return SizedBox(width: double.infinity, child: title);
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '重新运行',
                onPressed: widget.complete ? () => unawaited(_load()) : null,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              IconButton(
                tooltip: _source ? '显示示例' : '查看源码',
                onPressed: () => setState(() => _source = !_source),
                icon: Icon(_source ? Icons.widgets_outlined : Icons.code, size: 20),
              ),
              GenAiCopyButton(text: widget.code, tooltip: '复制源码'),
              IconButton(
                tooltip: _full ? '退出全屏' : '全屏',
                onPressed: () => _fullscreen(!_full),
                icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen, size: 20),
              ),
            ],
          );
          if (_compactToolbar(constraints.maxWidth)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, Align(alignment: Alignment.centerRight, child: actions)],
            );
          }
          return Row(children: [Expanded(child: title), actions]);
        },
      );

  Widget _content({required bool full}) => Column(
        key: full ? null : _inlineContentKey,
        mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          if (!_collapsed || full) const Divider(height: 1),
          if (full)
            Expanded(child: _body())
          else
            Offstage(
              offstage: _collapsed,
              child: SizedBox(
                height: _height,
                child: _full || !_activated ? const SizedBox.shrink() : _body(),
              ),
            ),
        ],
      );

  Widget _body() => Stack(
        children: [
          Positioned.fill(child: Offstage(offstage: _source, child: _canvas())),
          if (_source)
            Positioned.fill(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null || _timedOut)
                      Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(_error ?? '示例未能启动'),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: SelectableText.rich(
                        TextSpan(
                          children: GenAiSyntaxHighlighter(
                            brightness: Theme.of(context).brightness,
                          ).highlight(code: widget.code, language: 'html'),
                        ),
                        style: const TextStyle(
                          fontFamily: kGenAiMonospaceFamily,
                          fontFamilyFallback: kGenAiMonospaceFallback,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) => OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) => Positioned.fill(
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _fullscreen(false)},
            child: FocusScope(
              node: _fullscreenFocus,
              autofocus: true,
              child: PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _fullscreen(false);
                },
                child: BlockSemantics(
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(child: _content(full: true)),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _full ? SizedBox(height: _inlineHeight ?? _height + 49) : _content(full: false),
        ),
      );
}
