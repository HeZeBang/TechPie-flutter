import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/assignment.dart';
import '../models/course.dart';
import '../models/custom_course.dart';
import 'assignment_service.dart';
import 'campus_card_service.dart';
import 'schedule_service.dart';
import 'schedule_timeline_service.dart';
import 'storage_service.dart';

/// 手机端小米手环通信状态（经小米运动健康穿戴服务中转）。
class BandService extends ChangeNotifier {
  BandService._();

  static final BandService instance = BandService._();

  static const _method = MethodChannel('techpie/band');
  static const _events = EventChannel('techpie/band_events');

  StreamSubscription<dynamic>? _subscription;
  bool _started = false;
  bool _disposed = false;

  ScheduleService? _schedule;
  AssignmentService? _assignments;
  StorageService? _storage;
  CampusCardService? _campusCard;
  Timer? _rescheduleDebounce;

  bool serviceConnected = false;
  String? nodeId;
  String? nodeName;
  bool permissionGranted = false;
  bool? wearAppInstalled;
  String? lastError;
  int? lastMessageAt;
  int? lastPongAt;
  int? lastReminderAt;
  String? lastReminder;
  bool exactAlarms = true;
  List<String> messages = const [];

  bool get hasDevice => nodeId != null;

  /// 注入课表数据源；应在 app 启动时调用一次。
  void attach(
    ScheduleService schedule,
    AssignmentService assignments,
    StorageService storage,
    CampusCardService campusCard,
  ) {
    _schedule?.removeListener(_onScheduleChanged);
    _assignments?.removeListener(_onScheduleChanged);
    _schedule = schedule;
    _assignments = assignments;
    _storage = storage;
    _campusCard = campusCard;
    schedule.removeListener(_onScheduleChanged);
    schedule.addListener(_onScheduleChanged);
    assignments.removeListener(_onScheduleChanged);
    assignments.addListener(_onScheduleChanged);
  }

  void _onScheduleChanged() {
    _rescheduleDebounce?.cancel();
    _rescheduleDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(rescheduleReminders()),
    );
  }

  bool get reminderEnabled => _storage?.bandReminderEnabled ?? false;
  int get reminderLeadMinutes => _storage?.bandReminderLeadMinutes ?? 10;
  bool get assignmentReminderEnabled =>
      _storage?.bandAssignmentReminderEnabled ?? true;

  bool get offlineCredEnabled => _storage?.bandOfflineCredEnabled ?? false;

  Future<void> setOfflineCredEnabled(bool value) async {
    await _storage?.setBandOfflineCredEnabled(value);
    _notify();
  }

  Future<void> setReminderEnabled(bool value) async {
    await _storage?.setBandReminderEnabled(value);
    await rescheduleReminders();
    _notify();
  }

  Future<void> setReminderLeadMinutes(int value) async {
    await _storage?.setBandReminderLeadMinutes(value);
    await rescheduleReminders();
    _notify();
  }

  Future<void> setAssignmentReminderEnabled(bool value) async {
    await _storage?.setBandAssignmentReminderEnabled(value);
    await rescheduleReminders();
    _notify();
  }

  /// 打开系统的「闹钟和提醒」精确闹钟授权页。
  Future<void> requestExactAlarmPermission() async {
    await _invoke('requestExactAlarmPermission');
  }

  Future<void> sendTestNotification() async {
    await _invoke('sendNotification', {
      'title': 'TechPie 测试通知',
      'message': '上课提醒通道正常',
    });
  }

  /// 按当前课表重排未来七天的上课提醒（AlarmManager 触发，不依赖前台）。
  Future<void> rescheduleReminders() async {
    final storage = _storage;
    final schedule = _schedule;
    if (storage == null || schedule == null) return;
    if (!storage.bandReminderEnabled) {
      await _invoke('cancelReminders');
      return;
    }
    final lead = storage.bandReminderLeadMinutes;
    final now = DateTime.now();
    final reminders = <Map<String, Object?>>[];
    for (var offset = 0; offset <= 6; offset++) {
      final day = DateTime(now.year, now.month, now.day)
          .add(Duration(days: offset));
      final isToday = offset == 0;
      final dayPoint = isToday
          ? now
          : DateTime(day.year, day.month, day.day, 12);
      final week =
          teachingWeekOf(day, schedule.termBegin) ?? schedule.currentWeek();
      final courses = ScheduleTimeline.todayCourses(
        table: schedule.courseTable,
        customCourses: schedule.customCourses,
        week: week,
        termBegin: schedule.termBegin,
        assignments: _assignments?.assignments ?? const <Assignment>[],
        semesterId: schedule.selectedSemesterId,
        now: dayPoint,
      );
      for (final course in courses) {
        final minutes = parseClockMinutes(course.startTime);
        if (minutes == null) continue;
        final start = DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
        final at = start.subtract(Duration(minutes: lead));
        if (!at.isAfter(now)) continue;
        reminders.add({
          'at': at.millisecondsSinceEpoch,
          'title': '还有 $lead 分钟上课',
          'body': '${course.name} · ${course.location} · ${course.startTime}',
        });
      }
    }
    if (storage.bandAssignmentReminderEnabled) {
      for (final item in _assignments?.assignments ?? const <Assignment>[]) {
        if (item.submitted || !item.due.isAfter(now)) continue;
        final at = item.due.subtract(const Duration(days: 1));
        if (!at.isAfter(now)) continue;
        final course = item.course.isEmpty ? '' : ' · ${item.course}';
        reminders.add({
          'at': at.millisecondsSinceEpoch,
          'title': '${item.kind.label}明天截止',
          'body': '${item.title}$course · ${_fmtMonthDay(item.due)} ${_fmtClock(item.due)}',
        });
      }
    }
    reminders.sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));
    await _invoke('scheduleReminders', {
      'reminders': reminders.take(64).toList(growable: false),
    });
  }

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _method.invokeMethod<Object?>(method, args);
    } on PlatformException catch (error) {
      _setError(error.message);
    } on MissingPluginException {
      // 非 Android 平台没有该通道。
    }
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _method.setMethodCallHandler(_onMethodCall);
    _subscription = _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object _) {},
        );
    await refresh();
    await rescheduleReminders();
  }

  Future<void> refresh() async {
    await _call('refresh');
    // 自愈：开关关闭期间每次刷新都重发清除指令，
    // 防止关开关时手环断连、清除消息丢失后手环仍留有凭证/离线码。
    if (!offlineCredEnabled) {
      await _call('sendOfflineCredClear');
    }
  }

  Future<void> requestPermission() async {
    await _call('requestPermission');
  }

  Future<void> sendTest() async {
    await _call('sendTest');
  }

  /// 把离线支付凭证（私钥 + 离线授权）下发到手环；仅由「同步离线支付凭证」开关触发。
  Future<void> pushOfflineCredential() async {
    await _call('sendOfflineCred');
  }

  /// 清除手环本地保存的离线支付凭证（含私钥）；由开关关闭触发。
  Future<void> clearOfflineCredential() async {
    await _call('sendOfflineCredClear');
  }

  Future<void> _call(String method) async {
    try {
      final status = await _method.invokeMapMethod<String, dynamic>(method);
      if (status != null) _apply(status);
    } on PlatformException catch (error) {
      _setError(error.message);
    } on MissingPluginException {
      _setError('当前平台不支持手环通信');
    }
  }

  /// 手环快应用请求课表快照（由 Kotlin 侧经 MethodChannel 反向调用）。
  Future<Object?> _onMethodCall(MethodCall call) async {
    if (call.method == 'scheduleRequest') {
      final args = call.arguments;
      final date = args is Map ? args['date'] as String? : null;
      final wantWeek = args is Map && args['week'] == true;
      if (wantWeek) {
        final week = _buildWeekSnapshot();
        debugPrint('[BandService] scheduleRequest week -> '
            '${(week['days'] as List?)?.length ?? 0} days');
        return week;
      }
      final snapshot = _buildSnapshot(date);
      debugPrint('[BandService] scheduleRequest $date -> '
          '${(snapshot['courses'] as List?)?.length ?? 0} courses');
      return snapshot;
    }
    if (call.method == 'assignmentsRequest') {
      final snapshot = _buildAssignmentsSnapshot();
      debugPrint('[BandService] assignmentsRequest -> '
          '${(snapshot['items'] as List?)?.length ?? 0} items');
      return snapshot;
    }
    if (call.method == 'ecardRequest') {
      // 开关关闭时绝不下发任何离线码数据（手机渲染的二维码也不发）。
      if (!offlineCredEnabled) {
        return {'t': 'ecard.snap', 'error': '未授权，请在手机端开启同步离线支付凭证'};
      }
      final campusCard = _campusCard;
      if (campusCard == null) {
        return {'t': 'ecard.snap', 'error': '校园卡服务未就绪'};
      }
      final image = await campusCard.generateOfflinePaymentImage();
      debugPrint('[BandService] ecardRequest -> '
          '${image.containsKey('png') ? 'image' : image['error']}');
      return {'t': 'ecard.snap', ...image};
    }
    if (call.method == 'offlineCredRequest') {
      if (!offlineCredEnabled) {
        return {'t': 'offline.cred', 'error': '未授权，请在手机端开启同步离线支付凭证'};
      }
      final campusCard = _campusCard;
      if (campusCard == null) {
        return {'t': 'offline.cred', 'error': '校园卡服务未就绪'};
      }
      final cred = await campusCard.exportOfflineCredentialForBand();
      debugPrint('[BandService] offlineCredRequest -> '
          '${cred.containsKey('privateKey') ? 'credential' : cred['error']}');
      return cred;
    }
    throw MissingPluginException('unknown method ${call.method}');
  }

  Map<String, Object?> _buildSnapshot(String? dateArg) {
    final schedule = _schedule;
    if (schedule == null) {
      return {'t': 'schedule.snap', 'error': 'not_ready'};
    }
    final actualNow = DateTime.now();
    final requested = _parseDate(dateArg) ?? actualNow;
    final isToday = _sameDay(requested, actualNow);
    // 非当天用中午判定周次/日期，状态一律视为未开始。
    final day = isToday
        ? actualNow
        : DateTime(requested.year, requested.month, requested.day, 12);
    final week =
        teachingWeekOf(requested, schedule.termBegin) ?? schedule.currentWeek();
    final courses = ScheduleTimeline.todayCourses(
      table: schedule.courseTable,
      customCourses: schedule.customCourses,
      week: week,
      termBegin: schedule.termBegin,
      assignments: _assignments?.assignments ?? const <Assignment>[],
      semesterId: schedule.selectedSemesterId,
      now: day,
    );
    String stateOf(Course course) =>
        isToday ? ScheduleTimeline.courseState(course, actualNow) : 'upcoming';
    Map<String, Object?>? next;
    for (final course in courses) {
      final state = stateOf(course);
      if (!isToday || state == 'soon' || state == 'upcoming') {
        next = {
          'name': course.name,
          'location': course.location,
          'start': course.startTime,
          'end': course.endTime,
          'day': isToday ? '今天' : '当日',
        };
        break;
      }
    }
    return {
      't': 'schedule.snap',
      'date': _fmtDate(requested),
      'isToday': isToday,
      'week': week,
      'now': _fmtClock(actualNow),
      'next': next,
      'courses': [
        for (final course in courses)
          {
            'n': course.name,
            'loc': course.location,
            's': course.startTime,
            'e': course.endTime,
            'st': stateOf(course),
          },
      ],
    };
  }

  /// 整周快照：前 7 天后 6 天，一次同步覆盖手环翻页浏览（手环侧缓存 7 天）。
  Map<String, Object?> _buildWeekSnapshot() {
    if (_schedule == null) {
      return {'t': 'schedule.week', 'error': 'not_ready'};
    }
    final actualNow = DateTime.now();
    final today = DateTime(actualNow.year, actualNow.month, actualNow.day);
    Map<String, Object?> day(int offset) {
      final snap = _buildSnapshot(
        _fmtDate(DateTime(today.year, today.month, today.day + offset)),
      );
      return {'date': snap['date'], 'courses': snap['courses']};
    }

    return {
      't': 'schedule.week',
      'now': _fmtClock(actualNow),
      'days': [for (var offset = -7; offset <= 6; offset++) day(offset)],
    };
  }

  Map<String, Object?> _buildAssignmentsSnapshot() {
    final now = DateTime.now();
    final items = (_assignments?.assignments ?? const <Assignment>[])
        .where((item) => !item.submitted && item.due.isAfter(now))
        .toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return {
      't': 'assignments.snap',
      'items': [
        for (final item in items.take(10))
          {
            'title': item.title,
            'course': item.course,
            'kind': item.kind.label,
            'due': '${_fmtMonthDay(item.due)} ${_fmtClock(item.due)}',
            'left': _dayLabel(item.due),
          },
      ],
    };
  }

  static String _fmtMonthDay(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  static String _dayLabel(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    final diff = target.difference(today).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '明天';
    return _fmtMonthDay(due);
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmtDate(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  static String _fmtClock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final map = event.cast<String, dynamic>();
    if (map['type'] == 'message') {
      final data = map['data'];
      if (data is String) {
        messages = [data, ...messages].take(20).toList(growable: false);
        _notify();
      }
      return;
    }
    _apply(map);
  }

  void _apply(Map<String, dynamic> status) {
    final previousNode = nodeId;
    serviceConnected = status['serviceConnected'] as bool? ?? false;
    nodeId = status['nodeId'] as String?;
    nodeName = status['nodeName'] as String?;
    permissionGranted = status['permissionGranted'] as bool? ?? false;
    wearAppInstalled = status['wearAppInstalled'] as bool?;
    lastError = status['lastError'] as String?;
    lastMessageAt = (status['lastMessageAt'] as num?)?.toInt();
    lastPongAt = (status['lastPongAt'] as num?)?.toInt();
    lastReminderAt = (status['lastReminderAt'] as num?)?.toInt();
    lastReminder = status['lastReminder'] as String?;
    exactAlarms = status['exactAlarms'] as bool? ?? true;
    final list = status['messages'];
    if (list is List) {
      messages = list.whereType<String>().toList().reversed.toList(growable: false);
    }
    if (nodeId != null && nodeId != previousNode && !offlineCredEnabled) {
      // 开关已是关闭态但上次清除可能未送达（如当时手环离线），连上后补发一次；指令幂等。
      unawaited(clearOfflineCredential());
    }
    _notify();
  }

  void _setError(String? message) {
    lastError = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rescheduleDebounce?.cancel();
    _schedule?.removeListener(_onScheduleChanged);
    _assignments?.removeListener(_onScheduleChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
