import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wear_protocol.dart';

class AndroidWearTransport implements WearTransport {
  AndroidWearTransport({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('techpie/wear_engine') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'frame' && call.arguments is Uint8List) {
        _frames.add(call.arguments as Uint8List);
      } else if (call.method == 'state' && call.arguments is Map) {
        _states.add(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }
  final MethodChannel _channel;
  final _frames = StreamController<Uint8List>.broadcast();
  final _states = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Uint8List> get frames => _frames.stream;
  @override
  Stream<Map<String, dynamic>> get states => _states.stream;
  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const WearFailure('SERVICE_UNAVAILABLE');
    } on PlatformException catch (error) {
      throw WearFailure(
        error.code,
        nativeCode: error.details is int ? error.details as int : null,
        retryable: const {
          'SERVICE_UNAVAILABLE',
          'DEVICE_DISCONNECTED',
          'TRANSPORT_FAILED',
        }.contains(error.code),
      );
    }
  }

  @override
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
        await _call<Map<Object?, Object?>>('status') ?? {},
      );
  @override
  Future<List<Map<String, dynamic>>> devices() async =>
      (await _call<List<Object?>>('devices') ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> authorize({required bool notify}) async =>
      Map<String, dynamic>.from(
        await _call<Map<Object?, Object?>>('authorize', {'notify': notify}) ??
            {},
      );
  @override
  Future<void> open(String deviceId, String fingerprint) async =>
      _call<void>('open', {'deviceId': deviceId, 'fingerprint': fingerprint});
  @override
  Future<void> send(Uint8List bytes) async =>
      _call<void>('send', {'bytes': bytes});
  @override
  Future<void> close() async => _call<void>('close');
  @override
  Future<void> scheduleReminders(Map<String, dynamic> spec) async =>
      _call<void>('scheduleReminders', {'json': jsonEncode(spec)});
  @override
  Future<void> cancelReminders() async => _call<void>('cancelReminders');
  @override
  Future<String> sendReminder(String id) async =>
      await _call<String>('sendReminder', {
        'json': jsonEncode({'reminderId': id}),
      }) ??
      'deliveryUnknown';
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_frames.close());
    unawaited(_states.close());
  }
}

class PreferencesWearMetadata implements WearMetadata {
  PreferencesWearMetadata(this.preferences);
  final SharedPreferences preferences;
  static const key = 'techpie.wear.metadata.v1';
  @override
  String? read() => preferences.getString(key);
  @override
  Future<void> write(String value) async {
    if (!await preferences.setString(key, value)) {
      throw const WearFailure('STORAGE_FAILED');
    }
  }
}
