import 'genai_picker.dart';

GenAiPicker createGenAiPicker() => const _StubPicker();

final class _StubPicker implements GenAiPicker {
  const _StubPicker();

  @override
  bool get supportsDocuments => false;
  @override
  bool get supportsAudio => false;

  @override
  Future<GenAiPickedFile?> pickDocument() async => throw UnsupportedError(
        'Document selection is unavailable on this platform.',
      );

  @override
  Future<GenAiPickedFile?> pickImage() async => null;

  @override
  Future<GenAiPickedFile?> pickAudio() async => throw UnsupportedError(
        'Audio selection is unavailable on this platform.',
      );
}
