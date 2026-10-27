import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_document_upload.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_player.dart';
import 'package:techpie/features/genai/presentation/audio/genai_audio_recorder.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker.dart';
import 'package:techpie/features/genai/presentation/picker/genai_picker_io.dart';

void main() {
  test('native audio reports unavailable and refuses simulated success', () async {
    final player = GenAiAudioPlayer();
    final recorder = GenAiAudioRecorder();
    expect(player.isSupported, isFalse);
    expect(recorder.isSupported, isFalse);
    expect(await recorder.hasPermission(), isFalse);
    await expectLater(player.playWav([0, 1]), throwsUnsupportedError);
    await expectLater(recorder.start(), throwsUnsupportedError);
    expect(player.isPlaying, isFalse);
    expect(recorder.isRecording, isFalse);
    player.dispose();
    recorder.dispose();
  });

  test('native file capabilities distinguish unsupported actions from cancellation', () async {
    final picker = GenAiPicker();
    expect(picker.supportsDocuments, isTrue);
    expect(picker.supportsAudio, isFalse);
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
    await expectLater(picker.pickAudio(), throwsUnsupportedError);
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
