import 'dart:async';

import 'package:flutter/services.dart';

import '../features/campus_card/domain/ports/platform_ports.dart';

typedef OpenEcardPayHandler = Future<void> Function();

/// Hosts widget installation and routes cold or warm widget taps to payment.
final class EcardWidgetService implements HomeWidgetPort {
  EcardWidgetService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('techpie/ecard_deep_link');

  final MethodChannel _channel;
  final List<OpenEcardPayHandler> _paymentTargets = [];
  OpenEcardPayHandler? _handler;
  bool _initialized = false;
  bool _pending = false;
  bool _dispatching = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    unawaited(_consumePending());
  }

  void setOpenPayHandler(OpenEcardPayHandler handler) {
    _handler = handler;
    if (_pending) unawaited(_dispatch());
  }

  void clearOpenPayHandler() {
    _handler = null;
  }

  void Function() registerPaymentTarget(OpenEcardPayHandler handler) {
    _paymentTargets.add(handler);
    return () => _paymentTargets.remove(handler);
  }

  @override
  Future<HomeWidgetAvailability> availability() async {
    try {
      return switch (
          await _channel.invokeMethod<String>('widgetAvailability')) {
        'nativePin' => HomeWidgetAvailability.nativePin,
        'unsupported' => HomeWidgetAvailability.unsupported,
        _ => HomeWidgetAvailability.manual,
      };
    } on MissingPluginException {
      return HomeWidgetAvailability.manual;
    } on PlatformException {
      return HomeWidgetAvailability.manual;
    }
  }

  @override
  Future<bool> requestPin() async =>
      await _channel.invokeMethod<bool>('requestPinWidget') ?? false;

  Future<void> dispose() async {
    _handler = null;
    _paymentTargets.clear();
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method == 'openPayCode') {
      await _dispatch();
    }
    return null;
  }

  Future<void> _consumePending() async {
    try {
      final route = await _channel.invokeMethod<String>('consumePendingRoute');
      if (route == 'pay') await _dispatch();
    } on MissingPluginException {
      // Unsupported hosts do not install this channel.
    } on PlatformException {
      // A native shortcut failure must never delay normal app startup.
    }
  }

  Future<void> _dispatch() async {
    if (_dispatching) {
      _pending = true;
      return;
    }
    final handler = _paymentTargets.isEmpty ? _handler : _paymentTargets.last;
    if (handler == null) {
      _pending = true;
      return;
    }
    _pending = false;
    _dispatching = true;
    try {
      await handler();
      try {
        await _channel.invokeMethod<void>('acknowledgePendingRoute');
      } on MissingPluginException {
        // Tests and unsupported hosts can dispatch without a native peer.
      } on PlatformException {
        // The route is already open. A failed acknowledgement is harmless.
      }
    } finally {
      _dispatching = false;
      if (_pending) unawaited(_dispatch());
    }
  }
}
