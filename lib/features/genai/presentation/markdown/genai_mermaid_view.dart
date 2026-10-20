import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';

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
  final TransformationController _transformController =
      TransformationController();
  bool _showCode = false;
  bool _copied = false;
  String? _renderError;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  @override
  void didUpdateWidget(GenAiMermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _renderError = null;
      _resetZoom();
    }
  }

  Future<void> _copyCode() async {
    setState(() => _copied = true);
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  String _detectDiagramType(String code) {
    for (final line in code.split('\n')) {
      final trimmed = line.trim().toLowerCase();
      if (trimmed.isEmpty || trimmed.startsWith('%%')) {
        continue;
      }
      if (trimmed.startsWith('graph') || trimmed.startsWith('flowchart')) {
        return '流程图';
      }
      if (trimmed.startsWith('sequencediagram')) {
        return '时序图';
      }
      if (trimmed.startsWith('classdiagram')) {
        return '类图';
      }
      if (trimmed.startsWith('statediagram')) {
        return '状态图';
      }
      if (trimmed.startsWith('pie')) {
        return '饼图';
      }
      if (trimmed.startsWith('gantt')) {
        return '甘特图';
      }
      if (trimmed.startsWith('timeline')) {
        return '时间线';
      }
      if (trimmed.startsWith('kanban')) {
        return '看板';
      }
      if (trimmed.startsWith('gitgraph')) {
        return 'Git 图';
      }
      break;
    }
    return 'Mermaid 图表';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .06);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: .03)
        : Colors.black.withValues(alpha: .02);
    final diagramType = _detectDiagramType(widget.code);

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: .06)
                      : Colors.black.withValues(alpha: .04),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Mermaid 图表',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          diagramType,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_showCode && _renderError == null)
                  Tooltip(
                    message: '重置视角',
                    child: InkWell(
                      onTap: _resetZoom,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.restart_alt_rounded,
                          size: 16,
                          color: theme.hintColor,
                        ),
                      ),
                    ),
                  ),
                Tooltip(
                  message: _showCode ? '切换到图表' : '查看源码',
                  child: InkWell(
                    onTap: () => setState(() => _showCode = !_showCode),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _showCode ? Icons.schema_outlined : Icons.code_rounded,
                        size: 16,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: _copied ? '已复制' : '复制代码',
                  child: InkWell(
                    onTap: _copyCode,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                        color: _copied
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                      ),
                    ),
                  ),
                ),
              ],
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
                  fontFamily: 'RobotoMono',
                  fontFamilyFallback: ['monospace', 'Menlo'],
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ] else
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 140,
                  maxHeight: 380,
                ),
                padding: const EdgeInsets.all(12),
                child: InteractiveViewer(
                  transformationController: _transformController,
                  boundaryMargin: const EdgeInsets.all(40),
                  minScale: 0.5,
                  maxScale: 3.5,
                  clipBehavior: Clip.hardEdge,
                  child: Center(
                    child: MermaidDiagram(
                      code: normalizeMermaid(widget.code),
                      style:
                          isDark ? MermaidStyle.dark() : const MermaidStyle(),
                      onError: (error) {
                        if (mounted) {
                          setState(() => _renderError = error);
                        }
                      },
                      errorBuilder: (context, error) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '无法渲染图表: $error',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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

  final lines = cleanedSource.split('\n');
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
      if (line.isEmpty ||
          line.startsWith('%%') ||
          line.toLowerCase().startsWith('statediagram')) {
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
      if (line.isEmpty ||
          line.startsWith('%%') ||
          line.toLowerCase().startsWith('classdiagram')) {
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
        final bracketMatch =
            RegExp(r'^([^\s\[]+)\s*\[(.+)\]$').firstMatch(cleanLabel);
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
