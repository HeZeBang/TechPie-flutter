import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_contract.dart';
import 'package:techpie/features/genai/domain/genai_platform_contract.dart';
import 'package:techpie/features/genai/domain/genai_reference_image.dart';

import '../support/fakes.dart';

void main() {
  const model = GenAiModel(
    name: 'Image',
    aiType: 'image',
    rootAiType: 'fixture',
    status: 2,
  );
  GenAiReferenceImage image([int size = 8]) {
    final bytes = Uint8List(size)
      ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
    return GenAiReferenceImage.fromBytes('test.png', bytes);
  }

  GenAiImageRequest request(List<GenAiReferenceImage> refs) =>
      GenAiImageRequest(
        prompt: 'test',
        model: model,
        groupId: 'group',
        referenceImages: refs,
      );

  test(
      'zero, single and multiple references use the mutually exclusive API fields',
      () async {
    final first = image();
    final second =
        GenAiReferenceImage.fromBytes('renamed.png', [255, 216, 255, 224]);
    final transport = ScriptedTransport(
      (r) async => response(
        json: {
          'data': [
            {'url': 'test/result.png'},
          ],
        },
      ),
    );
    final api = GenAiApiClient(transport: transport);
    for (final refs in [
      <GenAiReferenceImage>[],
      [first],
      [first, second],
    ]) {
      await api.generateImage('token', request(refs), GenAiCancellation());
      final sent = transport.requests.last;
      expect(sent.uri.path, '/htk/chat/start/chat');
      final json = jsonDecode(sent.body!) as Map<String, dynamic>;
      expect(json['imageBase64'], refs.length == 1 ? first.dataUrl : null);
      expect(
        json['imageBase64List'],
        refs.length > 1 ? [first.dataUrl, second.dataUrl] : null,
      );
    }
    expect(transport.requests, hasLength(3));
    expect(first.dataUrl, 'data:image/png;base64,${base64Encode(first.bytes)}');
    expect(second.dataUrl, startsWith('data:image/jpeg;base64,'));
  });

  test('reference count and raw byte budgets include their exact boundaries',
      () {
    final small = image();
    expect(request([small, small, small, small]).referenceImages, hasLength(4));
    expect(
      () => request(List.filled(5, small)),
      throwsA(GenAiReferenceImageFailure.tooMany),
    );
    final ten = image(GenAiReferenceImage.maxFileBytes);
    final five = image(5 * 1024 * 1024);
    expect(request([ten, ten, five]).referenceImages, hasLength(3));
    expect(
      () => request([ten, ten, five, small]),
      throwsA(GenAiReferenceImageFailure.totalTooLarge),
    );
    expect(
      () => image(GenAiReferenceImage.maxFileBytes + 1),
      throwsA(GenAiReferenceImageFailure.tooLarge),
    );
    expect(
      () => GenAiReferenceImage.fromBytes('empty.png', []),
      throwsA(GenAiReferenceImageFailure.empty),
    );
    expect(
      () => GenAiReferenceImage.fromBytes('fake.png', utf8.encode('<svg/>')),
      throwsA(GenAiReferenceImageFailure.unsupportedFormat),
    );
  });

  test(
      'request references and bytes are snapshots independent of picker mutation',
      () {
    final bytes = Uint8List.fromList([255, 216, 255, 224]);
    final ref = GenAiReferenceImage.fromBytes('test.jpg', bytes);
    final refs = [ref];
    final value = request(refs);
    bytes[0] = 0;
    refs.clear();
    expect(value.referenceImages.single.bytes[0], 255);
    expect(() => value.referenceImages.clear(), throwsUnsupportedError);
    expect(() => ref.bytes[0] = 0, throwsUnsupportedError);
  });
}
