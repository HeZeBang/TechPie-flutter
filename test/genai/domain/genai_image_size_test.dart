import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_image_size.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';

void main() {
  const model = GenAiModel(
    name: 'Image',
    aiType: 'image',
    rootAiType: 'fixture',
    status: 2,
  );
  GenAiImageRequest request(String size) => GenAiImageRequest(
        prompt: 'test',
        model: model,
        groupId: 'group',
        size: size,
      );

  test('every offered resolution passes the image request validator', () {
    for (final sizes in GenAiImageSize.presets.values) {
      for (final size in sizes.values) {
        expect(request(size).toJson()['size'], size);
      }
    }
  });

  test('custom size bounds are inclusive and serialize without preset restriction', () {
    for (final size in [
      '1024x640',
      '800x820',
      '999x999',
      '3151x1600',
      '3840x2160',
    ]) {
      expect(request(size).toJson()['size'], size);
    }
    for (final size in [
      '1024x639',
      '3840x2161',
      '0x1024',
      '-1000x1000',
      '1024.5x1024',
      '1024X1024',
      '1024x',
      'abc',
      '9999999999999999999x1',
    ]) {
      expect(() => request(size), throwsArgumentError, reason: size);
    }
  });
}
