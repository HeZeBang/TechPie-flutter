import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import 'genai_visual_view.dart';

/// Unlike ordinary Markdown fences, an unfinished visual must never execute.
class GenAiVisualSyntax extends md.BlockSyntax {
  static Iterable<md.Element> elements(Iterable<md.Node> nodes) sync* {
    for (final node in nodes.whereType<md.Element>()) {
      if (node.tag == 'techpie-visual') yield node;
      if (node.children != null) yield* elements(node.children!);
    }
  }

  static int countComplete(String source) {
    if (!source.contains('techpie-visual')) return 0;
    // Counting fences needs block structure only; do not parse links, LaTeX or
    // other inline content a second time on every streaming update.
    final document = md.Document(blockSyntaxes: [GenAiVisualSyntax()]);
    final nodes =
        md.BlockParser(source.split('\n').map(md.Line.new).toList(), document).parseLines();
    return elements(nodes).where((node) => node.attributes['complete'] == 'true').length;
  }

  @override
  RegExp get pattern => RegExp(r'^ {0,3}(`{3,}|~{3,})techpie-visual\s*$');

  @override
  md.Node parse(md.BlockParser parser) {
    final marker = pattern.firstMatch(parser.current.content)!.group(1)!;
    final close = RegExp('^ {0,3}${marker[0]}{${marker.length},}\\s*\$');
    parser.advance();
    final lines = <String>[];
    var complete = false;
    while (!parser.isDone) {
      if (close.hasMatch(parser.current.content)) {
        complete = true;
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }
    return md.Element.text('techpie-visual', lines.join('\n'))
      ..attributes['complete'] = '$complete';
  }
}

class GenAiVisualBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => const SizedBox.shrink();

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) =>
      GenAiVisualView(
        code: element.textContent,
        index: int.parse(element.attributes['index'] ?? '1'),
        complete: element.attributes['complete'] == 'true',
      );
}
