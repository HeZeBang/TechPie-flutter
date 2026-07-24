import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform.dart';

const _presenterChannel = MethodChannel('techpie/native_glass_presenter');
const _interactiveTransitionChannel = MethodChannel(
  'techpie/native_page_transition',
);

final List<_InteractivePopEntry> _interactivePopEntries = [];
bool _interactivePopHandlerInstalled = false;

class _InteractivePopEntry {
  const _InteractivePopEntry(this.navigator, this.route);

  final NavigatorState navigator;
  final Route<dynamic> route;
}

/// 推入包含 iOS Platform View 的页面。
///
/// Flutter 3.27 的 Cupertino 路由会分别变换每个 [UiKitView]，可能在
/// iOS 上产生黑白矩形与控件碎片。iOS 端改为对完整应用视图执行一次原生
/// 转场，Flutter 路由本身瞬时切换，从而保持 Liquid Glass 的真实绘制。
Future<T?> pushPlatformViewPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) async {
  final navigator = Navigator.of(context);

  if (!isIos()) {
    return navigator.push<T>(
      MaterialPageRoute<T>(settings: settings, builder: builder),
    );
  }

  final animationsEnabled = !MediaQuery.disableAnimationsOf(context);
  if (animationsEnabled) {
    await _beginNativeTransition('push');
  }
  if (!navigator.mounted) {
    if (animationsEnabled) await _cancelNativeTransition();
    return null;
  }

  _installInteractivePopHandler();
  final route = PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
  final entry = _InteractivePopEntry(navigator, route);
  _interactivePopEntries.add(entry);

  try {
    final result = navigator.push<T>(route);
    if (animationsEnabled) {
      unawaited(_finishNativeTransitionAfterFrame());
    }
    return await result;
  } finally {
    _interactivePopEntries.remove(entry);
  }
}

/// 返回包含 iOS Platform View 的上一页。
Future<bool> maybePopPlatformViewPage<T>(
  BuildContext context, [
  T? result,
]) async {
  final navigator = Navigator.of(context);
  if (!navigator.canPop()) return false;

  final animationsEnabled = isIos() && !MediaQuery.disableAnimationsOf(context);
  if (animationsEnabled) {
    await _beginNativeTransition('pop');
    if (!navigator.mounted) {
      await _cancelNativeTransition();
      return false;
    }
  }

  final didPop = await navigator.maybePop<T>(result);
  if (animationsEnabled) {
    if (didPop) {
      await _finishNativeTransitionAfterFrame();
    } else {
      await _cancelNativeTransition();
    }
  }
  return didPop;
}

Future<void> _beginNativeTransition(String direction) async {
  try {
    await _presenterChannel.invokeMethod<void>(
      'beginPageTransition',
      <String, Object?>{'direction': direction},
    );
  } on MissingPluginException {
    // 仍使用无 Flutter Transform 的路由，避免恢复有问题的合成路径。
  } on PlatformException {
    // 原生转场不可用时保持瞬时切换，页面功能仍可正常使用。
  }
}

Future<void> _finishNativeTransitionAfterFrame() async {
  await WidgetsBinding.instance.endOfFrame;
  try {
    await _presenterChannel.invokeMethod<void>('finishPageTransition');
  } on MissingPluginException {
    // 平台插件不可用时，零时长 Flutter 路由仍能安全完成切换。
  } on PlatformException {
    await _cancelNativeTransition();
  }
}

Future<void> _cancelNativeTransition() async {
  try {
    await _presenterChannel.invokeMethod<void>('cancelPageTransition');
  } on MissingPluginException {
    // 无待清理的原生快照。
  } on PlatformException {
    // 原生端会在下一次 begin 时清理残留快照。
  }
}

void _installInteractivePopHandler() {
  if (_interactivePopHandlerInstalled) return;
  _interactivePopHandlerInstalled = true;

  _interactiveTransitionChannel.setMethodCallHandler((call) async {
    if (call.method != 'interactivePop') {
      throw MissingPluginException('Unknown method ${call.method}');
    }

    for (final entry in _interactivePopEntries.reversed) {
      if (!entry.navigator.mounted || !entry.route.isCurrent) continue;

      final didPop = await entry.navigator.maybePop();
      if (didPop) {
        await WidgetsBinding.instance.endOfFrame;
      }
      return didPop;
    }

    return false;
  });
}
