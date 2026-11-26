import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class MerchantContributionPreferences {
  final Set<String> _seen = {};

  String _key(String identity) =>
      'geekpay.merchantPrompt.${sha256.convert(utf8.encode(identity))}';

  Future<bool> hasSeen(String identity) async {
    if (_seen.contains(identity)) return true;
    try {
      if ((await SharedPreferences.getInstance()).getBool(_key(identity)) ==
          true) {
        _seen.add(identity);
        return true;
      }
    } catch (_) {/* A unavailable preference must not block the detail. */}
    return false;
  }

  Future<void> markSeen(String identity) async {
    _seen.add(identity);
    try {
      await (await SharedPreferences.getInstance())
          .setBool(_key(identity), true);
    } catch (_) {/* Keep the in-process dismissal. */}
  }
}
