import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'campus_file_share.dart';

Future<CampusFileOpenResult> openOrShareImpl({
  required String scope,
  required String filename,
  required List<int> bytes,
  String? mimeType,
  bool preferShare = false,
}) async {
  final raw = Uint8List.fromList(bytes).toJS;
  final options = web.BlobPropertyBag(
    type: mimeType ?? 'application/octet-stream',
  );
  final blob = web.Blob([raw].toJS, options);
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = objectUrl
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 5), () {
    web.URL.revokeObjectURL(objectUrl);
  });
  return const CampusFileOpenResult.downloaded();
}

Future<void> clearScopedFilesImpl({String? scope}) async {}
