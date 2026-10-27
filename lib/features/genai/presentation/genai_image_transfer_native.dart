import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';

bool get canCopyImage =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isWindows ||
    Platform.isLinux;
bool get copiesImageFile => Platform.isLinux;
bool canShareImage(Uint8List bytes) =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;

Future<void> copyImage(Uint8List bytes) async {
  if (!canCopyImage) throw UnsupportedError('Image clipboard unavailable');
  if (Platform.isLinux) {
    // Linux pasteboard supports file URIs, not bitmap writes. Keep the latest
    // clipboard file alive until the next copy so the receiver can read it.
    final root = Directory.systemTemp;
    final directory = Directory('${root.path}/genai-clipboard');
    await directory.create(recursive: true);
    final file = File('${directory.path}/image.png');
    await file.writeAsBytes(bytes, flush: true);
    if (!await Pasteboard.writeFiles([file.path])) {
      throw StateError('Clipboard rejected image file');
    }
  } else {
    await Pasteboard.writeImage(bytes);
  }
}

Future<void> shareImage(Uint8List bytes, Rect origin) async {
  if (!canShareImage(bytes)) throw UnsupportedError('Image sharing unavailable');
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: 'image/png')],
    fileNameOverrides: ['techpie-image.png'],
    sharePositionOrigin: origin,
  );
}
