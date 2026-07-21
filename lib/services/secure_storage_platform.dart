// On OHOS use the hard fork; everywhere else use the upstream federated plugin
// which has platform implementations for Linux, Android, macOS, iOS, Windows (+ Web).
export 'package:flutter_secure_storage/flutter_secure_storage.dart'
    if (dart.library.ohos) 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
