import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _platformChannel = MethodChannel('techpie/platform');

const double iosMinimumInteractiveDimension = 44;

bool _supportsIosLiquidGlass = false;

/// Load native platform capabilities that are needed before the first frame.
Future<void> initializePlatformCapabilities() async {
  if (!isIos()) return;

  try {
    final majorVersion = await _platformChannel.invokeMethod<int>(
      'iosMajorVersion',
    );
    _supportsIosLiquidGlass = (majorVersion ?? 0) >= 26;
  } on PlatformException {
    _supportsIosLiquidGlass = false;
  } on MissingPluginException {
    _supportsIosLiquidGlass = false;
  }
}

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
