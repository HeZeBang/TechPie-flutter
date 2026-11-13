import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/genai_api_client.dart';
import 'package:techpie/features/genai/domain/genai_cancellation.dart';
import 'package:techpie/features/genai/domain/genai_document_upload.dart';
import 'package:techpie/features/genai/domain/genai_failure.dart';

import '../support/fakes.dart';

void main() {
  test(
      'upload uses section 4.4 multipart contract and converts only text filenames',
      () async {
    final transport = ScriptedTransport(
      (_) async => response(
        json: {
          'success': true,
          'code': 200,
          'result': {
            'fileId': 'document-id',
            'fileName': 'notes_md.txt',
            'content': '# 中文文档',
            'chatGroupId': 'group',
          },
        },
      ),
    );
    final api = GenAiApiClient(transport: transport);
    final content = utf8.encode('# 中文文档');
    final result = await api.uploadDocument(
      'token',
      groupId: 'group',
      aiType: 'kimi',
      fileName: 'notes.MD',
      bytes: content,
      cancellation: GenAiCancellation(),
    );
    final request = transport.requests.single;
    expect(request.uri.path, '/htk/chat/upload/chat/file');
    expect(
      request.uri.queryParameters,
      {'chatGroupId': 'group', 'aiType': 'kimi'},
    );
    expect(request.headers['X-Access-Token'], 'token');
    final body = utf8.decode(request.bodyBytes!);
    expect(body, contains('name="biz"\r\n\r\ntemp'));
    expect(body, contains('name="file"; filename="notes_md.txt"'));
    expect(body, contains('# 中文文档'));
    expect(result.fileId, 'document-id');
    expect(result.content, '# 中文文档');
    await api.uploadDocument(
      'token',
      groupId: 'group',
      aiType: 'kimi',
      fileName: 'table.XLSX',
      bytes: [80, 75, 255],
      cancellation: GenAiCancellation(),
    );
    expect(
      utf8.decode(transport.requests.last.bodyBytes!, allowMalformed: true),
      contains('filename="table.xlsx"'),
    );
  });

  test('unknown document extraction cannot masquerade as empty context',
      () async {
    for (final fields in <Map<String, Object?>>[
      {},
      {'content': null},
      {'content': 12},
      {'content': ''},
    ]) {
      final transport = ScriptedTransport(
        (_) async => response(
          json: {
            'success': true,
            'code': 200,
            'result': {'fileId': 'document-id', ...fields},
          },
        ),
      );
      final upload = GenAiApiClient(transport: transport).uploadDocument(
        'token',
        groupId: 'group',
        aiType: 'kimi',
        fileName: 'notes.txt',
        bytes: [65],
        cancellation: GenAiCancellation(),
      );
      if (fields['content'] == '') {
        expect((await upload).content, '');
      } else {
        await expectLater(
          upload,
          throwsA(
            isA<GenAiFailure>().having(
              (failure) => failure.kind,
              'kind',
              GenAiFailureKind.protocol,
            ),
          ),
        );
      }
    }
  });

  test(
      'rejects unsupported, oversized and disguised binary documents before HTTP',
      () async {
    final transport =
        ScriptedTransport((_) async => throw StateError('Must not upload'));
    final api = GenAiApiClient(transport: transport);
    final cases = <(String, List<int>)>[
      ('slides.pptx', [1]),
      ('legacy.doc', [1]),
      ('binary.py', [255, 254]),
      ('binary.json', [0, 1]),
      ('large.pdf', Uint8List(GenAiDocumentUpload.maxBytes + 1)),
      (
        'long.txt',
        utf8.encode('a' * (GenAiDocumentUpload.maxTextCharacters + 1))
      ),
      ('bad"name.txt', [65]),
    ];
    for (final (name, bytes) in cases) {
      await expectLater(
        api.uploadDocument(
          'token',
          groupId: 'group',
          aiType: 'kimi',
          fileName: name,
          bytes: bytes,
          cancellation: GenAiCancellation(),
        ),
        throwsA(isA<GenAiDocumentUploadException>()),
      );
    }
    expect(transport.requests, isEmpty);
    expect(
      GenAiDocumentUpload.prepareFileName(
        'limit.pdf',
        Uint8List(GenAiDocumentUpload.maxBytes),
      ),
      'limit.pdf',
    );
    expect(
      GenAiDocumentUpload.prepareFileName(
        'limit.txt',
        utf8.encode('a' * GenAiDocumentUpload.maxTextCharacters),
      ),
      'limit.txt',
    );
  });
}
