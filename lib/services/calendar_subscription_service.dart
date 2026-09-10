import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_base_url.dart';
import 'auth_service.dart';
import 'ics/ics_export_service.dart';
import 'schedule_service.dart';
import 'storage_service.dart';

class CalendarSubscriptionException implements Exception {
  const CalendarSubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CalendarSubscriptionService extends ChangeNotifier {
  CalendarSubscriptionService(this.auth, this.storage, this.schedule,
      {http.Client? client,})
      : _client = client ?? http.Client() {
    schedule.addListener(_scheduleChanged);
  }
  final AuthService auth;
  final StorageService storage;
  final ScheduleService schedule;
  final http.Client _client;
  Map<String, dynamic>? _record;
  bool _busy = false;
  String? _error;
  DateTime? _observedUpdate;
  bool get busy => _busy;
  String? get error => _error;
  Map<String, dynamic>? get _current =>
      _record?['primaryId'] == auth.session?.userId &&
              _record?['api'] == apiBaseUrl(storage)
          ? _record
          : null;
  bool get enabled => _current?['id'] != null;
  String? get updatedAt => _current?['updatedAt'] as String?;
  String? get expiresAt => _current?['expiresAt'] as String?;
  Uri? get url => !enabled
      ? null
      : Uri.parse(
          '${apiBaseUrl(storage)}/calendar/subscribe/${_current!['id']}',);

  Future<void> initialize() async {
    _record = await storage.loadCalendarSubscription();
    _observedUpdate = schedule.updatedAt;
  }

  void _scheduleChanged() {
    final updated = schedule.updatedAt;
    if (schedule.loading ||
        schedule.error != null ||
        updated == null ||
        updated == _observedUpdate) {
      return;
    }
    _observedUpdate = updated;
    if (!enabled ||
        _current?['campusOwner'] != schedule.owner ||
        _current?['semester'] != schedule.selectedSemesterId ||
        _busy) {
      return;
    }
    unawaited(publish().catchError((Object _) {}));
  }

  Future<Map<String, dynamic>> _send(String method,
      [Map<String, dynamic>? body,]) async {
    final primaryId = auth.session?.userId;
    if (primaryId == null) {
      throw const CalendarSubscriptionException('请先登录 TechPie 主账号');
    }
    Future<http.Response> request() async {
      final token = auth.session?.geekpieToken;
      if (token == null || token.isEmpty || auth.session?.userId != primaryId) {
        throw const CalendarSubscriptionException('请重新登录 TechPie 主账号');
      }
      final request = http.Request(
          method, Uri.parse('${apiBaseUrl(storage)}/calendar/subscription'),)
        ..headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      return http.Response.fromStream(await _client.send(request));
    }

    try {
      var response = await request().timeout(const Duration(seconds: 60));
      if (response.statusCode == 401 && await auth.tryRenewSession()) {
        response = await request().timeout(const Duration(seconds: 60));
      }
      if (auth.session?.userId != primaryId) {
        throw const CalendarSubscriptionException('主账号已变更，请重新加载');
      }
      if (response.statusCode == 401) {
        throw const CalendarSubscriptionException('请重新登录 TechPie 主账号');
      }
      if (response.statusCode == 409) {
        throw const CalendarSubscriptionException('订阅已变更，请重新加载后操作');
      }
      if (response.statusCode == 404 || response.statusCode == 503) {
        throw const CalendarSubscriptionException('课表订阅服务暂不可用，请稍后重试');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || data['success'] != true) {
        throw const CalendarSubscriptionException('课表订阅操作失败，请稍后重试');
      }
      return data;
    } on CalendarSubscriptionException {
      rethrow;
    } catch (_) {
      throw const CalendarSubscriptionException('无法连接课表订阅服务，请稍后重试');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> reload() => _run(() async {
        final data = (await _send('GET'))['data'];
        if (data == null) {
          _record = null;
        } else {
          final remote = (data as Map).cast<String, dynamic>();
          _record = {
            if (_current?['id'] == remote['id']) ..._current!,
            ...remote,
            'primaryId': auth.session!.userId,
            'api': apiBaseUrl(storage),
          };
        }
        await storage.saveCalendarSubscription(_record);
      });

  Future<void> publish() => _run(() async {
        final owner = schedule.owner;
        final semester = schedule.selectedSemesterId;
        final table = schedule.courseTable;
        final termBegin = schedule.termBegin;
        if (owner == null ||
            table == null ||
            termBegin == null ||
            schedule.error != null ||
            schedule.loading) {
          throw const CalendarSubscriptionException('请先成功刷新当前课表');
        }
        final calendar = IcsExportService().buildCalendar(
          table: table,
          termBegin: termBegin,
          calendarName:
              schedule.semesterInfo?.findSemesterLabel(semester ?? '') ?? '课表',
        );
        final data = (await _send('PUT', {
          if (enabled) 'id': _current!['id'],
          'calendar': calendar,
        }))['data'] as Map;
        _record = {
          ...data.cast<String, dynamic>(),
          'primaryId': auth.session!.userId,
          'api': apiBaseUrl(storage),
          'campusOwner': owner,
          'semester': semester,
        };
        await storage.saveCalendarSubscription(_record);
      });

  Future<void> revoke() => _run(() async {
        if (!enabled) return;
        await _send('DELETE', {'id': _current!['id']});
        _record = null;
        await storage.saveCalendarSubscription(null);
      });

  @override
  void dispose() {
    schedule.removeListener(_scheduleChanged);
    _client.close();
    super.dispose();
  }
}
