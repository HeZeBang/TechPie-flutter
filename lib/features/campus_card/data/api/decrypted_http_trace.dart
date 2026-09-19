import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/debug_mode_features.dart';
import 'ecard_cipher.dart';

const _traceRequested = bool.fromEnvironment('GEEKPAY_TRACE_DECRYPTED_HTTP');
const _marker = '[GEEKPAY_HTTP]';

bool get decryptedHttpTraceEnabled =>
    debugModeFeaturesAvailable && _traceRequested;

void installDecryptedHttpTrace(
  Dio dio, {
  DecryptedHttpTraceInterceptor? trace,
}) {
  if ((trace == null && !decryptedHttpTraceEnabled) ||
      dio.interceptors.any((value) => value is DecryptedHttpTraceInterceptor)) {
    return;
  }
  dio.interceptors.add(trace ?? DecryptedHttpTraceInterceptor());
}

final class DecryptedHttpTraceInterceptor extends Interceptor {
  DecryptedHttpTraceInterceptor({
    bool Function()? enabled,
    void Function(Map<String, Object?> record)? onRecord,
  })  : _enabled = enabled ?? (() => decryptedHttpTraceEnabled),
        _onRecord = onRecord;

  final bool Function() _enabled;
  final void Function(Map<String, Object?> record)? _onRecord;

  static const _requestIdKey = 'geekpay.decryptedTrace.requestId';
  static const _startedAtKey = 'geekpay.decryptedTrace.startedAt';

  /// A caller that spends time before the request is sent — preparing a session,
  /// checking an identity — can put that cost here, so the trace reports it
  /// beside the wire time instead of hiding it.
  static const prepMicrosKey = 'geekpay.decryptedTrace.prepMicros';

  var _nextRequestId = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_enabled()) {
      handler.next(options);
      return;
    }
    final requestId = ++_nextRequestId;
    options.extra[_requestIdKey] = requestId;
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    final decodedRequest = _decodeRequest(options);
    _write({
      'event': 'request',
      'requestId': requestId,
      'method': options.method,
      'url': '${options.uri.origin}${options.uri.path}',
      'scheme': options.uri.scheme,
      'host': options.uri.host,
      'port': options.uri.hasPort ? options.uri.port : null,
      'path': options.uri.path,
      'headers': options.headers,
      'payload': decodedRequest,
      if (_scanCodeFingerprint(options.uri.path, decodedRequest) case final fp?)
        'qrcodeFingerprint': fp,
    });
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    if (!_enabled() || !options.extra.containsKey(_requestIdKey)) {
      handler.next(response);
      return;
    }
    final decodedResponse = _decodeResponse(response.data);
    _write({
      'event': 'response',
      'requestId': options.extra[_requestIdKey],
      'method': options.method,
      'url': '${options.uri.origin}${options.uri.path}',
      'path': options.uri.path,
      'statusCode': response.statusCode,
      'durationMicros': _durationMicros(options),
      if (options.extra[prepMicrosKey] case final prepMicros?)
        'prepMicros': prepMicros,
      'headers': response.headers.map,
      'payload': decodedResponse,
      if (_scanCodeFingerprint(options.uri.path, decodedResponse)
          case final fp?)
        'qrcodeFingerprint': fp,
    });
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    if (!_enabled() || !options.extra.containsKey(_requestIdKey)) {
      handler.next(err);
      return;
    }
    final response = err.response;
    _write({
      'event': 'errorResponse',
      'requestId': options.extra[_requestIdKey],
      'method': options.method,
      'url': '${options.uri.origin}${options.uri.path}',
      'path': options.uri.path,
      'statusCode': response?.statusCode,
      'durationMicros': _durationMicros(options),
      if (options.extra[prepMicrosKey] case final prepMicros?)
        'prepMicros': prepMicros,
      'dioExceptionType': err.type.name,
      'message': err.message,
      'headers': response?.headers.map,
      'payload': _decodeResponse(response?.data),
    });
    handler.next(err);
  }

  Object? _decodeRequest(RequestOptions options) {
    final query = Map<String, Object?>.from(options.queryParameters);
    final queryEnvelope = query.remove('datajson');
    final body = options.data;
    if (queryEnvelope is String) {
      return {
        'query': query,
        'decryptedDatajson': _decodeEnvelope(queryEnvelope),
      };
    }
    if (body is Map && body['datajson'] is String) {
      final bodyFields = body.map(
        (key, value) => MapEntry(key.toString(), value),
      )..remove('datajson');
      return {
        'query': query,
        'body': bodyFields,
        'decryptedDatajson': _decodeEnvelope(body['datajson'] as String),
      };
    }
    return {'query': query, 'body': body};
  }

  /// Length and digest for comparing scan codes in redacted Debug Logs.
  Object? _scanCodeFingerprint(String path, Object? decoded) {
    if (path != '/scan/scanningResult') return null;
    final code = _findScanCode(decoded);
    if (code == null || code.isEmpty) return null;
    final digest = sha256.convert(utf8.encode(code)).toString();
    return {'length': code.length, 'sha256_12': digest.substring(0, 12)};
  }

  String? _findScanCode(Object? node) {
    if (node is! Map) return null;
    final code = node['qrcode'];
    if (code is String && code.isNotEmpty) return code;
    for (final key in const ['decryptedDatajson', 'data', 'body', 'query']) {
      final nested = _findScanCode(node[key]);
      if (nested != null) return nested;
    }
    return null;
  }

  Object? _decodeEnvelope(String envelope) {
    try {
      return EcardCipher.decodeEnvelope(envelope);
    } catch (error) {
      return {'decodeError': error.toString(), 'wireDatajson': envelope};
    }
  }

  Object? _decodeResponse(Object? body) {
    if (body is List<int>) return {'binaryBytes': body.length};
    try {
      return EcardCipher.decodeResponse(body);
    } catch (error) {
      return {'decodeError': error.toString(), 'wireBody': body};
    }
  }

  int? _durationMicros(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return null;
    return DateTime.now().microsecondsSinceEpoch - startedAt;
  }

  void _write(Map<String, Object?> record) {
    if (!_enabled()) return;
    final onRecord = _onRecord;
    if (onRecord != null) {
      // An optional diagnostics consumer must never interrupt a payment request.
      try {
        onRecord(record);
      } catch (_) {}
      return;
    }
    final requestId = record['requestId'] ?? '?';
    final encoded = JsonEncoder.withIndent('  ', _toEncodable).convert(record);
    for (final line in const LineSplitter().convert(encoded)) {
      if (line.isEmpty) {
        debugPrintSynchronously('$_marker[$requestId]');
        continue;
      }
      const chunkSize = 700;
      for (var offset = 0; offset < line.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, line.length);
        debugPrintSynchronously(
          '$_marker[$requestId] ${line.substring(offset, end)}',
        );
      }
    }
  }

  Object? _toEncodable(Object? value) {
    if (value is Uint8List) {
      return {
        'encoding': 'base64',
        'length': value.length,
        'data': base64Encode(value),
      };
    }
    if (value is ByteBuffer) {
      final bytes = value.asUint8List();
      return {
        'encoding': 'base64',
        'length': bytes.length,
        'data': base64Encode(bytes),
      };
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Uri) return value.toString();
    return value.toString();
  }
}
