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

Directory? _clipboardDirectory;
Future<void> _clipboardWrite = Future<void>.value();

Future<void> copyImage(Uint8List bytes) async {
  if (!canCopyImage) throw UnsupportedError('Image clipboard unavailable');
  if (!Platform.isLinux) {
    await Pasteboard.writeImage(bytes);
    return;
  }
  final write = _clipboardWrite.then((_) => _copyLinuxImage(bytes));
  _clipboardWrite = write.catchError((Object _) {});
  await write;
}

Future<void> _copyLinuxImage(Uint8List bytes) async {
  // createTemp uses a private, unpredictable directory on POSIX. Never follow
  // a path another local user could have created in the shared temporary root.
  final directory = await Directory.systemTemp.createTemp('techpie-clipboard-');
  var retained = false;
  try {
    final file = File('${directory.path}/image.png');
    await file.writeAsBytes(bytes, flush: true);
    if (!await Pasteboard.writeFiles([file.path])) {
      throw StateError('Clipboard rejected image file');
    }
    final previous = _clipboardDirectory;
    _clipboardDirectory = directory;
    retained = true;
    if (previous != null) {
      try {
        await previous.delete(recursive: true);
      } on FileSystemException {
        // Cleanup failure does not invalidate an accepted clipboard update.
      }
    }
  } finally {
    if (!retained) await directory.delete(recursive: true);
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
