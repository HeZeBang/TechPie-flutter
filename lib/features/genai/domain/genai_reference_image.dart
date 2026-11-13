import 'dart:convert';
import 'dart:typed_data';

enum GenAiReferenceImageFailure implements Exception { unsupportedFormat, empty }

/// Original image bytes stay local until the generation request is serialized.
final class GenAiReferenceImage {
  GenAiReferenceImage._(this.name, this.mimeType, this.bytes);

  factory GenAiReferenceImage.fromBytes(String name, List<int> bytes) {
    if (bytes.isEmpty) throw GenAiReferenceImageFailure.empty;
    bool prefix(List<int> signature, [int start = 0]) =>
        bytes.length >= start + signature.length &&
        Iterable<int>.generate(signature.length).every((i) => bytes[start + i] == signature[i]);
    final String mime;
    if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) {
      mime = 'image/png';
    } else if (prefix([255, 216, 255])) {
      mime = 'image/jpeg';
    } else if (prefix([82, 73, 70, 70]) && prefix([87, 69, 66, 80], 8)) {
      mime = 'image/webp';
    } else {
      throw GenAiReferenceImageFailure.unsupportedFormat;
    }
    return GenAiReferenceImage._(name, mime, Uint8List.fromList(bytes).asUnmodifiableView());
  }

  final String name;
  final String mimeType;
  final Uint8List bytes;
  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}
