import 'dart:collection';
import 'dart:convert';

import '../ids/campus_http.dart';
import 'campus_errors.dart';
import 'campus_session.dart';
import 'eams_html_parser.dart';

class EamsClient {
  EamsClient(
    this.session, {
    this.minInterval = const Duration(milliseconds: 1600),
    this.retryDelay = const Duration(milliseconds: 2500),
  });
  final CampusSession session;
  final Duration minInterval;
  final Duration retryDelay;
  final _clock = Stopwatch()..start();
  Duration _next = Duration.zero;
  Future<void> _tail = Future.value();
  final _inFlight = Expando<Map<String, Future<CampusResponse>>>();
  final _semesters = Expando<Map<String, String>>();

  Future<CampusResponse> _schedule(SendRequest send) {
    final task = _tail.then((_) async {
      final wait = _next - _clock.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      late final CampusResponse response;
      try {
        response = await send();
      } finally {
        _next = _clock.elapsed + minInterval;
      }
      if (_limited(response)) {
        final backoff = _clock.elapsed + retryDelay;
        if (backoff > _next) _next = backoff;
        throw const CampusRequestException(CampusErrorKind.rateLimited, '教务系统请求过于频繁，请稍后再试');
      }
      return response;
    });
    _tail = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  static bool _text(CampusResponse response) {
    final contentType = response.headers.value('content-type') ?? '';
    return contentType.isEmpty || contentType.startsWith('text/') || contentType.contains('json');
  }

  static bool _limited(CampusResponse r) =>
      r.statusCode == 429 || (_text(r) && CampusHttp.text(r).contains('请不要过快点击'));

  Future<CampusResponse> _request(
    CampusWire wire,
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
  }) {
    final active = _inFlight[wire] ??= {};
    final key = jsonEncode([
      method,
      path,
      SplayTreeMap.of(query ?? <String, String>{}),
      SplayTreeMap.of(form ?? <String, String>{}),
    ]);
    return active.putIfAbsent(key, () async {
      try {
        for (var attempt = 0;; attempt++) {
          late final CampusResponse r;
          try {
            r = await wire.request(
              path,
              method: method,
              query: query,
              data: form,
              headers: form == null ? null : formHeaders,
              schedule: _schedule,
            );
          } on CampusRequestException catch (error) {
            if (error.kind == CampusErrorKind.rateLimited && attempt == 0) continue;
            rethrow;
          }
          checkStatus(r);
          if (_text(r) && EamsHtmlParser.isLoginPage(CampusHttp.text(r))) {
            throw CampusRequestException.expired;
          }
          return r;
        }
      } finally {
        active.remove(key)?.ignore();
      }
    });
  }

  Future<String> getHtml(String path, {Map<String, String>? query}) =>
      session.run((wire) async => CampusHttp.text(await _request(wire, 'GET', path, query: query)));
  Future<String> postForm(String path, Map<String, String> form) =>
      session.run((wire) async => CampusHttp.text(await _request(wire, 'POST', path, form: form)));
  Future<Map<String, dynamic>> getJson(String path, {Map<String, String>? query}) =>
      session.run((wire) async => jsonObject(await _request(wire, 'GET', path, query: query)));
  Future<List<int>> downloadBytes(
    String path, {
    String method = 'GET',
    Map<String, String>? form,
  }) =>
      session.run((wire) async => (await _request(wire, method, path, form: form)).data ?? []);
  Future<Map<String, String>> fetchSemesters({bool forceRefresh = false}) =>
      session.run((wire) async {
        final cached = _semesters[wire];
        if (!forceRefresh && cached != null) return cached;
        final r =
            await _request(wire, 'POST', '/eams/dataQuery.action', form: {'dataType': 'semester'});
        final terms = EamsHtmlParser.options(CampusHttp.text(r));
        if (terms.isEmpty) throw CampusRequestException.invalid;
        return _semesters[wire] = Map.unmodifiable(terms);
      });
}
