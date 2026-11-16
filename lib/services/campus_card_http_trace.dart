import 'dart:convert';

import '../features/campus_card/data/api/decrypted_http_trace.dart';
import 'debug_logger.dart';

/// Sends the feature's existing request trace to TechPie's shared debug log.
/// The logger's live switch gates both auth and card requests. Redaction is
/// applied here rather than in the shared logger: the debug log deliberately
/// records API traffic verbatim so session problems stay diagnosable, while
/// card traffic carries pay passwords and codes that must never be written.
DecryptedHttpTraceInterceptor campusCardHttpTrace(DebugLogger logger) =>
    DecryptedHttpTraceInterceptor(
      enabled: () => logger.enabled,
      onRecord: (record) {
        final isRequest = record['event'] == 'request';
        final fingerprint = record['qrcodeFingerprint'];
        final raw = record['path'] == '/offlineCode/openVirtualcard'
            ? _redactOnlineCode(record['payload'])
            : record['payload'];
        // Scan payments log a length/digest pair so both phases can be
        // compared without writing the code itself.
        final payload = fingerprint == null || raw is! Map
            ? raw
            : <String, Object?>{
                ...raw.cast<String, Object?>(),
                'qrcodeFingerprint': fingerprint,
              };
        logger.log(
          method: record['method']! as String,
          url: record['url']! as String,
          statusCode: record['statusCode'] as int?,
          requestBody: isRequest
              ? DebugLogger.redactSensitive(jsonEncode(payload))
              : null,
          responseBody: isRequest
              ? null
              : DebugLogger.redactSensitive(jsonEncode(payload)),
          error: record['dioExceptionType'] as String?,
          tag: 'Campus Card',
          durationMicros: record['durationMicros'] as int?,
          prepMicros: record['prepMicros'] as int?,
        );
      },
    );

Object? _redactOnlineCode(Object? payload) {
  if (payload is! Map || payload['data'] is! Map) return payload;
  final data = payload['data'] as Map;
  if (!data.containsKey('code')) return payload;
  return <Object?, Object?>{
    ...payload,
    'data': <Object?, Object?>{...data, 'code': data['code'] == null ? null : '***'},
  };
}
