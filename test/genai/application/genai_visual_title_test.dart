import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:techpie/features/genai/application/genai_conversation_turn.dart';
import 'package:techpie/features/genai/application/genai_remote_history.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_remote_record.dart';
import 'package:techpie/features/genai/domain/genai_visual.dart';
import 'package:techpie/features/genai/presentation/visuals/genai_visual_syntax.dart';

const _titledAnswer = '示例说明。\n\n'
    '```techpie-visual {"title":"曲线与切线"}\n'
    '<!doctype html><html><body><title>HTML label must not win</title><p>demo</p></body></html>\n'
    '```\n\n'
    '继续。';

const _bareAnswer = '# 旧示例\n\n'
    '```techpie-visual\n'
    '<!doctype html><html><body><p>legacy</p></body></html>\n'
    '```\n';

md.Element _parseVisual(String markdown) {
  final document = md.Document(blockSyntaxes: [GenAiVisualSyntax()]);
  return GenAiVisualSyntax.elements(document.parseLines(markdown.split('\n'))).single;
}

GenAiSavedTurn _saved(String answer) {
  final turn = GenAiConversationTurn('演示', id: 'turn-1');
  return GenAiSavedTurn(
    prompt: encodeGenAiRemoteRecord({
      'kind': 'exchange',
      'step_id': 'step-1',
      'turn': turn.toRemoteInput(),
      'input': turn.prompt,
    }),
    answer: answer,
  );
}

void main() {
  group('fence metadata', () {
    test('reads an explicit title and raw source', () {
      final visual = GenAiVisual.parse('<p>demo</p>', info: '{"title":"曲线与切线"}');
      expect(visual.title, '曲线与切线');
      expect(visual.source, '<p>demo</p>');
    });

    test('keeps bare fences valid and ignores malformed or empty titles', () {
      expect(GenAiVisual.parse('<p/>').title, isNull);
      expect(GenAiVisual.parse('<p/>', info: '').title, isNull);
      expect(GenAiVisual.parse('<p/>', info: 'not json').title, isNull);
      expect(GenAiVisual.parse('<p/>', info: '{"title":1}').title, isNull);
      expect(GenAiVisual.parse('<p/>', info: '{"title":"   "}').title, isNull);
      expect(GenAiVisual.parse('<p/>', info: '{"title":["x"]}').title, isNull);
      expect(
        GenAiVisual.parse('<p/>', info: '{"title":"  曲线\\n 与 切线 "}').title,
        '曲线 与 切线',
      );
    });

    test('bounds an oversized title without dropping the source', () {
      final title = List.filled(100, '曲').join();
      final visual = GenAiVisual.parse('<p/>', info: '{"title":"$title"}');
      expect(visual.source, '<p/>');
      expect(visual.title!.runes.length, GenAiVisual.maxTitleRunes + 1);
      expect(visual.title, endsWith('…'));
    });
  });

  group('block syntax', () {
    test('carries the explicit title attribute to the builder input', () {
      final titled = _parseVisual(_titledAnswer);
      expect(titled.attributes['title'], '曲线与切线');
      expect(titled.attributes['complete'], 'true');
      // The HTML document's own <title> is literal source, never the card title.
      expect(titled.textContent, contains('<title>HTML label must not win</title>'));
    });

    test('an old bare fence has no title attribute and still parses', () {
      final bare = _parseVisual(_bareAnswer);
      expect(bare.attributes.containsKey('title'), isFalse);
      expect(bare.attributes['complete'], 'true');
      expect(bare.textContent, contains('<p>legacy</p>'));
    });

    test('tilde fences accept metadata with or without separating whitespace', () {
      for (final header in [
        '~~~techpie-visual {"title":"无空格"}',
        '~~~techpie-visual{"title":"无空格"}',
      ]) {
        final element = _parseVisual('$header\n<p>x</p>\n~~~');
        expect(element.attributes['title'], '无空格');
        expect(element.textContent, '<p>x</p>');
      }
    });

    test('malformed metadata still yields a renderable visual', () {
      final element = _parseVisual('```techpie-visual {"title":\n<p>x</p>\n```');
      expect(element.attributes.containsKey('title'), isFalse);
      expect(element.attributes['complete'], 'true');
      expect(element.textContent, '<p>x</p>');
    });

    test('completion counting recognizes titled and untitled fences while streaming', () {
      expect(
        GenAiVisualSyntax.countComplete('```techpie-visual {"title":"曲线"}\n<p/>\n```'),
        1,
      );
      expect(GenAiVisualSyntax.countComplete('```techpie-visual {"title":"曲线"}\n<p/>'), 0);
      expect(GenAiVisualSyntax.countComplete('```techpie-visual\n<p/>\n```'), 1);
    });

    test('a longer language token is never treated as a visual', () {
      final document = md.Document(blockSyntaxes: [GenAiVisualSyntax()]);
      final nodes = document.parseLines(['```techpie-visual-extra', '<p/>', '```']);
      expect(GenAiVisualSyntax.elements(nodes), isEmpty);
    });
  });

  group('local persistence and sync', () {
    test('the sync record carries the title only inside the raw answer text', () {
      final saved = _saved(_titledAnswer);
      expect(saved.answer, _titledAnswer);
      expect(saved.prompt, startsWith('<techpie-record version="2">'));
      expect(saved.prompt, isNot(contains('曲线与切线')));
      final record = decodeGenAiRemoteRecord(saved.prompt)!;
      expect(record['step_id'], 'step-1');

      // The server row parser must keep the fence byte-for-byte, not
      // normalize or strip the optional metadata.
      final loaded = GenAiSavedTurn.fromJson({
        'question': saved.prompt,
        'answer': _titledAnswer,
      });
      expect(loaded.answer, _titledAnswer);

      final restored = decodeGenAiConversation('group', [saved]).archive.turns.single;
      expect(restored.answer, _titledAnswer);
      expect(_parseVisual(restored.answer).attributes['title'], '曲线与切线');
    });

    test('an old untitled sync record restores its bare fence unchanged', () {
      final saved = _saved(_bareAnswer);
      final restored = decodeGenAiConversation('old-group', [saved]).archive.turns.single;
      expect(restored.answer, _bareAnswer);
      expect(_parseVisual(restored.answer).attributes.containsKey('title'), isFalse);
      expect(decodeGenAiRemoteRecord(saved.prompt)!.keys, isNot(contains('visualTitle')));
    });
  });
}
