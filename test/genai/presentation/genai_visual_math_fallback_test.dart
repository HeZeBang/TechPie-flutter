import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:techpie/features/genai/presentation/visuals/genai_visual_document.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_runtime.dart';

void main() {
  test('raw TeX fallback is styled as readable source without hiding it', () async {
    final prepared = await GenAiVisualDocument.prepare(
      r'<span data-latex="\frac{1}{2}"></span>'
      r'<div data-latex="\sum_{n=1}^{N} n" data-display="block"></div>',
      loadLibrary: (_) => Future.error(StateError('offline')),
    );
    final document = html.parse(prepared);
    final style = document.querySelector('style')!.text;

    final inlineRule = RegExp(r'\[data-math-error\]\{([^}]*)\}').firstMatch(style)!.group(1)!;
    final displayRule = RegExp(r'\[data-math-error\]\[data-math-display=block\]\{([^}]*)\}')
        .firstMatch(style)!
        .group(1)!;
    expect(inlineRule, contains('white-space:pre-wrap'));
    expect(inlineRule, contains('font-family:'));
    for (final rule in [inlineRule, displayRule]) {
      expect(rule, isNot(contains('display:none')));
      expect(rule, isNot(contains('visibility:hidden')));
      expect(rule, isNot(contains('color:transparent')));
      expect(rule, isNot(contains('text-transform')));
      expect(rule, isNot(contains('font-size:0')));
    }
    // The original markup and TeX attribute survive the optional library failure.
    expect(document.querySelector('span')!.attributes['data-latex'], r'\frac{1}{2}');
    expect(document.querySelector('div[data-display]')!.attributes['data-display'], 'block');
    expect(
      document
          .querySelectorAll('script')
          .any((script) => script.text.contains('window.techpieMath=')),
      isTrue,
    );
  });

  test('math fallback keeps exact TeX text and clears its markers on recovery', () {
    expect(genAiVisualMath, contains('element.textContent=tex;'));
    expect(genAiVisualMath, isNot(contains('element.innerHTML=tex')));
    expect(genAiVisualMath, contains("element.setAttribute('data-math-error','true')"));
    expect(genAiVisualMath, contains("element.setAttribute('data-math-display','block')"));
    expect(genAiVisualMath, contains("element.removeAttribute('data-math-error')"));
    expect(genAiVisualMath, contains("element.removeAttribute('data-math-display')"));
  });
}
