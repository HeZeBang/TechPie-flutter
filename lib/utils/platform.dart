import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const double iosMinimumInteractiveDimension = 44;

bool _supportsIosLiquidGlass = false;

/// Load native platform capabilities that are needed before the first frame.
Future<void> initializePlatformCapabilities() async {
  if (!isIos()) return;

  _supportsIosLiquidGlass = (PlatformVersion.iosVersion ?? 0) >= 26;
}

/// Tests run with no native runtime to ask; this picks the chrome they see.
@visibleForTesting
set debugUsesIosLiquidGlass(bool value) => _supportsIosLiquidGlass = value;

/// Check if the current platform is iOS and not web.
bool isIos() => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Check whether the current iOS runtime supports Apple's Liquid Glass APIs.
bool usesIosLiquidGlass() => isIos() && _supportsIosLiquidGlass;

/// Older iOS versions should use conventional, non-floating navigation bars.
bool usesLegacyIosChrome() => isIos() && !_supportsIosLiquidGlass;

/// Height for the app's top chrome, matching roomier iOS 26 toolbar controls.
double adaptiveTopBarHeight() => usesIosLiquidGlass() ? 64.0 : kToolbarHeight;

/// Check if the current platform is Android and not web.
bool isAndroid() => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Check if the current platform is HarmonyOS NEXT (OHOS) and not web.
///
/// The OHOS Flutter fork adds `TargetPlatform.ohos`; matching on the name keeps
/// this file compiling against upstream Flutter, which has no such constant.
bool isOhos() => !kIsWeb && defaultTargetPlatform.name == 'ohos';

/// Whether `dynamic_color` ships an implementation here — it covers Android,
/// Linux, macOS and Windows only.
///
/// Its builder swallows `PlatformException`, but a platform without the plugin
/// throws `MissingPluginException`, which would surface as an unhandled async
/// error at startup (iOS, web, OHOS). Skipping the builder leaves the app on its
/// static colour scheme instead.
bool supportsSystemDynamicColor() =>
    !kIsWeb &&
    (isAndroid() ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);
