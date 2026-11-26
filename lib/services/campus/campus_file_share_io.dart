import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'campus_file_share.dart';

const MethodChannel _platformChannel = MethodChannel('techpie/platform');

@visibleForTesting
Future<Directory> Function()? debugTempDirectoryOverride;

Future<Directory> _baseRoot() async {
  final dir = await (debugTempDirectoryOverride ?? getTemporaryDirectory)();
  return Directory('${dir.path}${Platform.pathSeparator}campus_files');
}

Future<CampusFileOpenResult> openOrShareImpl({
  required String scope,
  required String filename,
  required List<int> bytes,
  String? mimeType,
  bool preferShare = false,
}) async {
  final root = await _baseRoot();
  final scopeDir = Directory('${root.path}${Platform.pathSeparator}$scope');
  await scopeDir.create(recursive: true);
  final file = File('${scopeDir.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);

  final mobile =
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
  if (preferShare && mobile) {
    await _platformChannel.invokeMethod<void>('shareFile', {
      'scope': scope,
      'filename': filename,
      if (mimeType != null) 'mimeType': mimeType,
    });
    return CampusFileOpenResult(status: CampusFileOpenStatus.shared, path: file.path);
  }

  try {
    final openResult = await OpenFilex.open(file.path, type: mimeType);
    if (openResult.type == ResultType.done) {
      return CampusFileOpenResult(status: CampusFileOpenStatus.opened, path: file.path);
    }
  } catch (_) {}

  try {
    final launched = await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
    if (launched) {
      return CampusFileOpenResult(status: CampusFileOpenStatus.opened, path: file.path);
    }
  } catch (_) {}

  return CampusFileOpenResult(status: CampusFileOpenStatus.savedOnly, path: file.path);
}

Future<void> clearScopedFilesImpl({String? scope}) async {
  try {
    final root = await _baseRoot();
    final target = scope == null
        ? root
        : Directory('${root.path}${Platform.pathSeparator}$scope');
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
  } catch (_) {}
}
