import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_document_upload.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker_io.dart';

void main() {
  test('native document picker handles cancellation and rejects invalid files before reading',
      () async {
    final cancelled = GenAiPickerIo(selectDocument: (_) async => null);
    expect(await cancelled.pickDocument(), isNull);
    final document = GenAiPickerIo(
      selectDocument: (types) async {
        expect(types.single.uniformTypeIdentifiers, contains('public.data'));
        expect(types.single.extensions, contains('pdf'));
        return XFile.fromData(Uint8List.fromList([65, 66]), path: 'notes.txt');
      },
    );
    final picked = await document.pickDocument();
    expect(picked!.name, 'notes.txt');
    expect(picked.bytes, [65, 66]);
    final invalid = GenAiPickerIo(
      selectDocument: (_) async => XFile.fromData(Uint8List.fromList([0]), path: 'program.exe'),
    );
    await expectLater(invalid.pickDocument(), throwsA(isA<GenAiDocumentUploadException>()));
    final oversized = GenAiPickerIo(selectDocument: (_) async => _OversizedDocument());
    await expectLater(oversized.pickDocument(), throwsA(isA<GenAiDocumentUploadException>()));
  });

  test('macOS sandbox entitlements grant Downloads read-write for image saving', () {
    for (final path in const [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final contents = File(path).readAsStringSync();
      expect(
        contents,
        matches(
          RegExp(
            r'<key>com\.apple\.security\.files\.downloads\.read-write</key>\s*<true/>',
          ),
        ),
        reason: '$path must enable the Downloads read-write entitlement',
      );
      expect(
        contents,
        matches(RegExp(r'<key>com\.apple\.security\.app-sandbox</key>\s*<true/>')),
        reason: '$path must keep the App Sandbox enabled',
      );
      for (final broad in const [
        'com.apple.security.files.all',
        'com.apple.security.files.home-relative-path.read-write',
      ]) {
        expect(
          contents,
          isNot(contains(broad)),
          reason: '$path must not grant the broad write entitlement $broad',
        );
      }
    }
  });
}

class _OversizedDocument extends XFile {
  _OversizedDocument() : super('large.pdf');
  @override
  Future<int> length() async => GenAiDocumentUpload.maxBytes + 1;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      throw StateError('Oversized file must be rejected before reading');
}
