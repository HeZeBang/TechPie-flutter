import 'dart:convert';

import 'package:dio/dio.dart';

import '../ids/campus_http.dart';
import 'campus_errors.dart';
import 'campus_session.dart';
import 'eams_html_parser.dart';

class EmapPageResult {
  const EmapPageResult(this.rows, this.totalSize);
  final List<Map<String, dynamic>> rows;
  final int totalSize;
}

class EmapClient {
  EmapClient(this.session);
  final CampusSession session;
  final _bootstrappedApps = Expando<Map<(String, String), Future<void>>>();

  void _check(CampusResponse response, {bool file = false}) {
    checkStatus(response);
    final prefix = utf8
        .decode((response.data ?? []).take(512).toList(), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    if (prefix.startsWith('<!doctype') ||
        prefix.startsWith('<html') ||
        (!file &&
            prefix.startsWith('<') &&
            EamsHtmlParser.isLoginPage(CampusHttp.text(response)))) {
      throw CampusRequestException.expired;
    }
  }

  Future<CampusResponse> _request(
    String app,
    String appId,
    String path, {
    String method = 'POST',
    Map<String, String>? query,
    Object? form,
    bool fileComponent = false,
    bool singleSubmission = false,
  }) {
    final base = '/xsfw/sys/${segment(app)}/';
    final route = Uri.parse(path.replaceFirst(RegExp(r'^/'), ''));
    if (route.hasScheme ||
        route.hasAuthority ||
        route.pathSegments.any((p) => p == '..' || p.isEmpty)) {
      throw ArgumentError('Expected an application-relative action');
    }
    final headers = {
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': '${session.origin.origin}$base*default/index.do',
    };
    final target = fileComponent ? '/xsfw/sys/emapcomponent/file/$route' : '$base$route';
    final requestHeaders = form is Map<String, String> ? {...headers, ...formHeaders} : headers;
    var dispatched = false;
    return session.run(
      (wire) async {
        final cache = _bootstrappedApps[wire] ??= {};
        final key = (app, appId);
        Future<void> bootstrap() async {
          final r = await wire.request(
            '/xsfw/sys/funauthapp/api/getAppConfig/${segment(app)}-${segment(appId)}.do',
            headers: headers,
          );
          _check(r);
        }

        if (singleSubmission) {
          // Verify/bootstrap via an idempotent GET first so expired cookies renew
          // before a non-idempotent POST leaves the wire.
          final fresh = bootstrap();
          cache[key] = fresh;
          try {
            await fresh;
          } catch (_) {
            if (identical(cache[key], fresh)) cache.remove(key)?.ignore();
            rethrow;
          }
          dispatched = true;
          final r = await wire.request(
            target,
            method: method,
            query: query,
            data: form,
            headers: requestHeaders,
            allowBodyRedirect: false,
          );
          _check(r);
          return r;
        }

        for (var attempt = 0;; attempt++) {
          final ready = cache.putIfAbsent(key, bootstrap);
          try {
            await ready;
          } catch (_) {
            if (identical(cache[key], ready)) cache.remove(key)?.ignore();
            rethrow;
          }
          final r = await wire.request(
            target,
            method: method,
            query: query,
            data: form,
            headers: requestHeaders,
          );
          if (r.statusCode == 403 && attempt == 0) {
            if (identical(cache[key], ready)) cache.remove(key)?.ignore();
            continue;
          }
          _check(r);
          return r;
        }
      },
      canRetryExpired: singleSubmission ? () => !dispatched : null,
    );
  }

  Future<EmapPageResult> queryModel({
    required String app,
    required String appId,
    required String module,
    required String model,
    int pageSize = 20,
    int pageNumber = 1,
    List<Map<String, dynamic>>? querySetting,
    Map<String, String>? extraForm,
    bool allowMissingTotalSize = false,
  }) async {
    final body = jsonObject(
      await _request(
        app,
        appId,
        'modules/${segment(module)}/${segment(model)}.do',
        form: {
          ...?extraForm,
          'pageSize': '$pageSize',
          'pageNumber': '$pageNumber',
          if (querySetting != null) 'querySetting': jsonEncode(querySetting),
        },
      ),
    );
    if ('${body['code']}' != '0') {
      throw const CampusRequestException(CampusErrorKind.rejected, '学工系统未接受查询');
    }
    final datas = body['datas'];
    final page = datas is Map ? datas[model] : null;
    if (page is! Map) throw CampusRequestException.invalid;
    final rows = page['rows'];
    final rawTotal = page['totalSize'];
    final total = rawTotal == null && allowMissingTotalSize
        ? (rows is List ? rows.length : null)
        : int.tryParse('$rawTotal');
    if (rows is! List || total == null || !rows.every((v) => v is Map<String, dynamic>)) {
      throw CampusRequestException.invalid;
    }
    return EmapPageResult(rows.cast<Map<String, dynamic>>(), total);
  }

  Future<Map<String, dynamic>> getAction({
    required String app,
    required String appId,
    required String path,
    Map<String, String>? query,
  }) async =>
      jsonObject(
        await _request(app, appId, path, method: 'GET', query: query),
      );

  Future<Map<String, dynamic>> postAction({
    required String app,
    required String appId,
    required String path,
    Map<String, String> form = const {},
    bool singleSubmission = false,
  }) async =>
      jsonObject(
        await _request(
          app,
          appId,
          path,
          form: form,
          singleSubmission: singleSubmission,
        ),
      );

  /// EMAP's shared file component uses the calling application's session.
  Future<Map<String, dynamic>> postFileComponent({
    required String app,
    required String appId,
    required String path,
    required Object form,
    bool singleSubmission = false,
  }) async =>
      jsonObject(
        await _request(
          app,
          appId,
          path,
          form: form,
          singleSubmission: singleSubmission,
          fileComponent: true,
        ),
      );

  /// Submits a plain-text write action at most once without automatic retries.
  Future<String> submitTextOnce({
    required String app,
    required String appId,
    required String path,
    Map<String, String> form = const {},
  }) async =>
      CampusHttp.text(
        await _request(app, appId, path, form: form, singleSubmission: true),
      );

  Future<Map<String, dynamic>> commonCall({
    required String app,
    required String appId,
    required String actionName,
    required String actionType,
    String? dataModelAction,
    required Object requestParams,
    bool batch = false,
    bool singleSubmission = true,
  }) async {
    final name = [actionName, actionType, if (dataModelAction != null) dataModelAction]
        .map(segment)
        .join('-');
    final result = jsonObject(
      await _request(
        app,
        appId,
        'commoncall/${batch ? 'callBatch' : 'call'}/$name.do',
        form: {'requestParams': jsonEncode(requestParams)},
        singleSubmission: singleSubmission,
      ),
    );
    if (result['resultCode'] != '00000') {
      throw const CampusRequestException(CampusErrorKind.rejected, '学工系统未接受操作');
    }
    return result;
  }

  Future<Map<String, dynamic>> uploadTempFile({
    required String scope,
    required String token,
    required List<int> bytes,
    required String filename,
  }) =>
      session.run((wire) async {
        final response = await wire.request(
          '/xsfw/sys/emapcomponent/file/uploadTempFile/${segment(scope)}/${segment(token)}.do',
          method: 'POST',
          allowBodyRedirect: false,
          data: FormData.fromMap({
            'bhFile': MultipartFile.fromBytes(bytes, filename: filename),
            'storeId': 'imexport',
          }),
        );
        _check(response);
        return jsonObject(response);
      });

  Future<List<int>> downloadFileByToken(String token) => session.run((wire) async {
        final response =
            await wire.request('/xsfw/sys/emapcomponent/file/getFileByToken/${segment(token)}.do');
        _check(response, file: true);
        return response.data ?? [];
      });
}
