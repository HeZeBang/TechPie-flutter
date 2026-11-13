import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_image_caption.dart';

void main() {
  test('prefers a non-empty explicit title', () {
    expect(genAiImageCaption('A long prompt that should not win', title: '  Sunrise  '), 'Sunrise');
  });

  test('derives the first punctuation-delimited clause', () {
    expect(genAiImageCaption('A red square, blue circle'), 'A red square');
    expect(genAiImageCaption('夏日池塘里的荷花，晨雾与倒影'), '夏日池塘里的荷花');
    expect(genAiImageCaption('第一行\n第二行'), '第一行');
  });

  test('caps mixed-script captions by display width', () {
    expect(genAiImageCaption('abc一二三四五六七八九十十一'), 'abc一二三四五六七八九十');
  });

  test('is empty-safe for blank prompts and titles', () {
    expect(genAiImageCaption(''), '');
    expect(genAiImageCaption('   \n '), '');
    expect(genAiImageCaption('hello', title: '   '), 'hello');
    expect(genAiImageCaption('', title: ''), '');
  });
}
