import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mermaid/flutter_mermaid.dart';

/// The draft's smaller arrowheads: flutter_mermaid hardcodes a 10px head in
/// [MermaidPainter.drawArrowHead], so the head is drawn at the origin and the
/// canvas is scaled around it. The stroke width is compensated inside the
/// scaled frame and restored afterwards, keeping the edge itself untouched.
const double _arrowScale = .65;

mixin _SmallArrowHeads on MermaidPainter {
  @override
  void drawArrowHead(
    Canvas canvas,
    Offset position,
    double angle,
    ArrowType type,
    Paint paint,
  ) {
    final strokeWidth = paint.strokeWidth;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.scale(_arrowScale);
    paint.strokeWidth = strokeWidth / _arrowScale;
    super.drawArrowHead(canvas, Offset.zero, angle, type, paint);
    canvas.restore();
    paint.strokeWidth = strokeWidth;
  }
}

/// Renders Mermaid flowcharts and sequence diagrams with the GenAI draft
/// instead of flutter_mermaid's stock presets.
///
/// Parsing, layout and natural canvas sizing stay the package's own
/// ([MermaidParser], [DagreLayout], [SequenceLayout]); every other diagram
/// type falls through to [MermaidDiagram] unchanged.
///
/// Parsing depends only on the source and layout only on the parsed diagram,
/// the style and the available width, so both are cached per widget state
/// under exactly those keys. The caches are bounded and widget-local: a
/// rebuild reuses a result, but a changed source, style or width always
/// invalidates the entry it would otherwise read.
class GenAiMermaidDiagram extends StatefulWidget {
  const GenAiMermaidDiagram({
    super.key,
    required this.code,
    required this.style,
    this.onError,
    this.errorBuilder,
  });

  final String code;
  final MermaidStyle style;
  final ValueChanged<String>? onError;
  final Widget Function(BuildContext context, String error)? errorBuilder;

  @override
  State<GenAiMermaidDiagram> createState() => _GenAiMermaidDiagramState();
}

class _GenAiMermaidDiagramState extends State<GenAiMermaidDiagram> {
  /// Small enough that a streaming message cannot grow the cache unbounded,
  /// large enough to cover the inline/fullscreen widths of one diagram.
  static const _cacheLimit = 6;

  final _parsed = <String, _MermaidParse>{};
  final _layouts = <(MermaidDiagramData, MermaidStyle, double), _MermaidLayout>{};

  static V _cached<K, V>(Map<K, V> cache, K key, V Function() create) {
    final hit = cache.remove(key);
    if (hit != null) {
      cache[key] = hit;
      return hit;
    }
    final value = create();
    cache[key] = value;
    while (cache.length > _cacheLimit) {
      cache.remove(cache.keys.first);
    }
    return value;
  }

  _MermaidParse _parse(String code) => _cached(
        _parsed,
        code,
        () {
          try {
            final result = const MermaidParser().parseWithData(code);
            if (result == null) throw const FormatException('Unable to parse diagram');
            return _MermaidParse.diagram(result.diagram);
          } catch (error) {
            return _MermaidParse.failure(error.toString());
          }
        },
      );

  _MermaidLayout _layout(MermaidDiagramData diagram, MermaidStyle style, double width) =>
      _cached(
        _layouts,
        (diagram, style, width),
        () {
          final styled = _withDraftSubgraphs(diagram, style);
          final Size natural;
          final CustomPainter painter;
          if (styled.type == DiagramType.flowchart) {
            natural = const DagreLayout()
                .computeLayout(styled, style, Size(width, 600));
            painter = GenAiFlowchartPainter(diagram: styled, style: style);
          } else {
            natural = const SequenceLayout()
                .computeLayout(styled, style, Size(width, 600));
            painter = GenAiSequencePainter(diagram: styled, style: style);
          }
          return _MermaidLayout(natural, painter);
        },
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final parsed = _parse(widget.code);
        final failure = parsed.failure;
        if (failure != null) {
          widget.onError?.call(failure);
          return widget.errorBuilder?.call(context, failure) ??
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '无法渲染图表',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              );
        }

        final diagram = parsed.diagram!;
        if (diagram.type != DiagramType.flowchart &&
            diagram.type != DiagramType.sequence) {
          return MermaidDiagram(
            code: widget.code,
            style: widget.style,
            enableResponsive: false,
            onError: widget.onError,
            errorBuilder: widget.errorBuilder,
          );
        }

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final layout = _layout(diagram, widget.style, availableWidth);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : layout.natural.width;
        return Container(
          width: layout.natural.width.clamp(0.0, maxWidth),
          height: layout.natural.height,
          color: Color(widget.style.backgroundColor),
          child: CustomPaint(painter: layout.painter, size: layout.natural),
        );
      },
    );
  }

  /// The package paints subgraphs with hardcoded gray defaults; give them the
  /// same palette roles as nodes while layout still reads the diagram.
  MermaidDiagramData _withDraftSubgraphs(
    MermaidDiagramData diagram,
    MermaidStyle style,
  ) {
    if (diagram.subgraphs.isEmpty) return diagram;
    final node = style.defaultNodeStyle;
    return diagram.copyWith(
      subgraphs: [
        for (final subgraph in diagram.subgraphs)
          Subgraph(
            id: subgraph.id,
            label: subgraph.label,
            nodeIds: subgraph.nodeIds,
            style: SubgraphStyle(
              backgroundColor: node.fillColor,
              borderColor: node.strokeColor,
              borderWidth: node.strokeWidth,
              borderRadius: node.borderRadius,
            ),
          ),
      ],
    );
  }
}

/// A successful parse, or the message the renderer reports for a failure.
class _MermaidParse {
  const _MermaidParse.diagram(this.diagram) : failure = null;
  const _MermaidParse.failure(this.failure) : diagram = null;

  final MermaidDiagramData? diagram;
  final String? failure;
}

class _MermaidLayout {
  const _MermaidLayout(this.natural, this.painter);

  final Size natural;
  final CustomPainter painter;
}

/// Flowcharts inherit flutter_mermaid's paint wholesale; only the arrowhead
/// size changes.
class GenAiFlowchartPainter extends FlowchartPainter with _SmallArrowHeads {
  const GenAiFlowchartPainter({
    required super.diagram,
    required super.style,
    super.deviceConfig,
  });
}

/// Sequence diagrams reimplement [SequencePainter.paint] because the package's
/// participant, lifeline and actor helpers are private and hardcode the stock
/// pastel palette. Geometry matches the package so [SequenceLayout] and the
/// natural canvas stay authoritative; only the drawing is draft-styled.
class GenAiSequencePainter extends SequencePainter with _SmallArrowHeads {
  const GenAiSequencePainter({
    required super.diagram,
    required super.style,
    super.deviceConfig,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (diagram.nodes.isEmpty) return;

    final messageSpacing = deviceConfig?.messageSpacing ?? 50.0;
    final messageStartOffset = messageSpacing * .8;
    final first = diagram.nodes.first;
    final messageStartY = first.y + first.height + messageStartOffset;
    final bottomY = messageStartY + diagram.edges.length * messageSpacing + 20;

    final edgeStyle = style.defaultEdgeStyle;
    final lifelinePaint = Paint()
      ..color = Color(edgeStyle.strokeColor ?? MermaidColors.defaultEdgeColor)
      ..strokeWidth = edgeStyle.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final node in diagram.nodes) {
      _drawLifeline(canvas, node, messageStartY - 10, bottomY, lifelinePaint);
    }

    final nodeStyle = style.defaultNodeStyle;
    for (final node in diagram.nodes) {
      _drawParticipant(canvas, node, node.y, nodeStyle);
    }

    var messageY = messageStartY;
    for (final edge in diagram.edges) {
      _drawMessage(canvas, edge, messageY);
      messageY += messageSpacing;
    }

    for (final node in diagram.nodes) {
      _drawParticipant(canvas, node, bottomY, nodeStyle);
    }
  }

  void _drawLifeline(
    Canvas canvas,
    MermaidNode node,
    double startY,
    double endY,
    Paint paint,
  ) {
    final x = node.x + node.width / 2;
    const dashLength = 6.0;
    const gapLength = 5.0;
    var y = startY;
    while (y < endY) {
      final end = math.min(y + dashLength, endY);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y = end + gapLength;
    }
  }

  void _drawParticipant(
    Canvas canvas,
    MermaidNode node,
    double top,
    NodeStyle nodeStyle,
  ) {
    final rect = Rect.fromLTWH(node.x, top, node.width, node.height);
    if (node is SequenceParticipant && node.participantType == ParticipantType.actor) {
      _drawActor(canvas, node, rect, nodeStyle);
      return;
    }

    final fill = nodeStyle.fillColor ?? style.backgroundColor;
    final stroke = nodeStyle.strokeColor ?? MermaidColors.defaultNodeStroke;
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(nodeStyle.borderRadius),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Color(fill)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Color(stroke)
        ..style = PaintingStyle.stroke
        ..strokeWidth = nodeStyle.strokeWidth,
    );
    drawText(
      canvas,
      node.label,
      rect.center,
      TextStyle(
        color: Color(nodeStyle.textColor ?? MermaidColors.defaultTextColor),
        fontSize: nodeStyle.fontSize,
        fontWeight: nodeStyle.fontWeight,
      ),
    );
  }

  void _drawActor(
    Canvas canvas,
    MermaidNode node,
    Rect rect,
    NodeStyle nodeStyle,
  ) {
    final paint = Paint()
      ..color = Color(nodeStyle.strokeColor ?? MermaidColors.defaultNodeStroke)
      ..strokeWidth = nodeStyle.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = rect.center.dx;
    final headCenter = rect.top + 6;
    const headRadius = 4.5;
    final bodyTop = headCenter + headRadius;
    final bodyBottom = bodyTop + 8;
    final armY = bodyTop + 2;

    canvas.drawCircle(Offset(cx, headCenter), headRadius, paint);
    canvas.drawLine(Offset(cx, bodyTop), Offset(cx, bodyBottom), paint);
    canvas.drawLine(Offset(cx - 7, armY), Offset(cx + 7, armY), paint);
    canvas.drawLine(Offset(cx, bodyBottom), Offset(cx - 5, bodyBottom + 6), paint);
    canvas.drawLine(Offset(cx, bodyBottom), Offset(cx + 5, bodyBottom + 6), paint);

    drawText(
      canvas,
      node.label,
      Offset(cx, rect.bottom + nodeStyle.fontSize * .8),
      TextStyle(
        color: Color(nodeStyle.textColor ?? MermaidColors.defaultTextColor),
        fontSize: nodeStyle.fontSize,
        fontWeight: nodeStyle.fontWeight,
      ),
    );
  }

  void _drawMessage(Canvas canvas, MermaidEdge edge, double y) {
    final from = diagram.getNode(edge.from);
    final to = diagram.getNode(edge.to);
    if (from == null || to == null) return;

    final fromX = from.x + from.width / 2;
    final toX = to.x + to.width / 2;
    final paint = createEdgePaint(edge);

    if (edge.from == edge.to) {
      _drawSelfMessage(canvas, fromX, y, edge, paint);
      return;
    }

    drawLine(canvas, Offset(fromX, y), Offset(toX, y), paint, edge.lineType);
    if (edge.arrowType != ArrowType.none) {
      drawArrowHead(canvas, Offset(toX, y), toX > fromX ? 0 : math.pi, edge.arrowType, paint);
    }
    _drawEdgeLabel(canvas, edge, Offset((fromX + toX) / 2, y - 12));
  }

  void _drawSelfMessage(
    Canvas canvas,
    double x,
    double y,
    MermaidEdge edge,
    Paint paint,
  ) {
    const loopWidth = 26.0;
    const loopHeight = 16.0;
    final path = Path()
      ..moveTo(x, y)
      ..lineTo(x + loopWidth, y)
      ..lineTo(x + loopWidth, y + loopHeight)
      ..lineTo(x, y + loopHeight);

    if (edge.lineType == LineType.dotted) {
      for (final metric in path.computeMetrics()) {
        var distance = 0.0;
        while (distance < metric.length) {
          final end = math.min(distance + 5, metric.length);
          canvas.drawPath(metric.extractPath(distance, end), paint);
          distance += 10;
        }
      }
    } else {
      canvas.drawPath(path, paint);
    }

    if (edge.arrowType != ArrowType.none) {
      drawArrowHead(canvas, Offset(x, y + loopHeight), math.pi, edge.arrowType, paint);
    }
    _drawEdgeLabel(canvas, edge, Offset(x + loopWidth / 2, y + loopHeight + 12));
  }

  void _drawEdgeLabel(Canvas canvas, MermaidEdge edge, Offset position) {
    if (edge.label == null || edge.label!.isEmpty) return;
    final edgeStyle = edge.style ?? style.defaultEdgeStyle;
    drawText(
      canvas,
      edge.label!,
      position,
      TextStyle(
        color: Color(edgeStyle.labelColor ?? MermaidColors.defaultTextColor),
        fontSize: edgeStyle.labelFontSize,
      ),
      backgroundColor: Color(edgeStyle.labelBackgroundColor ?? style.backgroundColor),
    );
  }
}
