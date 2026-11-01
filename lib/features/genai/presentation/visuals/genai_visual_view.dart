import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../widgets/adaptive_feedback.dart';
import '../genai_icons.dart';
import '../genai_theme.dart';
import '../markdown/genai_code_font.dart';
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
/// overlay, retaining the same JS runtime and local interaction state. Source
/// opens in its own dialog and never replaces the running canvas.
class GenAiVisualView extends StatefulWidget {
  const GenAiVisualView({
    super.key,
    required this.code,
    required this.complete,
    this.index = 1,
    this.title,
  });
  final String code;
  final int index;
  final bool complete;

  /// A caller-supplied label for the example. It is shown as plain text; HTML
  /// titles and headings are deliberately not inferred. When absent or blank
  /// the header shows only the generic "交互示例" tag.
  final String? title;

  @override
  State<GenAiVisualView> createState() => _GenAiVisualViewState();
}

class _GenAiVisualViewState extends State<GenAiVisualView> {
  static const _cardRadius = 14.0;
  static const _cardRadiusCompact = 12.0;
  static const _fullscreenMaxWidth = 1160.0;
  static const _mobileBreakpoint = 600.0;
  static const _cardCompactBreakpoint = 680.0;

  final _overlay = OverlayPortalController();
  final _fullscreenFocus = FocusScopeNode();
  final _inlineContentKey = GlobalKey();
  GlobalKey _surfaceKey = GlobalKey();
  String? _document;
  String? _error;
  bool _ready = false;
  bool _timedOut = false;
  bool _full = false;
  bool _collapsed = false;
  bool _activated = false;
  (String, int)? _latestVisual;

  /// Inline canvas height. Fullscreen frames the canvas from their own
  /// constraints, so fullscreen measurements are deliberately not stored.
  double _height = 360;
  double? _inlineHeight;
  int _revision = 0;
  Timer? _timeout;

  /// The exact source-dialog route this visual opened, so disposal removes
  /// that route rather than popping whatever is currently on top.
  Route<dynamic>? _sourceRoute;

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
      // The fullscreen frame sizes the canvas from the overlay's constraints,
      // so only inline measurements resize the card. A `fullscreen-height`
      // report (including one arriving after exit) is a deliberate no-op.
      if (_full) return;
      final next = height.clamp(180.0, 560.0);
      if ((next - _height).abs() > 2) setState(() => _height = next);
    }
  }

  void _fullscreen(bool value) {
    if (value) {
      final box = _inlineContentKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) _inlineHeight = box.size.height;
      // A visual auto-folded by the scope may never have activated. Entering
      // fullscreen is the first chance to mount and run it; leaving fullscreen
      // must not trigger a load.
      if (!_activated) {
        _activated = true;
        if (widget.complete) unawaited(_load());
      }
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
    final sourceRoute = _sourceRoute;
    _sourceRoute = null;
    if (sourceRoute != null) _dismissSourceRoute(sourceRoute);
    super.dispose();
  }

  /// Removes only the route this visual owns. A navigator cannot be mutated
  /// from inside its own build, so defer to the end of the frame when needed.
  void _dismissSourceRoute(Route<dynamic> route) {
    void remove() {
      if (!route.isActive) return;
      route.navigator?.removeRoute(route);
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
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
            active: !_collapsed || _full,
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

  Future<void> _copySource() async {
    // A source dialog can outlive the moment its visual is removed; never
    // touch the clipboard or UI for a disposed state.
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    showAdaptiveFeedback(context: context, message: '已复制源码');
  }

  /// Draft popover rows: 42 px minimum, 10/8 px padding, 13 px labels,
  /// 17 px muted icons and a 10 px gap. The shared route clips each row's
  /// 7 px hover plate through `genAiMenuEntry`.
  PopupMenuItem<String> _menuItem(
    GenAiPalette palette,
    String value,
    String label,
    GenAiGlyph glyph, {
    bool enabled = true,
  }) =>
      PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            IconTheme.merge(
              data: IconThemeData(size: 17, color: palette.muted),
              child: GenAiIcon(glyph),
            ),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );

  Widget _moreMenu({required bool enabled}) {
    final palette = GenAiPalette.of(context);
    final items = <PopupMenuEntry<String>>[
      _menuItem(palette, 'rerun', '重新运行', GenAiGlyph.retry, enabled: enabled),
      _menuItem(palette, 'source', '查看源代码', GenAiGlyph.code),
      _menuItem(palette, 'copy', '复制内容', GenAiGlyph.copy),
    ];
    return Builder(
      builder: (anchorContext) => IconButton(
        tooltip: '更多操作',
        icon: const GenAiIcon(GenAiGlyph.more, size: 20),
        onPressed: () => unawaited(_openMoreMenu(anchorContext, items)),
      ),
    );
  }

  /// The popover can outlive a rebuild of this visual, so a late choice is
  /// applied only while this state element and its opening anchor are mounted
  /// and the code it acted on is still the current revision.
  Future<void> _openMoreMenu(
    BuildContext anchorContext,
    List<PopupMenuEntry<String>> items,
  ) async {
    final revision = _revision;
    final action = await genAiShowAnchoredMenu<String>(
      context: context,
      anchorContext: anchorContext,
      items: items,
      minWidth: 180,
      gap: 7,
      semanticLabel: '更多操作',
    );
    if (action == null || !mounted || !anchorContext.mounted || revision != _revision) {
      return;
    }
    switch (action) {
      case 'rerun':
        unawaited(_load());
      case 'source':
        unawaited(_showSource());
      case 'copy':
        unawaited(_copySource());
    }
  }

  /// The caller-provided label, or null when only the generic tag should show.
  /// HTML titles and headings are never inspected here.
  String? get _explicitTitle {
    final title = widget.title?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  Widget _cardHeader() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth <= _cardCompactBreakpoint;
          final title = _explicitTitle;
          final muted = Theme.of(context).colorScheme.onSurfaceVariant;
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.fromLTRB(compact ? 4 : 8, 5, compact ? 5 : 10, 5),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _toggleCollapsed,
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        padding: const EdgeInsets.all(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedRotation(
                            turns: _collapsed ? -0.25 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: GenAiIcon(
                              GenAiGlyph.down,
                              size: 15,
                              color: muted,
                            ),
                          ),
                          SizedBox(width: compact ? 7 : 9),
                          Flexible(
                            child: Text(
                              title ?? GenAiVisualDocument.defaultTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: title == null ? 11 : 13,
                                fontWeight: FontWeight.w400,
                                color: title == null ? muted : null,
                              ),
                            ),
                          ),
                          if (title != null) ...[
                            const SizedBox(width: 5),
                            Text(
                              GenAiVisualDocument.defaultTitle,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Fullscreen and more stay in the header while folded; only
                  // the body is hidden.
                  IconButton(
                    tooltip: '全屏',
                    onPressed: () => _fullscreen(true),
                    icon: const GenAiIcon(GenAiGlyph.full, size: 20),
                  ),
                  _moreMenu(enabled: widget.complete),
                ],
              ),
            ),
          );
        },
      );

  Widget _fullscreenHeader() => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _explicitTitle ?? GenAiVisualDocument.defaultTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '退出全屏',
                onPressed: () => _fullscreen(false),
                icon: const GenAiIcon(GenAiGlyph.close, size: 20),
              ),
            ],
          ),
        ),
      );

  /// Source opens in its own dialog; the inline canvas keeps running behind it.
  /// The view is 18px rounded, `min(500, screen - 32)` wide, with a titled
  /// header, a scrolling monospace body and a copy footer.
  Future<void> _showSource() async {
    final colors = Theme.of(context).colorScheme;
    try {
      await genAiShowDialog<void>(
        context: context,
        builder: (dialogContext) {
          // Track the exact route this visual owns; disposal removes this
          // route only, never whatever happens to be on top of the navigator.
          _sourceRoute = ModalRoute.of(dialogContext);
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              key: const ValueKey('genai-visual-source'),
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '示例源代码',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const GenAiIcon(GenAiGlyph.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText.rich(
                        TextSpan(
                          children: GenAiSyntaxHighlighter(
                            brightness: Theme.of(dialogContext).brightness,
                          ).highlight(code: widget.code, language: 'html'),
                        ),
                        contextMenuBuilder: genAiTextSelectionContextMenu,
                        style: TextStyle(
                          fontFamily: kGenAiMonospaceFamily,
                          fontFamilyFallback: kGenAiMonospaceFallback,
                          fontSize: 12,
                          height: 1.7,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _copySource,
                        icon: const GenAiIcon(GenAiGlyph.copy, size: 17),
                        label: const Text('复制'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _sourceRoute = null;
    }
  }

  EdgeInsets _inlinePadding(bool compact) => compact
      ? const EdgeInsets.fromLTRB(14, 18, 14, 16)
      : const EdgeInsets.fromLTRB(24, 24, 24, 18);

  Widget _inlineBody() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth <= _cardCompactBreakpoint;
          return Padding(
            padding: _inlinePadding(compact),
            child: SizedBox(height: _height, child: _canvas()),
          );
        },
      );

  Widget _fullscreenBody() => LayoutBuilder(
        builder: (context, constraints) {
          final compact = MediaQuery.sizeOf(context).width <= _mobileBreakpoint;
          // The frame owns vertical centring and scrolling. Never size it from
          // the inline measurement: its new width changes the content height.
          return Padding(
            key: const ValueKey('genai-visual-fullscreen-body'),
            padding: EdgeInsets.all(compact ? 12 : 24),
            child: SizedBox.expand(child: _canvas()),
          );
        },
      );

  Widget _content({required bool full}) => Column(
        key: full ? null : _inlineContentKey,
        mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          full ? _fullscreenHeader() : _cardHeader(),
          if (!_collapsed || full) const Divider(height: 1),
          if (full)
            Expanded(child: _fullscreenBody())
          else
            Offstage(
              offstage: _collapsed,
              child: _full || !_activated ? const SizedBox.shrink() : _inlineBody(),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) {
        final view = MediaQuery.sizeOf(context);
        final compact = view.width <= _mobileBreakpoint;
        final width = compact ? view.width : math.min(view.width - 40, _fullscreenMaxWidth);
        final height = compact ? view.height : view.height - 40;
        return Positioned.fill(
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
                    color: compact
                        ? palette.canvas
                        : Theme.of(context).colorScheme.scrim.withValues(alpha: .32),
                    child: Center(
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Material(
                          key: const ValueKey('genai-visual-fullscreen'),
                          color: palette.raised,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(compact ? 0 : 18),
                          ),
                          child: SafeArea(child: _content(full: true)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth <= _cardCompactBreakpoint;
          return Container(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: palette.raised,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(compact ? _cardRadiusCompact : _cardRadius),
            ),
            child: _full ? SizedBox(height: _inlineHeight ?? _height + 49) : _content(full: false),
          );
        },
      ),
    );
  }
}
