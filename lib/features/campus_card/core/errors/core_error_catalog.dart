import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class CoreErrorCatalog {
  static const _chineseAsset =
      'assets/campus_card/data/core_error_codes_zh.json';
  static const _englishAsset =
      'assets/campus_card/data/core_error_codes_en.json';

  static const _fallbackChinese = <String, String>{
    'CORE10003': '请求失败',
    'CORE10004': '操作失败',
    'CORE10005': '操作异常',
    'CORE10008': '成功',
    'CORE20003': '密码错误',
  };
  static const _fallbackEnglish = <String, String>{
    'CORE10003': 'Request Failure',
    'CORE10004': 'Operation Failure',
    'CORE10005': 'Operation Exception',
    'CORE10008': 'Success',
    'CORE20003': 'Password Error',
  };

  static Map<String, String> _chinese = _fallbackChinese;
  static Map<String, String> _english = _fallbackEnglish;
  static Future<void>? _initializing;

  static Future<void> initialize({AssetBundle? bundle}) =>
      _initializing ??= _load(bundle ?? rootBundle);

  static Future<void> _load(AssetBundle bundle) async {
    try {
      final values = await Future.wait([
        _loadAsset(bundle, _chineseAsset),
        _loadAsset(bundle, _englishAsset),
      ]);
      _chinese = _decode(values[0]);
      _english = _decode(values[1]);
    } catch (_) {
      _chinese = _fallbackChinese;
      _english = _fallbackEnglish;
    }
  }

  static Future<String> _loadAsset(AssetBundle bundle, String asset) =>
      bundle.loadString(asset);

  static Map<String, String> _decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Core error catalog must be a JSON object');
    }
    return Map.unmodifiable(
      decoded.map((key, value) => MapEntry(key.toString(), value.toString())),
    );
  }

  /// The feature's copy is Chinese, so the catalog resolves to Chinese by
  /// default. [languageCode] stays for callers that already know the language
  /// (the tests pin both tables), and English is kept as a fallback for codes
  /// the Chinese table does not carry.
  static String? message(String? code, {String? languageCode}) {
    final normalized = code?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final preferred = languageCode == 'en' ? _english : _chinese;
    return preferred[normalized] ??
        _chinese[normalized] ??
        _english[normalized];
  }

  static String resolve(String value, {String? languageCode}) =>
      message(value, languageCode: languageCode) ?? value;

  static bool isCoreCode(Object? value) =>
      value is String && RegExp(r'^CORE\d+$').hasMatch(value.trim());

  @visibleForTesting
  static void installForTest({
    required Map<String, String> chinese,
    required Map<String, String> english,
  }) {
    _chinese = Map.unmodifiable(chinese);
    _english = Map.unmodifiable(english);
    _initializing = Future<void>.value();
  }
}
