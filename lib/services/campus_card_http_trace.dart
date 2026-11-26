import '../features/campus_card/data/api/decrypted_http_trace.dart';
import 'debug_logger.dart';

/// The transport emits metadata only. A scan fingerprint relates the two payment phases.
DecryptedHttpTraceInterceptor campusCardHttpTrace(DebugLogger logger) =>
    DecryptedHttpTraceInterceptor(
      enabled: () => logger.enabled,
      onRecord: (record) {
        final isRequest = record['event'] == 'request';
        final summary = <String, Object?>{
          'requestId': record['requestId'],
          if (record['qrcodeFingerprint'] case final fingerprint?) 'qrcodeFingerprint': fingerprint,
        };
        logger.log(
          method: record['method']! as String,
          uri: Uri.parse(record['url']! as String),
          statusCode: record['statusCode'] as int?,
          requestSummary: isRequest ? summary : null,
          responseSummary: isRequest ? null : summary,
          error: record['dioExceptionType'] as String?,
          tag: 'Campus Card',
          durationMicros: record['durationMicros'] as int?,
          prepMicros: record['prepMicros'] as int?,
        );
      },
    );
