import 'genai_picker_stub.dart'
    if (dart.library.js_interop) 'genai_picker_web.dart'
    if (dart.library.io) 'genai_picker_io.dart';

final class GenAiPickedFile {
  const GenAiPickedFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final List<int> bytes;
}

abstract interface class GenAiPicker {
  factory GenAiPicker() => createGenAiPicker();

  bool get supportsDocuments;
  bool get supportsAudio;

  Future<GenAiPickedFile?> pickDocument();
  Future<GenAiPickedFile?> pickImage();
  Future<GenAiPickedFile?> pickAudio();
}
