import 'dart:convert';
import 'dart:typed_data';

final class GenAiMultipartData {
  const GenAiMultipartData({
    required this.contentType,
    required this.bytes,
  });

  final String contentType;
  final List<int> bytes;

  static GenAiMultipartData create({
    Map<String, String> fields = const {},
    required String fileFieldName,
    required String fileName,
    required List<int> fileBytes,
    String fileContentType = 'application/octet-stream',
  }) {
    final boundary =
        '----TechPieBoundary${DateTime.now().microsecondsSinceEpoch}';
    final builder = BytesBuilder();
    for (final entry in fields.entries) {
      builder.add(utf8.encode('--$boundary\r\n'));
      builder.add(
        utf8.encode(
          'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n',
        ),
      );
      builder.add(utf8.encode('${entry.value}\r\n'));
    }
    builder.add(utf8.encode('--$boundary\r\n'));
    builder.add(
      utf8.encode(
        'Content-Disposition: form-data; name="$fileFieldName"; filename="$fileName"\r\n',
      ),
    );
    builder.add(utf8.encode('Content-Type: $fileContentType\r\n\r\n'));
    builder.add(fileBytes);
    builder.add(utf8.encode('\r\n--$boundary--\r\n'));
    return GenAiMultipartData(
      contentType: 'multipart/form-data; boundary=$boundary',
      bytes: builder.toBytes(),
    );
  }
}
