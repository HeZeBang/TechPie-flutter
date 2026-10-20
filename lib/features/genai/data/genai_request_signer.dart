import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Public frontend anti-tamper protocol. Deployment supplies the platform salt;
/// account credentials and API keys never belong in this configuration.
final class GenAiRequestSigner {
  const GenAiRequestSigner(this.salt);
  final String salt;

  /// The official helper mutates top-level numeric body fields before Axios
  /// serializes them. Sign and transmit the same normalized representation.
  Map<String, Object?> prepareBody(Map<String, Object?> data) => {
        for (final entry in data.entries)
          entry.key: entry.value is num ? entry.value.toString() : entry.value,
      };

  Map<String, String> headers(
    Uri uri,
    Map<String, Object?> data,
    DateTime time,
  ) {
    final merged = <String, Object?>{...uri.queryParameters, ...data};
    final keys = merged.keys.toList()..sort();
    final sorted = <String, Object?>{
      for (final key in keys)
        key: merged[key] is num ? merged[key].toString() : merged[key],
    };
    String pad(int value) => value.toString().padLeft(2, '0');
    final stamp = '${time.year}${pad(time.month)}${pad(time.day)}'
        '${pad(time.hour)}${pad(time.minute)}${pad(time.second)}';
    return {
      'X-Sign': md5
          .convert(utf8.encode('${jsonEncode(sorted)}$salt'))
          .toString()
          .toUpperCase(),
      'X-TIMESTAMP': stamp,
    };
  }
}
