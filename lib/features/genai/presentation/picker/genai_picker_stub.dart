import 'genai_picker.dart';

GenAiPicker createGenAiPicker() => const _StubPicker();

final class _StubPicker implements GenAiPicker {
  const _StubPicker();

  @override
  Future<GenAiPickedFile?> pickDocument() async => null;

  @override
  Future<GenAiPickedFile?> pickImage() async => null;

  @override
  Future<GenAiPickedFile?> pickAudio() async => null;
}
