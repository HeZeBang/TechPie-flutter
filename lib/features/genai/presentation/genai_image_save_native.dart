import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String?> saveImage(Uint8List bytes, String fileName) async {
  final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes);
  return file.path;
}
