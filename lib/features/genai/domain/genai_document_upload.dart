import 'dart:convert';

/// Upload contract from the university API reference, section 4.4.
abstract final class GenAiDocumentUpload {
  static const maxBytes = 10 * 1024 * 1024;
  static const maxTextCharacters = 500000;
  static const nativeExtensions = {'txt', 'pdf', 'docx', 'xlsx', 'xls', 'csv'};
  static const textExtensions = {
    'md',
    'markdown',
    'py',
    'json',
    'dart',
    'c',
    'cpp',
    'h',
    'java',
    'js',
    'ts',
    'jsx',
    'tsx',
    'html',
    'xml',
    'log',
    'yaml',
    'yml',
    'css',
    'sh',
    'sql',
  };

  static String get pickerAccept =>
      {...nativeExtensions, ...textExtensions}.map((ext) => '.$ext').join(',');

  /// Preserve bytes and the original display name; normalize only the wire name.
  /// Never disguise binary formats such as legacy Word or PowerPoint as text.
  static String prepareFileName(String fileName, List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const GenAiDocumentUploadException('文档不能超过 10 MB');
    }
    final name = fileName.split(RegExp(r'[/\\]')).last;
    if (name.contains(RegExp(r'[\x00-\x1f\x7f"]'))) {
      throw const GenAiDocumentUploadException('文件名包含无效字符，请重命名后上传');
    }
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final convert = textExtensions.contains(extension);
    if (!nativeExtensions.contains(extension) && !convert) {
      throw const GenAiDocumentUploadException(
        '不支持此格式，请选择 TXT、PDF、DOCX、Excel、CSV 或文本代码文件',
      );
    }
    if (convert || extension == 'txt' || extension == 'csv') {
      // Non-UTF-8 native TXT/CSV may still be understood by the server parser.
      String? text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        if (convert) {
          throw const GenAiDocumentUploadException('请将代码或文本文件保存为 UTF-8 后上传');
        }
      }
      if (convert && text!.contains('\u0000')) {
        throw const GenAiDocumentUploadException('此文件不像文本，无法转换为 TXT');
      }
      if (text != null && text.length > maxTextCharacters) {
        throw const GenAiDocumentUploadException('文档文本不能超过 500,000 字符');
      }
    }
    return convert
        ? '${name.substring(0, dot)}_$extension.txt'
        : '${name.substring(0, dot)}.$extension';
  }
}

/// Only locally authored, safe messages may be displayed to the user.
final class GenAiDocumentUploadException implements Exception {
  const GenAiDocumentUploadException(this.message);
  final String message;
}
