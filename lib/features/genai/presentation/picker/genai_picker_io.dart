import 'package:image_picker/image_picker.dart';

import 'genai_picker.dart';

GenAiPicker createGenAiPicker() => GenAiPickerIo();

final class GenAiPickerIo implements GenAiPicker {
  final _picker = ImagePicker();

  @override
  bool get supportsDocuments => false;
  @override
  bool get supportsAudio => false;

  @override
  Future<GenAiPickedFile?> pickDocument() async => throw UnsupportedError(
        'Document selection is unavailable on this platform.',
      );

  @override
  Future<GenAiPickedFile?> pickImage() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return null;
      final bytes = await image.readAsBytes();
      return GenAiPickedFile(name: image.name, bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<GenAiPickedFile?> pickAudio() async => throw UnsupportedError(
        'Audio selection is unavailable on this platform.',
      );
}
