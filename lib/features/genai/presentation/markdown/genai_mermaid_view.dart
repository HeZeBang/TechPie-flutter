import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';

import '../../../../widgets/adaptive_feedback.dart';
import '../../../../widgets/adaptive_page_navigation.dart';
import '../genai_icons.dart';
import '../genai_theme.dart';
import 'genai_code_font.dart';
import 'genai_mermaid_painter.dart';

class GenAiMermaidView extends StatefulWidget {
  const GenAiMermaidView({
    super.key,
    required this.code,
  });

  final String code;

  @override
  State<GenAiMermaidView> createState() => _GenAiMermaidViewState();
}

class _GenAiMermaidViewState extends State<GenAiMermaidView> {
  final _canvasKey = GlobalKey<_MermaidCanvasState>();
  bool _showCode = false;
  String? _renderError;

  Future<void> _openFullscreen() async {
    final canvasKey = GlobalKey<_MermaidCanvasState>();
    await pushAdaptivePage<void>(
      context,
      rootNavigator: true,
      builder: (context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const GenAiIcon(GenAiGlyph.close),
              ),
              title: const Text('Mermaid 图表', maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: '缩小',
                  onPressed: () => canvasKey.currentState?.zoom(.8),
                  icon: const GenAiIcon(GenAiGlyph.zoomOut),
                ),
                IconButton(
                  tooltip: '放大',
                  onPressed: () => canvasKey.currentState?.zoom(1.25),
                  icon: const GenAiIcon(GenAiGlyph.zoomIn),
                ),
                IconButton(
                  tooltip: '适应窗口',
                  onPressed: () => canvasKey.currentState?.fit(),
                  icon: const GenAiIcon(GenAiGlyph.fit),
                ),
              ],
            ),
            body: SafeArea(
              child: _MermaidCanvas(
                key: canvasKey,
                code: widget.code,
                fullscreen: true,
                initialView: _canvasKey.currentState?.view,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(GenAiMermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _renderError = null;
    }
  }

  Future<void> _openMenu(BuildContext anchor) async {
    final code = widget.code;
    final action = await genAiShowMenu<String>(
      context: context,
      anchorContext: anchor,
      semanticLabel: '图表操作',
      minWidth: 180,
      items: [
        if (!_showCode && _renderError == null)
          const PopupMenuItem(value: 'fit', child: Text('适应窗口')),
        PopupMenuItem(value: 'source', child: Text(_showCode ? '切换到图表' : '查看源码')),
        const PopupMenuItem(value: 'copy', child: Text('复制源码')),
      ],
    );
    if (!mounted || widget.code != code) return;
    switch (action) {
      case 'fit':
        _canvasKey.currentState?.fit();
      case 'source':
        setState(() => _showCode = !_showCode);
      case 'copy':
        try {
          await Clipboard.setData(ClipboardData(text: code));
          if (mounted) showAdaptiveFeedback(context: context, message: '已复制');
        } catch (_) {
          if (mounted) showAdaptiveFeedback(context: context, message: '无法复制，请手动选择文字');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = GenAiPalette.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GenAiContentHeader(
            title: 'Mermaid 图表',
            leading: GenAiIcon(GenAiGlyph.diagram, size: 16, color: palette.accent),
            actions: [
              if (!_showCode && _renderError == null)
                IconButton(
                  tooltip: '全屏查看',
                  onPressed: _openFullscreen,
                  icon: const GenAiIcon(GenAiGlyph.full, size: 20),
                ),
              Builder(
                builder: (anchor) => IconButton(
                  tooltip: '更多操作',
                  icon: const GenAiIcon(GenAiGlyph.more, size: 20),
                  onPressed: () => _openMenu(anchor),
                ),
              ),
            ],
          ),

          // Body
          if (_showCode || _renderError != null) ...[
            if (_renderError != null)
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    GenAiIcon(
                      GenAiGlyph.warning,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mermaid 图表无法渲染，已显示源码：$_renderError',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: SelectableText(
                widget.code,
                style: const TextStyle(
                  fontFamily: kGenAiMonospaceFamily,
                  fontFamilyFallback: kGenAiMonospaceFallback,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ] else
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: _MermaidCanvas(
                key: _canvasKey,
                code: widget.code,
                onError: (error) {
                  if (_renderError != error) setState(() => _renderError = error);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Minimalist draft treatment for flutter_mermaid's pure-Dart painters.
///
/// Every color is a [GenAiPalette] role, so light, dark, AMOLED, dynamic-color
/// and iOS-accent settings carry into the diagram. Only what [MermaidStyle]
/// exposes is set: 1px [GenAiPalette.line] node borders with a 9px radius,
/// 13px regular-weight [GenAiPalette.text] labels on a soft fill, and 1.15px
/// [GenAiPalette.muted] edges whose 11.5px labels sit on a raised chip so a
/// line never strikes through its own text. Spacing is widened for breathing
/// room; node interior padding is fixed by the package's node measurement.
MermaidStyle _mermaidStyle(GenAiPalette palette, {required bool dark}) {
  return MermaidStyle(
    backgroundColor: palette.raised.toARGB32(),
    defaultNodeStyle: NodeStyle(
      fillColor: (dark
              ? Color.alphaBlend(palette.text.withValues(alpha: .06), palette.raised)
              : palette.soft)
          .toARGB32(),
      strokeColor: palette.line.toARGB32(),
      strokeWidth: 1,
      textColor: palette.text.toARGB32(),
      fontSize: 13,
      fontWeight: FontWeight.w400,
      borderRadius: 9,
    ),
    defaultEdgeStyle: EdgeStyle(
      strokeColor: palette.muted.toARGB32(),
      strokeWidth: 1.15,
      labelColor: palette.muted.toARGB32(),
      labelFontSize: 11.5,
      labelBackgroundColor: palette.raised.toARGB32(),
    ),
    nodeSpacingX: 56,
    nodeSpacingY: 56,
    padding: 28,
    themeMode: dark ? MermaidThemeMode.dark : MermaidThemeMode.light,
  );
}

/// Preserve the renderer's natural canvas: viewport constraints must never
/// truncate nodes before the user can pan to them.
class _MermaidCanvas extends StatefulWidget {
  const _MermaidCanvas({
    super.key,
    required this.code,
    this.fullscreen = false,
    this.onError,
    this.initialView,
  });

  final String code;
  final bool fullscreen;
  final ValueChanged<String>? onError;
  final (double, Offset)? initialView;

  @override
  State<_MermaidCanvas> createState() => _MermaidCanvasState();
}

class _MermaidCanvasState extends State<_MermaidCanvas> {
  final _transform = TransformationController();
  Size _naturalSize = Size.zero;
  Size _viewport = Size.zero;

  /// Normalization and the derived style are pure functions of the source and
  /// the palette. Memoizing them keeps every rebuild from re-running the
  /// source rewrite or allocating a fresh (never equal) [MermaidStyle].
  String? _normalizedCode;
  String? _styleKey;
  MermaidStyle? _style;

  String get _normalized => _normalizedCode ??= normalizeMermaid(widget.code);

  (double, Offset) get view => (
        _transform.value.getMaxScaleOnAxis(),
        _transform.toScene(_viewport.center(Offset.zero)),
      );

  void _restoreView((double, Offset) view) {
    final scale = view.$1.clamp(_fitScale, 8.0);
    final center = _viewport.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx - view.$2.dx * scale, center.dy - view.$2.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  void initState() {
    super.initState();
    _transform.addListener(_constrainPan);
  }

  // Clamp every transform, including pinch/wheel zoom, button zoom and inertia.
  // Small axes stay centered; large axes can move only between their edges.
  void _constrainPan() {
    if (_naturalSize.isEmpty || _viewport.isEmpty) return;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    double clampAxis(double offset, double content, double viewport) {
      final remaining = viewport - content * scale;
      return remaining >= 0 ? remaining / 2 : offset.clamp(remaining, 0.0);
    }

    final x = clampAxis(matrix.entry(0, 3), _naturalSize.width, _viewport.width);
    final y = clampAxis(matrix.entry(1, 3), _naturalSize.height, _viewport.height);
    if (x == matrix.entry(0, 3) && y == matrix.entry(1, 3)) return;
    _transform.value = matrix.clone()
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
  }

  @override
  void dispose() {
    _transform.removeListener(_constrainPan);
    _transform.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_MermaidCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _naturalSize = Size.zero;
      _viewport = Size.zero;
      _normalizedCode = null;
    }
  }

  /// Returns the same instance while the palette roles and brightness are
  /// unchanged, so [GenAiMermaidDiagram]'s style-keyed layout cache can hit.
  /// [MermaidStyle] has no value equality, so identity is the invalidation.
  MermaidStyle _resolveStyle(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final key = '${palette.raised.toARGB32()}:${palette.soft.toARGB32()}:'
        '${palette.line.toARGB32()}:${palette.text.toARGB32()}:'
        '${palette.muted.toARGB32()}:$dark';
    if (_styleKey != key) {
      _styleKey = key;
      _style = _mermaidStyle(palette, dark: dark);
    }
    return _style!;
  }

  double get _fitScale => _naturalSize.isEmpty || _viewport.isEmpty
      ? 1
      : math.min(
          1,
          math.min(_viewport.width / _naturalSize.width, _viewport.height / _naturalSize.height),
        );

  double _readingScale(double width) =>
      _naturalSize.isEmpty ? 1 : (width / _naturalSize.width).clamp(.65, 1.0);

  void _position(double scale, {bool centerVertically = false}) {
    final x = math.max(0.0, (_viewport.width - _naturalSize.width * scale) / 2);
    final y = centerVertically
        ? math.max(0.0, (_viewport.height - _naturalSize.height * scale) / 2)
        : 0.0;
    _transform.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void fit() => _position(_fitScale, centerVertically: true);

  void zoom(double factor) {
    final center = _viewport.center(Offset.zero);
    final scene = _transform.toScene(center);
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(_fitScale, 8.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx - scene.dx * scale, center.dy - scene.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxHeight = (MediaQuery.sizeOf(context).height * .65).clamp(240.0, 720.0);
        final height = widget.fullscreen
            ? constraints.maxHeight
            : (_naturalSize.height * _readingScale(width)).clamp(180.0, maxHeight);
        final viewport = Size(width, height);
        if (_viewport != viewport) {
          final previous = _viewport.isEmpty ? widget.initialView : view;
          _viewport = viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _viewport != viewport) return;
            if (previous == null) {
              _position(_readingScale(viewport.width));
            } else {
              _restoreView(previous);
            }
          });
        }
        return SizedBox(
          height: height,
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            alignment: Alignment.topLeft,
            // Flutter's finite boundary also imposes a minimum cover scale,
            // preventing fit-to-window for tall/wide diagrams. Clamp pan per
            // axis in the controller instead, while retaining independent zoom.
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: _fitScale,
            maxScale: 8,
            child: _CanvasSizeObserver(
              key: ValueKey(widget.code),
              onSize: (size) {
                if (_naturalSize == size) return;
                setState(() {
                  _naturalSize = size;
                  _viewport = Size.zero;
                });
              },
              // Leave room for arrowheads and curved return edges painted
              // just outside the renderer's node bounds.
              child: ColoredBox(
                color: Color(style.backgroundColor),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GenAiMermaidDiagram(
                    code: _normalized,
                    style: style,
                    onError: (error) {
                      final code = widget.code;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && widget.code == code) widget.onError?.call(error);
                      });
                    },
                    errorBuilder: (context, error) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '无法渲染图表',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CanvasSizeObserver extends SingleChildRenderObjectWidget {
  const _CanvasSizeObserver({super.key, required this.onSize, required super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _CanvasSizeRenderBox(onSize);

  @override
  void updateRenderObject(BuildContext context, covariant _CanvasSizeRenderBox renderObject) {
    renderObject.onSize = onSize;
  }
}

class _CanvasSizeRenderBox extends RenderProxyBox {
  _CanvasSizeRenderBox(this.onSize);
  ValueChanged<Size> onSize;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_lastSize == size) return;
    _lastSize = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}

/// Normalizes AI-generated or imperfect Mermaid diagrams so they parse cleanly
/// with [MermaidParser] in flutter_mermaid.
///
/// Handles:
/// - Converting classDiagram and stateDiagram to equivalent flowchart constructs
/// - Auto-generating missing graph/flowchart headers
/// - Stripping trailing semicolons and inline comments
/// - Normalizing `A -- text --> B` and `A == text ==> B` into `A -->|text| B` and `A ==>|text| B`
/// - Converting non-ASCII, Chinese, hyphenated, and dot-containing node IDs into safe ASCII identifiers
///   while preserving visual labels
/// - Normalizing Chinese/quoted subgraphs into `subgraph sub_x [Label]`
String normalizeMermaid(String source) {
  var cleanedSource = source.trim();
  if (cleanedSource.startsWith('```')) {
    final firstNewline = cleanedSource.indexOf('\n');
    if (firstNewline != -1) {
      cleanedSource = cleanedSource.substring(firstNewline + 1).trim();
    }
  }
  if (cleanedSource.endsWith('```')) {
    cleanedSource = cleanedSource.substring(0, cleanedSource.length - 3).trim();
  }

  final lines = _splitMermaidStatements(cleanedSource);
  final resultLines = <String>[];

  var isStateDiagram = false;
  var isClassDiagram = false;
  var hasHeader = false;

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || trimmed.startsWith('%%')) continue;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('statediagram')) {
      isStateDiagram = true;
      hasHeader = true;
      break;
    } else if (lower.startsWith('classdiagram')) {
      isClassDiagram = true;
      hasHeader = true;
      break;
    } else if (lower.startsWith('graph') ||
        lower.startsWith('flowchart') ||
        lower.startsWith('sequencediagram') ||
        lower.startsWith('pie') ||
        lower.startsWith('gantt') ||
        lower.startsWith('timeline') ||
        lower.startsWith('kanban') ||
        lower.startsWith('radar-beta') ||
        lower.startsWith('xychart')) {
      hasHeader = true;
      break;
    }
  }

  final firstNonEmpty = lines
      .map((l) => l.trim().toLowerCase())
      .firstWhere((l) => l.isNotEmpty && !l.startsWith('%%'), orElse: () => '');
  if (firstNonEmpty.startsWith('sequencediagram') ||
      firstNonEmpty.startsWith('pie') ||
      firstNonEmpty.startsWith('gantt') ||
      firstNonEmpty.startsWith('timeline') ||
      firstNonEmpty.startsWith('kanban') ||
      firstNonEmpty.startsWith('radar-beta') ||
      firstNonEmpty.startsWith('xychart')) {
    return cleanedSource;
  }

  // A generated ID must never shadow one that already exists in the source.
  // Without this, `n0[Start] --> 中文[结束]` maps 中文 onto the existing n0 and
  // the two nodes collapse. Reserve every identifier-looking token up front,
  // including labels, because skipping an extra counter value is harmless.
  final usedIds = <String>{
    for (final match in RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(cleanedSource))
      match.group(0)!,
  };
  final idMap = <String, String>{};
  final hasExplicitLabel = <String, bool>{};
  var idCounter = 0;

  String nextGeneratedId(String prefix) {
    String candidate;
    do {
      candidate = '$prefix${idCounter++}';
    } while (usedIds.contains(candidate));
    usedIds.add(candidate);
    return candidate;
  }

  String getSafeId(String rawId) {
    return idMap.putIfAbsent(rawId, () => nextGeneratedId('n'));
  }

  bool needsSafeId(String id) {
    return !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(id);
  }

  String normalizeToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return token;

    final shapeMatch = RegExp(
      r'^([^\s\[\(\{>]+)(\(\(.*\)\)|\{\{.*\}\}|\[\[.*\]\]|\[\(.*\)\]|\(\[.*\]\)|\[/.+[/\\]\]|\[\\.+[/\\]\]|\[.*\]|\(.*\)|\{.*\}|>.*\])$',
      dotAll: true,
    ).firstMatch(trimmed);

    if (shapeMatch != null) {
      final rawId = shapeMatch.group(1)!;
      final shapeAndLabel = shapeMatch.group(2)!;
      hasExplicitLabel[rawId] = true;
      if (needsSafeId(rawId)) {
        final safeId = getSafeId(rawId);
        return '$safeId$shapeAndLabel';
      }
      return trimmed;
    }

    if (needsSafeId(trimmed)) {
      final safeId = getSafeId(trimmed);
      if (hasExplicitLabel[trimmed] == true) {
        return safeId;
      } else {
        hasExplicitLabel[trimmed] = true;
        return '$safeId[$trimmed]';
      }
    }

    return trimmed;
  }

  if (isStateDiagram) {
    resultLines.add('flowchart TD');
    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('%%') || line.toLowerCase().startsWith('statediagram')) {
        continue;
      }
      line = line.replaceAll('[*]', 'state_terminal((●))');
      if (line.contains(':')) {
        final colonIdx = line.indexOf(':');
        final transition = line.substring(0, colonIdx).trim();
        final event = line.substring(colonIdx + 1).trim();
        if (transition.contains('-->')) {
          final parts = transition.split('-->');
          line = '${parts[0].trim()} -->|$event| ${parts[1].trim()}';
        }
      }
      resultLines.add('  $line');
    }
  } else if (isClassDiagram) {
    resultLines.add('flowchart TD');
    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('%%') || line.toLowerCase().startsWith('classdiagram')) {
        continue;
      }
      if (line.contains('<|--')) {
        final parts = line.split('<|--');
        line = '${parts[0].trim()} -->|继承| ${parts[1].trim()}';
      } else if (line.contains('*--')) {
        final parts = line.split('*--');
        line = '${parts[0].trim()} -->|包含| ${parts[1].trim()}';
      } else if (line.contains('o--')) {
        final parts = line.split('o--');
        line = '${parts[0].trim()} -->|聚合| ${parts[1].trim()}';
      } else if (line.contains('-->')) {
        // preserve
      } else if (line.contains(':') || line.startsWith('class ')) {
        continue;
      }
      resultLines.add('  $line');
    }
  } else {
    if (!hasHeader) {
      resultLines.add('flowchart TD');
    }

    for (final rawLine in lines) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('%%')) continue;

      if (line.endsWith(';')) {
        line = line.substring(0, line.length - 1).trimRight();
      }

      if (line.toLowerCase().startsWith('subgraph')) {
        final content = line.substring(8).trim();
        var cleanLabel = content;
        if ((cleanLabel.startsWith('"') && cleanLabel.endsWith('"')) ||
            (cleanLabel.startsWith("'") && cleanLabel.endsWith("'"))) {
          cleanLabel = cleanLabel.substring(1, cleanLabel.length - 1).trim();
        }
        final bracketMatch = RegExp(r'^([^\s\[]+)\s*\[(.+)\]$').firstMatch(cleanLabel);
        if (bracketMatch != null) {
          final rawId = bracketMatch.group(1)!;
          final label = bracketMatch.group(2)!;
          final safeId = needsSafeId(rawId) ? getSafeId(rawId) : rawId;
          resultLines.add('  subgraph $safeId [$label]');
        } else {
          final safeId = nextGeneratedId('sub_');
          resultLines.add('  subgraph $safeId [$cleanLabel]');
        }
        continue;
      }

      line = line.replaceAllMapped(
        RegExp(r'--\s*([^->\n|]+?)\s*-->'),
        (m) => '-->|${m[1]!.trim()}|',
      );
      line = line.replaceAllMapped(
        RegExp(r'==\s*([^=>\n|]+?)\s*==>'),
        (m) => '==>|${m[1]!.trim()}|',
      );

      final arrowPattern = RegExp(
        r'(\s*(?:==>|-->|---|\.\.\.|===|-.->|-\.-*>|---->|====)\s*(?:\|[^|]*\|)?\s*)',
      );
      if (arrowPattern.hasMatch(line)) {
        final parts = line.split(arrowPattern);
        final matches = arrowPattern.allMatches(line).toList();

        final newParts = parts.map(normalizeToken).toList();
        final buf = StringBuffer();
        for (var i = 0; i < newParts.length; i++) {
          buf.write(newParts[i]);
          if (i < matches.length) {
            buf.write(matches[i].group(0));
          }
        }
        line = buf.toString();
      } else if (!line.toLowerCase().startsWith('graph') &&
          !line.toLowerCase().startsWith('flowchart') &&
          line != 'end') {
        line = normalizeToken(line);
      }

      resultLines.add(line);
    }
  }

  return resultLines.join('\n');
}

/// Semicolons separate statements only outside labels and comments.
List<String> _splitMermaidStatements(String source) {
  final result = <String>[];
  var buffer = StringBuffer();
  var depth = 0;
  String? quote;
  var edgeLabel = false;
  var comment = false;
  var escaped = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (char == '\n') {
      result.add(buffer.toString());
      buffer = StringBuffer();
      comment = false;
      escaped = false;
      continue;
    }
    if (!comment && quote == null && char == '%' && i + 1 < source.length && source[i + 1] == '%') {
      comment = true;
    }
    if (!comment) {
      if (quote != null) {
        if (char == quote && !escaped) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '|') {
        edgeLabel = !edgeLabel;
      } else if ('[({'.contains(char)) {
        depth++;
      } else if ('])}'.contains(char) && depth > 0) {
        depth--;
      } else if (char == ';' && depth == 0 && !edgeLabel) {
        result.add(buffer.toString());
        buffer = StringBuffer();
        continue;
      }
    }
    escaped = char == r'\' && !escaped;
    buffer.write(char);
  }
  result.add(buffer.toString());
  return result;
}
