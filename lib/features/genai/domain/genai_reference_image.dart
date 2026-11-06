import 'dart:convert';
import 'dart:typed_data';

enum GenAiReferenceImageFailure implements Exception {
  unsupportedFormat,
  empty,
  tooLarge,
  tooMany,
  totalTooLarge,
}

/// Original image bytes stay local until the generation request is serialized.
final class GenAiReferenceImage {
  GenAiReferenceImage._(this.name, this.mimeType, this.bytes);

  factory GenAiReferenceImage.fromBytes(String name, List<int> bytes) {
    if (bytes.isEmpty) throw GenAiReferenceImageFailure.empty;
    if (bytes.length > maxFileBytes) throw GenAiReferenceImageFailure.tooLarge;
    bool prefix(List<int> signature, [int start = 0]) =>
        bytes.length >= start + signature.length &&
        Iterable<int>.generate(signature.length)
            .every((i) => bytes[start + i] == signature[i]);
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
    return GenAiReferenceImage._(
      name,
      mime,
      Uint8List.fromList(bytes).asUnmodifiableView(),
    );
  }

  static const maxCount = 4;
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxTotalBytes = 25 * 1024 * 1024;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';

  static void validate(List<GenAiReferenceImage> images) {
    if (images.length > maxCount) throw GenAiReferenceImageFailure.tooMany;
    if (images.fold<int>(0, (sum, image) => sum + image.bytes.length) >
        maxTotalBytes) {
      throw GenAiReferenceImageFailure.totalTooLarge;
    }
  }
}
