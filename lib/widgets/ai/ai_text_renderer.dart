import 'package:flutter/widgets.dart';
import 'package:flutter_ai_elements/flutter_ai_elements.dart';

import 'ai_code_highlighter.dart';

/// A [TextRenderer] that renders Markdown via [AiResponse] **even while
/// streaming**, so markdown and code blocks form up live as tokens arrive.
///
/// This is the demo's "render Markdown during streaming too" opt-out from the
/// flutter_ai `ChatScreen` — the library's default [MarkdownTextRenderer]
/// switches to [AiAnimatedResponse] (plain-prose blur fade) while streaming,
/// which doesn't render Markdown. We prefer live Markdown here.
///
/// [AiResponse] caches its parse and only re-parses when the text actually
/// changes, and the controller coalesces notifications, so re-rendering per
/// streamed token stays smooth.
class StreamingMarkdownRenderer implements AiTextRenderer {
  const StreamingMarkdownRenderer({this.onLinkTap});

  /// Called when a link is tapped. If `null`, links render but aren't tappable.
  final void Function(Uri url)? onLinkTap;

  @override
  Widget render(String text, {required bool isStreaming}) => AiResponse(
        text: text,
        onLinkTap: onLinkTap,
        codeHighlighter: techpieCodeHighlighter,
      );
}
