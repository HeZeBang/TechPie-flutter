import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui';

import 'package:web/web.dart' as web;

bool get canCopyImage =>
    web.window.isSecureContext &&
    web.window.navigator.has('clipboard') &&
    globalContext.has('ClipboardItem');
bool get copiesImageFile => false;

web.ShareData _shareData(Uint8List bytes) => web.ShareData(
      files: [
        web.File([bytes.toJS].toJS, 'techpie-image.png', web.FilePropertyBag(type: 'image/png')),
      ].toJS,
    );

bool canShareImage(Uint8List bytes) =>
    web.window.navigator.has('canShare') && web.window.navigator.canShare(_shareData(bytes));

Future<void> copyImage(Uint8List bytes) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  // Start in the menu gesture, and await rejection rather than reporting a
  // successful copy when browser permissions disallow it.
  await web.window.navigator.clipboard
      .write(
        [
          web.ClipboardItem({'image/png': blob}.jsify()! as JSObject),
        ].toJS,
      )
      .toDart;
}

Future<void> shareImage(Uint8List bytes, Rect origin) async {
  try {
    await web.window.navigator.share(_shareData(bytes)).toDart;
  } catch (error) {
    final exception = error as JSAny;
    if (exception.isA<web.DOMException>() && (exception as web.DOMException).name == 'AbortError') {
      return;
    }
    rethrow;
  }
}
