import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';

import 'genai_code_font.dart';
import 'genai_copy_button.dart';

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
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                leading: const CloseButton(),
                title: const Text('Mermaid 图表', maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(
                    tooltip: '缩小',
                    onPressed: () => canvasKey.currentState?.zoom(.8),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: '放大',
                    onPressed: () => canvasKey.currentState?.zoom(1.25),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: '适应窗口',
                    onPressed: () => canvasKey.currentState?.fit(),
                    icon: const Icon(Icons.fit_screen),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor =
        isDark ? Colors.white.withValues(alpha: .08) : Colors.black.withValues(alpha: .06);
    final cardBg =
        isDark ? Colors.white.withValues(alpha: .03) : Colors.black.withValues(alpha: .02);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: .06)
                      : Colors.black.withValues(alpha: .04),
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = Row(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Mermaid 图表',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_showCode && _renderError == null) ...[
                      IconButton(
                        tooltip: '适应窗口',
                        onPressed: () => _canvasKey.currentState?.fit(),
                        icon: const Icon(Icons.fit_screen, size: 20),
                      ),
                      IconButton(
                        tooltip: '全屏查看',
                        onPressed: _openFullscreen,
                        icon: const Icon(Icons.fullscreen, size: 20),
                      ),
                    ],
                    IconButton(
                      tooltip: _showCode ? '切换到图表' : '查看源码',
                      onPressed: () => setState(() => _showCode = !_showCode),
                      icon: Icon(_showCode ? Icons.schema_outlined : Icons.code_rounded, size: 20),
                    ),
                    GenAiCopyButton(text: widget.code, tooltip: '复制源码'),
                  ],
                );
                final compact =
                    constraints.maxWidth < 332 * MediaQuery.textScalerOf(context).scale(13) / 13;
                return compact && !_showCode && _renderError == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title,
                          const SizedBox(height: 4),
                          Align(alignment: Alignment.centerRight, child: actions),
                        ],
                      )
                    : Row(children: [Expanded(child: title), actions]);
              },
            ),
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
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mermaid 语法解析未完成: $_renderError',
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
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
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
    }
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
    final dark = Theme.of(context).brightness == Brightness.dark;
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
                color: Color((dark ? MermaidStyle.dark() : const MermaidStyle()).backgroundColor),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MermaidDiagram(
                    code: normalizeMermaid(widget.code),
                    enableResponsive: false,
                    style: dark ? MermaidStyle.dark() : const MermaidStyle(),
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

  final idMap = <String, String>{};
  final hasExplicitLabel = <String, bool>{};
  var idCounter = 0;

  String getSafeId(String rawId) {
    return idMap.putIfAbsent(rawId, () => 'n${idCounter++}');
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
          final safeId = 'sub_${idCounter++}';
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
