import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';

/// Shared configuration for the host and its integrated account stores.
const appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
