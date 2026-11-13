import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Only the prepared, sandboxed shell is opened, never raw model HTML.
Future<void> openGenAiVisual(String shell) async {
  final root = await getTemporaryDirectory();
  final directory = await Directory('${root.path}/techpie-visuals').create(recursive: true);
  final file = File('${directory.path}/visual-${DateTime.now().microsecondsSinceEpoch}.html');
  await file.writeAsString(shell, flush: true);
  if (!await launchUrl(file.uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Browser unavailable');
  }
}
