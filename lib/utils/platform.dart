import 'dart:io';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/campus_user_agent.dart';

const double iosMinimumInteractiveDimension = 44;

bool _supportsIosLiquidGlass = false;

/// Load native platform capabilities that are needed before the first frame.
Future<void> initializePlatformCapabilities() async {
  if (!isIos()) return;

  _supportsIosLiquidGlass = (PlatformVersion.iosVersion ?? 0) >= 26;
}

Future<void> initializeCampusUserAgent() async {
  final package = await PackageInfo.fromPlatform();
  final scale = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  if (kIsWeb) {
    CampusUserAgent.value = CampusUserAgent.format(
      version: package.version,
      build: package.buildNumber,
      device: defaultTargetPlatform.name,
      system: 'web',
      systemVersion: '',
      scale: scale,
    );
  } else if (isIos()) {
    final info = (await const MethodChannel('techpie/platform')
        .invokeMapMethod<String, dynamic>('getUserAgentInfo'))!;
    CampusUserAgent.value = CampusUserAgent.format(
      version: package.version, build: package.buildNumber,
      device: info['device'] as String, system: info['system'] as String,
      systemVersion: info['systemVersion'] as String,
      scale: (info['scale'] as num).toDouble(),
    );
  } else {
    CampusUserAgent.value = CampusUserAgent.format(
      version: package.version, build: package.buildNumber,
      device: Platform.operatingSystem, system: Platform.operatingSystem,
      systemVersion: Platform.operatingSystemVersion.replaceAll(RegExp(r'[()\r\n]'), ''),
      scale: scale,
    );
  }
}

/// Tests run with no native runtime to ask; this picks the chrome they see.
@visibleForTesting
set debugUsesIosLiquidGlass(bool value) => _supportsIosLiquidGlass = value;

/// Allows widget tests running on the Dart VM to exercise direct pre-iOS 26
/// UIKit platform-view wrappers without running inside an iOS host process.
@visibleForTesting
bool debugForceDirectIosUiKitViews = false;

/// Opts Dart-VM widget tests into native `techpie/macos_native_ui` modal
/// channel calls (real macOS processes always use it).
@visibleForTesting
bool debugForceMacosNativeUiModals = false;

/// Check if the current platform is iOS and not web.
bool isIos() => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Check if the current platform is macOS and not web.
bool isMacOs() => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Check if the current platform is Apple (iOS or macOS) and not web.
bool isApplePlatform() => isIos() || isMacOs();

/// Whether macOS should render native AppKit platform views and desktop dialogs.
bool usesMacOsNativeControls() => isMacOs();

/// Whether macOS should present native `NSAlert`/`NSMenu` panels over the
/// `'techpie/macos_native_ui'` channel. Real macOS processes always use native
/// panels; headless `flutter test` defaults to Flutter fallbacks unless
/// [debugForceMacosNativeUiModals] is enabled so unmocked channel calls do not
/// stall FakeAsync.
bool usesMacOsNativeUiModals() =>
    usesMacOsNativeControls() &&
    (!Platform.environment.containsKey('FLUTTER_TEST') ||
        debugForceMacosNativeUiModals);

/// Check whether the current iOS runtime supports Apple's Liquid Glass APIs.
bool usesIosLiquidGlass() => isIos() && _supportsIosLiquidGlass;

/// Whether pre-iOS 26 devices should use UIKit controls (`UISwitch`,
/// `UISegmentedControl`, `UIMenu`, `UISlider`) directly instead of Flutter
/// fallbacks. Guarded on `Platform.isIOS` so existing Dart-VM widget tests
/// continue exercising `CNSwitch` / `CNSegmentedControl` unless opted in.
bool usesDirectIosUiKitViews() =>
    isIos() &&
    !usesIosLiquidGlass() &&
    (Platform.isIOS || debugForceDirectIosUiKitViews);

/// Older iOS versions should use conventional, non-floating navigation bars.
bool usesLegacyIosChrome() => isIos() && !_supportsIosLiquidGlass;

/// Height for the app's top chrome, matching roomier iOS 26 toolbar controls.
double adaptiveTopBarHeight() => usesIosLiquidGlass() ? 64.0 : kToolbarHeight;

/// Check if the current platform is native Linux, independently of window size.
bool isLinux() => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

/// Check if the current platform is a native desktop target.
bool isDesktop() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);

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

/// Whether this platform has a paired Apple Watch companion settings surface.
bool supportsAppleWatch() => isIos();

/// Whether this platform exposes and applies the in-app HTTP proxy setting.
/// Mobile OSes route traffic through system VPN/proxy settings instead.
bool supportsInAppProxy() => isDesktop();

/// Whether calendar export can import events directly into the device calendar.
bool supportsDirectCalendarImport() => isIos() || isAndroid();

/// Whether the timetable uses horizontal paging across weeks.
bool usesHorizontalWeekPaging() => isIos();

/// Whether selection mode replaces the bottom tab bar with a native action bar.
bool usesIosSelectionToolbar() => isIos();

/// Whether the eCard auto-bind helper temporarily occupies the iOS system VPN.
bool showsIosVpnTunnelNotice() => isIos();
