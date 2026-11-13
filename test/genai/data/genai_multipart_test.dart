import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/genai_multipart.dart';

void main() {
  test('multipart escapes header parameters without altering payload bytes', () {
    final data = GenAiMultipartData.create(
      fields: {'field"\r\nInjected: value': 'ordinary\r\nvalue'},
      fileFieldName: 'file"\r\nInjected: value',
      fileName: 'folder/screenshot "1"\r\n.png',
      fileBytes: [0, 255, 13, 10],
      fileContentType: 'image/png',
    );
    final wire = latin1.decode(data.bytes);
    expect(wire, contains('filename="screenshot %221%22%0D%0A.png"'));
    expect(wire, isNot(contains('\r\nInjected:')));
    expect(wire, contains('ordinary\r\nvalue'));
    expect(wire, contains(latin1.decode([0, 255, 13, 10])));
    expect(
      () => GenAiMultipartData.create(
        fileFieldName: 'file',
        fileName: 'image.png',
        fileBytes: [],
        fileContentType: 'image/png\r\nInjected: value',
      ),
      throwsArgumentError,
    );
  });
}
