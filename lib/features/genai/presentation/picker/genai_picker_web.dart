import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'genai_picker.dart';

GenAiPicker createGenAiPicker() => GenAiPickerWeb();

final class GenAiPickerWeb implements GenAiPicker {
  @override
  Future<GenAiPickedFile?> pickDocument() => _pickFile(
        '.txt,.md,.pdf,.docx,.doc,.csv,.json,.py,.dart,.c,.cpp,.h,.java,.js,.ts',
      );

  @override
  Future<GenAiPickedFile?> pickImage() => _pickFile('image/*');

  @override
  Future<GenAiPickedFile?> pickAudio() => _pickFile('audio/*,.wav,.mp3,.m4a');

  Future<GenAiPickedFile?> _pickFile(String accept) {
    final completer = Completer<GenAiPickedFile?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = accept
      ..style.display = 'none';

    web.document.body?.append(input);

    input.onchange = ((web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        input.remove();
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final file = files.item(0)!;
      final reader = web.FileReader();
      reader.onload = ((web.Event _) {
        final result = reader.result;
        input.remove();
        if (result != null && result.isA<JSArrayBuffer>()) {
          final buffer = (result as JSArrayBuffer).toDart;
          completer.complete(
            GenAiPickedFile(
              name: file.name,
              bytes: Uint8List.view(buffer),
            ),
          );
        } else {
          completer.complete(null);
        }
      }).toJS;
      reader.onerror = ((web.Event _) {
        input.remove();
        if (!completer.isCompleted) completer.complete(null);
      }).toJS;
      reader.readAsArrayBuffer(file);
    }).toJS;

    input.click();
    return completer.future;
  }
}
