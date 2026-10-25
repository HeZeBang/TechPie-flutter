import 'dart:typed_data';

import 'genai_image_save_native.dart' if (dart.library.js_interop) 'genai_image_save_web.dart'
    as platform;

Future<String?> saveGenAiImage(Uint8List bytes, String fileName) =>
    platform.saveImage(bytes, fileName);
