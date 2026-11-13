import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/genai_document_upload.dart';
import 'genai_picker.dart';

GenAiPicker createGenAiPicker() => GenAiPickerIo();

final class GenAiPickerIo implements GenAiPicker {
  GenAiPickerIo({Future<XFile?> Function(List<XTypeGroup>)? selectDocument})
      : _selectDocument = selectDocument ?? _openDocument;

  final Future<XFile?> Function(List<XTypeGroup>) _selectDocument;
  static Future<XFile?> _openDocument(List<XTypeGroup> types) =>
      openFile(acceptedTypeGroups: types);
  final _picker = ImagePicker();

  @override
  bool get supportsDocuments => true;
  @override
  bool get supportsAudio => false;

  @override
  Future<GenAiPickedFile?> pickDocument() async {
    final file = await _selectDocument(
      const [
        XTypeGroup(
          label: '文档',
          extensions: [
            ...GenAiDocumentUpload.nativeExtensions,
            ...GenAiDocumentUpload.textExtensions,
          ],
          // iOS filters by UTType; validation below remains authoritative.
          uniformTypeIdentifiers: ['public.data'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > GenAiDocumentUpload.maxBytes) {
      throw const GenAiDocumentUploadException('文档不能超过 10 MB');
    }
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > GenAiDocumentUpload.maxBytes) {
        throw const GenAiDocumentUploadException('文档不能超过 10 MB');
      }
      bytes.addAll(chunk);
    }
    GenAiDocumentUpload.prepareFileName(file.name, bytes);
    return GenAiPickedFile(name: file.name, bytes: bytes);
  }

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
