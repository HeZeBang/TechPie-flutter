import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> saveImage(Uint8List bytes, String fileName) async {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Allow the browser to start reading the blob before releasing it.
  Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return null;
}
