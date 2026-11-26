import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
// NOTE: import the OHOS package, not the upstream `flutter_secure_storage`.
// Despite the name, `flutter_secure_storage_ohos` is a hard fork (declares
// `library flutter_secure_storage;` and ships its own FlutterSecureStorage
// class with OhosOptions) — it is NOT a federated platform implementation.
// Importing the upstream facade falls through to UNSUPPORTED_PLATFORM on OHOS
// and crashes at boot. Keep this import as-is on the OHOS branch.
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment.dart';
import '../models/assignment_overrides.dart';
import '../models/campus_identity.dart';
import '../models/course_table.dart';
import '../models/custom_course.dart';
import '../models/graduate_schedule.dart';
import '../models/ids_passkey.dart';
import '../models/oa_gym.dart';
import '../models/quick_shortcuts.dart';
import '../models/renew_status.dart';
import '../models/third_party_account.dart';
import '../models/user_session.dart';
import '../utils/secure_storage.dart';
import 'sync_envelope.dart';

class StorageService {
  static const _sessionKey = 'user_session';
  static const _debugModeKey = 'debug_mode';
  static const _schoolNameKey = 'cached_school_name';
  static const _phoneKey = 'cached_phone';
  static const _themeModeKey = 'theme_mode';
  static const _colorSchemeKey = 'color_scheme';
  static const _useLocalhostKey = 'use_localhost';
  static const _syncEnabledKey = 'sync_enabled';
  static const _syncLastAtKey = 'sync_last_at';
  static const _syncMasterKeyKey = 'sync_master_key'; // secure storage
  static const _deviceIdKey = 'device_id';
  static const _hideCampusCardBalanceKey = 'hide_campus_card_balance';
  static const _desktopSidebarCollapsedKey = 'desktop_sidebar_collapsed';
  static const _scheduleViewModeKey = 'schedule_view_mode';
  static const _scheduleShowSaturdayKey = 'schedule_show_saturday';
  static const _scheduleShowSundayKey = 'schedule_show_sunday';
  static const _scheduleShowGhostCoursesKey = 'schedule_show_ghost_courses';
  static const _deadlinesShowAssignmentsKey = 'deadlines_show_assignments';
  static const _deadlinesShowExamsKey = 'deadlines_show_exams';
  static const _proxyUrlKey = 'app_proxy_url';
  static const _proxyEnabledKey = 'app_proxy_enabled';

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  StorageService(this._prefs) : _secure = appSecureStorage;

  String? get campusWebOwner => _prefs.getString('campus_web_owner');
  Future<void> setCampusWebOwner(String owner) => _prefs.setString('campus_web_owner', owner);

  // 背屏 / 折叠外屏的精简界面设置。
  bool get glanceEnabled => _prefs.getBool('glance_enabled') ?? true;
  Future<void> setGlanceEnabled(bool value) =>
      _prefs.setBool('glance_enabled', value);

  bool get glanceShowCourses =>
      _prefs.getBool('glance_show_courses') ?? true;
  Future<void> setGlanceShowCourses(bool value) =>
      _prefs.setBool('glance_show_courses', value);

  bool get glanceShowAssignments =>
      _prefs.getBool('glance_show_assignments') ?? true;
  Future<void> setGlanceShowAssignments(bool value) =>
      _prefs.setBool('glance_show_assignments', value);

  bool get glanceShowPayment =>
      _prefs.getBool('glance_show_payment') ?? true;
  Future<void> setGlanceShowPayment(bool value) =>
      _prefs.setBool('glance_show_payment', value);

  List<String>? get pinnedQuickFeatureIds => _prefs.getStringList('pinned_quick_features');
  Future<void> setPinnedQuickFeatureIds(List<String> ids) =>
      _prefs.setStringList('pinned_quick_features', pinnedShortcutIds(ids));

  String _studyPlanKey(bool full) =>
      '${_campusCachePrefix}study_plan_${full ? 'catalog' : 'progress'}';

  Map<String, dynamic>? studyPlanCache(bool full) {
    final value = _prefs.getString(_studyPlanKey(full));
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    unawaited(clearStudyPlanCache(full));
    return null;
  }

  Future<void> saveStudyPlanCache(bool full, Map<String, dynamic> entry) =>
      _prefs.setString(_studyPlanKey(full), jsonEncode(entry));
  Future<void> clearStudyPlanCache(bool full) => _prefs.remove(_studyPlanKey(full));

  bool get islandEnabled => _prefs.getBool('island_enabled') ?? false;
  Future<void> setIslandEnabled(bool value) => _prefs.setBool('island_enabled', value);

  // Secure session storage
  Future<void> saveSession(UserSession session) async {
    await _secure.write(key: _sessionKey, value: jsonEncode(session.toJson()));
  }

  Future<UserSession?> loadSession() async {
    final raw = await _secure.read(key: _sessionKey);
    if (raw == null) return null;
    return UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static const _emapCachePrefix = 'emap_cache_';
  static const _campusCachePrefix = 'campus_cache_';

  String? readEmapCache(String feature) => _prefs.getString('$_emapCachePrefix$feature');

  Future<void> writeEmapCache(String feature, String? value) => value == null
      ? _prefs.remove('$_emapCachePrefix$feature')
      : _prefs.setString('$_emapCachePrefix$feature', value);

  Future<void> clearCampusCaches() async {
    final keys = _prefs
        .getKeys()
        .where(
          (k) => k.startsWith(_emapCachePrefix) || k.startsWith(_campusCachePrefix),
        )
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  Future<void> clearSession() async {
    await _secure.delete(key: _sessionKey);
    await clearCampusCaches();
  }

  Future<void> saveIdsCandidate(String account, IdsPasskey credential) =>
      _secure.write(key: 'third_party_ids_pending', value: jsonEncode({'account': account, 'credential': credential.toJson()}));

  Future<({String account, IdsPasskey credential})?> loadIdsCandidate() async {
    final value = await _secure.read(key: 'third_party_ids_pending');
    if (value == null) return null;
    final json = jsonDecode(value) as Map<String, dynamic>;
    return (account: json['account'] as String, credential: IdsPasskey.fromJson((json['credential'] as Map).cast<String, dynamic>()));
  }

  Future<void> clearIdsCandidate() => _secure.delete(key: 'third_party_ids_pending');
  String? get idsBackedUpId => _prefs.getString('third_party_ids_backed_up_id');
  Future<void> markIdsBackedUp(String id) => _prefs.setString('third_party_ids_backed_up_id', id);

  List<SyncTombstone> loadThirdPartyTombstones() =>
      (jsonDecode(_prefs.getString('third_party_tombstones') ?? '[]') as List)
          .map((entry) => SyncTombstone.fromJson((entry as Map).cast<String, dynamic>())).toList();
  Future<void> saveThirdPartyTombstones(List<SyncTombstone> tombstones) =>
      _prefs.setString('third_party_tombstones', jsonEncode(tombstones.map((t) => t.toJson()).toList()));

  // Secure third-party account storage (one secure key per platform)
  static const _thirdPartyKeyPrefix = 'third_party_';
  static const _legacyCampusKeys = [
    '${_thirdPartyKeyPrefix}cpdaily',
    '${_thirdPartyKeyPrefix}egate',
  ];
  String _thirdPartyKey(ThirdPartyPlatform p) => '$_thirdPartyKeyPrefix${p.id}';

  Future<void> saveThirdPartyAccount(ThirdPartyAccount acc) async {
    await _secure.write(
      key: _thirdPartyKey(acc.platform),
      value: jsonEncode(acc.toJson()),
    );
  }

  Future<ThirdPartyAccount?> loadThirdPartyAccount(ThirdPartyPlatform p) async {
    final raw = await _secure.read(key: _thirdPartyKey(p));
    if (raw == null) return null;
    try {
      return ThirdPartyAccount.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ThirdPartyAccount>> loadAllThirdPartyAccounts() async {
    final result = <ThirdPartyAccount>[];
    for (final p in ThirdPartyPlatform.values) {
      var acc = await loadThirdPartyAccount(p);
      // Read published campus accounts under their old keys. All writes use ids.
      if (p == ThirdPartyPlatform.ids && acc == null) {
        for (final legacyKey in _legacyCampusKeys) {
          final raw = await _secure.read(key: legacyKey);
          if (raw == null) continue;
          try {
            acc = ThirdPartyAccount.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            );
          } catch (_) {
            continue;
          }
          await saveThirdPartyAccount(acc);
          await _secure.delete(key: legacyKey);
          break;
        }
      }
      if (acc != null) result.add(acc);
    }
    return result;
  }

  Future<void> clearThirdPartyAccount(ThirdPartyPlatform p) async {
    await _secure.delete(key: _thirdPartyKey(p));
    if (p == ThirdPartyPlatform.ids) {
      for (final key in _legacyCampusKeys) {
        await _secure.delete(key: key);
      }
      await clearCampusCaches();
    }
  }

  Future<void> clearAllThirdPartyAccounts() async {
    for (final p in ThirdPartyPlatform.values) {
      await clearThirdPartyAccount(p);
    }
  }

  // Derived downstream cookies
  // CASTGC, persisted so cold start skips the SSO bounce. Keyed by node id.
  static const _derivedCookieKeyPrefix = 'derived_cookie_';

  Future<void> saveDerivedCookie(String nodeId, String cookie) async {
    await _secure.write(
      key: '$_derivedCookieKeyPrefix$nodeId',
      value: cookie,
    );
  }

  Future<String?> loadDerivedCookie(String nodeId) async {
    return _secure.read(key: '$_derivedCookieKeyPrefix$nodeId');
  }

  Future<void> clearDerivedCookie(String nodeId) async {
    await _secure.delete(key: '$_derivedCookieKeyPrefix$nodeId');
  }

  Future<void> clearAllDerivedCookies() async {
    for (final id in const ['eams', 'elearning', 'egateApp', 'oa']) {
      await _secure.delete(key: '$_derivedCookieKeyPrefix$id');
    }
  }

  // Renew status (last attempt outcome per session-node id: ids,
  // gradescope, hydro, eams, elearning). Local-only UI signal, never synced.
  static const _renewStatusKeyPrefix = 'renew_status_';

  Future<void> saveRenewStatus(String nodeId, RenewStatus status) => _prefs.setString(
        '$_renewStatusKeyPrefix$nodeId',
        jsonEncode(status.toJson()),
      );

  RenewStatus? loadRenewStatus(String nodeId) {
    final raw = _prefs.getString('$_renewStatusKeyPrefix$nodeId');
    if (raw == null) return null;
    try {
      return RenewStatus.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Session-node renewal schedule. Local-only runtime state; never synced.
  static const _nextRenewKeyPrefix = 'next_renew_';

  Future<void> saveNextRenewTimestamp(
    String nodeId,
    DateTime? timestamp,
  ) async {
    final key = '$_nextRenewKeyPrefix$nodeId';
    if (timestamp == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, timestamp.toIso8601String());
    }
  }

  DateTime? loadNextRenewTimestamp(String nodeId) {
    final raw = _prefs.getString('$_nextRenewKeyPrefix$nodeId');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Notifications are opt-in and never change the upstream release defaults.
  bool get spendingAlertsEnabled => _prefs.getBool('spending_alerts_enabled') ?? false;
  Future<void> setSpendingAlertsEnabled(bool value) => _prefs.setBool('spending_alerts_enabled', value);
  Future<void> reloadNotificationPreferences() => _prefs.reload();

  // SharedPreferences for non-sensitive data
  bool get debugMode =>
      !kReleaseMode && (_prefs.getBool(_debugModeKey) ?? false);
  Future<void> setDebugMode(bool value) => _prefs.setBool(_debugModeKey, value);

  bool get debugForceIdsRebindBanner =>
      !kReleaseMode && (_prefs.getBool('debug_force_ids_rebind_banner') ?? false);
  Future<void> setDebugForceIdsRebindBanner(bool value) =>
      _prefs.setBool('debug_force_ids_rebind_banner', value);

  String get cachedSchoolName => _prefs.getString(_schoolNameKey) ?? '';
  Future<void> setCachedSchoolName(String name) => _prefs.setString(_schoolNameKey, name);

  String get cachedPhone => _prefs.getString(_phoneKey) ?? '';
  Future<void> setCachedPhone(String phone) => _prefs.setString(_phoneKey, phone);

  String get themeMode => _prefs.getString(_themeModeKey) ?? 'system';
  Future<void> setThemeMode(String mode) => _prefs.setString(_themeModeKey, mode);

  static const _colorSchemeDefaultMigratedV1Key =
      'color_scheme_default_techred_v1';

  String get colorScheme => _prefs.getString(_colorSchemeKey) ?? 'techRed';
  Future<void> setColorScheme(String scheme) => _prefs.setString(_colorSchemeKey, scheme);

  /// Migrates legacy installs that stored the pre-v1.1 `'system'` default
  /// accent to `'techRed'` once, while preserving future user selections.
  Future<void> migrateLegacyDefaultColorScheme() async {
    if (_prefs.getBool(_colorSchemeDefaultMigratedV1Key) ?? false) return;
    if (_prefs.getString(_colorSchemeKey) == 'system') {
      await _prefs.setString(_colorSchemeKey, 'techRed');
    }
    await _prefs.setBool(_colorSchemeDefaultMigratedV1Key, true);
  }

  bool get hideCampusCardBalance =>
      _prefs.getBool(_hideCampusCardBalanceKey) ?? false;
  Future<void> setHideCampusCardBalance(bool value) =>
      _prefs.setBool(_hideCampusCardBalanceKey, value);

  bool get desktopSidebarCollapsed =>
      _prefs.getBool(_desktopSidebarCollapsedKey) ?? false;
  Future<void> setDesktopSidebarCollapsed(bool value) =>
      _prefs.setBool(_desktopSidebarCollapsedKey, value);

  String get scheduleViewMode =>
      _prefs.getString(_scheduleViewModeKey) ?? 'week';
  Future<void> setScheduleViewMode(String mode) =>
      _prefs.setString(_scheduleViewModeKey, mode);

  /// `null` means the user has never overridden Saturday visibility, so
  /// SchedulePage shows Saturday only when the active semester has Saturday
  /// classes or exams.
  bool? get scheduleShowSaturday => _prefs.getBool(_scheduleShowSaturdayKey);
  Future<void> setScheduleShowSaturday(bool value) =>
      _prefs.setBool(_scheduleShowSaturdayKey, value);

  /// `null` means the user has never overridden Sunday visibility.
  bool? get scheduleShowSunday => _prefs.getBool(_scheduleShowSundayKey);
  Future<void> setScheduleShowSunday(bool value) =>
      _prefs.setBool(_scheduleShowSundayKey, value);

  bool get scheduleShowGhostCourses =>
      _prefs.getBool(_scheduleShowGhostCoursesKey) ?? false;
  Future<void> setScheduleShowGhostCourses(bool value) =>
      _prefs.setBool(_scheduleShowGhostCoursesKey, value);

  bool get deadlinesShowAssignments =>
      _prefs.getBool(_deadlinesShowAssignmentsKey) ?? true;
  Future<void> setDeadlinesShowAssignments(bool value) =>
      _prefs.setBool(_deadlinesShowAssignmentsKey, value);

  bool get deadlinesShowExams =>
      _prefs.getBool(_deadlinesShowExamsKey) ?? true;
  Future<void> setDeadlinesShowExams(bool value) =>
      _prefs.setBool(_deadlinesShowExamsKey, value);

  String get appProxyUrl => _prefs.getString(_proxyUrlKey) ?? '';
  Future<void> setAppProxyUrl(String value) => _prefs.setString(_proxyUrlKey, value);
  bool get appProxyEnabled => _prefs.getBool(_proxyEnabledKey) ?? false;
  Future<void> setAppProxyEnabled(bool value) => _prefs.setBool(_proxyEnabledKey, value);

  // Whether this device has been shown the privacy policy and agreed to it. A
  // store requires the answer before the app does anything on the user's behalf,
  // so it is read on the very first frame (see PrivacyGate) and checked again at
  // every sign-in entry.
  static const _privacyAcceptedKey = 'privacy_accepted_v1';
  bool get privacyAccepted => _prefs.getBool(_privacyAcceptedKey) ?? false;
  Future<void> setPrivacyAccepted(bool value) =>
      _prefs.setBool(_privacyAcceptedKey, value);

  bool get useLocalhost =>
      !kReleaseMode && (_prefs.getBool(_useLocalhostKey) ?? false);
  Future<void> setUseLocalhost(bool value) =>
      _prefs.setBool(_useLocalhostKey, value);

  // Cloud-sync settings. The master-password-derived key is the one sensitive
  // piece — it lives in secure storage, never in SharedPreferences.
  bool get syncEnabled => _prefs.getBool(_syncEnabledKey) ?? false;
  Future<void> setSyncEnabled(bool value) => _prefs.setBool(_syncEnabledKey, value);

  String? get syncLastAt => _prefs.getString(_syncLastAtKey);
  Future<void> setSyncLastAt(String iso) => _prefs.setString(_syncLastAtKey, iso);

  Future<String?> loadSyncMasterKey() => _secure.read(key: _syncMasterKeyKey);
  Future<void> saveSyncMasterKey(String serialized) =>
      _secure.write(key: _syncMasterKeyKey, value: serialized);
  Future<void> clearSyncMasterKey() => _secure.delete(key: _syncMasterKeyKey);

  // Stable per-device identifier used as the cloud-sync LWW tie-breaker.
  // Generated lazily on first access (16 random bytes → 32 hex chars) and
  // persisted in SharedPreferences; never leaves the device except inside
  // encrypted sync blobs.
  Future<String> ensureDeviceId() async {
    var id = _prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      id = List<int>.generate(16, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await _prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  String _academicCertificateKey(String owner, String kind) =>
      '${_campusCachePrefix}certificate_${jsonEncode([owner, kind])}';

  String? academicCertificateCache(String owner, String kind) =>
      _prefs.getString(_academicCertificateKey(owner, kind));

  Future<void> saveAcademicCertificateCache(String owner, String kind, String value) =>
      _prefs.setString(_academicCertificateKey(owner, kind), value);

  Future<void> clearAcademicCertificateCache(String owner) async {
    final prefix = '${_campusCachePrefix}certificate_[${jsonEncode(owner)},';
    await Future.wait(_prefs.getKeys().where((k) => k.startsWith(prefix)).map(_prefs.remove));
  }

  String _pnpMinorKey(String owner) => '${_campusCachePrefix}pnp_minor_history_$owner';

  String? pnpMinorHistory(String owner) => _prefs.getString(_pnpMinorKey(owner));
  Future<void> savePnpMinorHistory(String owner, String value) =>
      _prefs.setString(_pnpMinorKey(owner), value);
  Future<void> clearPnpMinorHistory(String owner) => _prefs.remove(_pnpMinorKey(owner));

  List<String> catalogHistory(String owner) =>
      _prefs.getStringList('${_campusCachePrefix}catalog_history_$owner') ?? [];
  Future<void> saveCatalogHistory(String owner, List<String> terms) =>
      _prefs.setStringList('${_campusCachePrefix}catalog_history_$owner', terms);
  Future<void> clearCatalogHistory(String owner) =>
      _prefs.remove('${_campusCachePrefix}catalog_history_$owner');

  String _gradeKey(String owner, String scope) =>
      '${_campusCachePrefix}grades_${jsonEncode([owner, scope])}';

  String? loadGradeCache(String owner, String scope) => _prefs.getString(_gradeKey(owner, scope));

  Future<void> saveGradeCache(String owner, String scope, String data) =>
      _prefs.setString(_gradeKey(owner, scope), data);

  Future<void> clearGradeCache(String owner) async {
    final prefix = '${_campusCachePrefix}grades_[${jsonEncode(owner)},';
    await Future.wait(_prefs.getKeys().where((key) => key.startsWith(prefix)).map(_prefs.remove));
  }

  // Schedule cache
  static const _semestersKey = 'schedule_semesters';
  static const _courseTablePrefix = 'schedule_course_table_';
  static const _termBeginPrefix = 'schedule_term_begin_';
  static const _selectedSemesterKey = 'schedule_selected_semester';
  static const _scheduleSourceKey = 'schedule_source_preference';

  String _shortNameKey(String? owner, String course) =>
      'schedule_short_name_${jsonEncode([owner, course])}';

  String? courseShortName(String? owner, String course) =>
      _prefs.getString(_shortNameKey(owner, course));

  Future<void> setCourseShortName(String? owner, String course, String? name) async {
    final key = _shortNameKey(owner, course);
    final saved = name == null ? await _prefs.remove(key) : await _prefs.setString(key, name);
    if (!saved) throw StateError('保存课表简称失败');
  }

  CampusIdentity? loadCampusIdentity(String owner) {
    final raw = _prefs.getString('schedule_campus_identity');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data['owner'] == owner ? CampusIdentity.fromJson(data) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCampusIdentity(String owner, CampusIdentity identity) => _prefs.setString(
        'schedule_campus_identity',
        jsonEncode({'owner': owner, ...identity.toJson()}),
      );

  Future<void> clearCampusIdentity() => _prefs.remove('schedule_campus_identity');

  CampusScheduleSource scheduleSourceFor(String? owner) {
    if (owner == null) return CampusScheduleSource.automatic;
    final sources = CampusScheduleSource.values.asNameMap();
    final source = _prefs.getString('${_scheduleSourceKey}_$owner');
    if (source != null) return sources[source] ?? CampusScheduleSource.automatic;

    // Older installations saved one preference together with its owner.
    final raw = _prefs.getString(_scheduleSourceKey);
    if (raw == null) return CampusScheduleSource.automatic;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['owner'] == owner) {
        return sources[data['source']] ?? CampusScheduleSource.automatic;
      }
    } catch (_) {
      return CampusScheduleSource.automatic;
    }
    return CampusScheduleSource.automatic;
  }

  Future<void> setScheduleSource(String owner, CampusScheduleSource source) =>
      _prefs.setString('${_scheduleSourceKey}_$owner', source.name);

  String? get graduateScheduleOwner {
    final current = _prefs.getString('graduate_schedule_v2');
    final raw = current ?? _prefs.getString('graduate_schedule');
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return current == null ? _prefs.getString('graduate_schedule_owner') : data['owner'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? graduateSchemeFor(String semesterId) => _prefs.getString('graduate_scheme_$semesterId');

  Future<void> setGraduateScheme(String semesterId, String scheme) =>
      _prefs.setString('graduate_scheme_$semesterId', scheme);

  GraduateSchedule? loadGraduateSchedule() {
    final raw = _prefs.getString('graduate_schedule_v2') ?? _prefs.getString('graduate_schedule');
    if (raw == null) return null;
    try {
      return GraduateSchedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveGraduateSchedule(String owner, GraduateSchedule schedule) =>
      // Keep the owner and response in one preference write.
      _prefs.setString('graduate_schedule_v2', jsonEncode({...schedule.toJson(), 'owner': owner}));

  Future<void> clearGraduateScheduleCache() async {
    final keys = _prefs.getKeys().where(
      (key) =>
        key == 'graduate_schedule' ||
        key == 'graduate_schedule_v2' ||
        key == 'graduate_schedule_owner' ||
        key.startsWith('$_courseTablePrefix$graduateSemesterPrefix') ||
        key.startsWith('$_termBeginPrefix$graduateSemesterPrefix') ||
        key.startsWith('graduate_scheme_'),
    ).toList();
    if (loadSemesters()?.info.tableId == graduateTableId) keys.add(_semestersKey);
    if (selectedSemester?.startsWith(graduateSemesterPrefix) == true) {
      keys.add(_selectedSemesterKey);
    }
    await Future.wait(keys.map(_prefs.remove));
  }

  Future<void> saveSemesters(SemesterInfo info, {String? owner}) =>
      _prefs.setString(_semestersKey, jsonEncode({...info.toJson(), 'owner': owner}));

  ({SemesterInfo info, String? owner})? loadSemesters() {
    final raw = _prefs.getString(_semestersKey);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (info: SemesterInfo.fromJson(json), owner: json['owner'] as String?);
  }

  Future<void> saveCourseTable(String semesterId, CourseTable table, {String? owner}) =>
      _prefs.setString(
        '$_courseTablePrefix$semesterId',
        jsonEncode({...table.toJson(), if (owner != null) 'owner': owner}),
      );

  Future<void> adoptLegacyCourseTable(String semesterId, String? owner, String watchOwner) async {
    final key = '$_courseTablePrefix$semesterId';
    final raw = _prefs.getString(key);
    if (raw == null || semesterId.startsWith(graduateSemesterPrefix)) return;
    final row = jsonDecode(raw) as Map<String, dynamic>;
    if (row['owner'] != null || row['watchOwner'] != null) return;
    if (owner == null) {
      row['watchOwner'] = watchOwner;
    } else {
      row['owner'] = owner;
    }
    await _prefs.setString(key, jsonEncode(row));
  }

  CourseTable? loadCourseTable(String semesterId, {String? owner, String? watchOwner}) {
    final raw = _prefs.getString('$_courseTablePrefix$semesterId');
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (semesterId.startsWith(graduateSemesterPrefix) && (owner == null || json['owner'] != owner)) {
      return null;
    }
    if (watchOwner != null) {
      // Older watch builds stored a manual adoption in the owner field.
      final savedOwner = json['owner'] ?? json['watchOwner'];
      if (savedOwner != (owner ?? watchOwner)) return null;
    } else if (json['owner'] != null && json['owner'] != owner) {
      return null;
    }
    return CourseTable.fromJson(json);
  }

  Future<void> saveTermCalendar(String key, TermCalendar info) =>
      _prefs.setString('$_termBeginPrefix$key', jsonEncode(info.toJson()));

  TermCalendar? loadTermCalendar(String key) {
    final raw = _prefs.getString('$_termBeginPrefix$key');
    if (raw == null) return null;
    try {
      return TermCalendar.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String? get selectedSemester => _prefs.getString(_selectedSemesterKey);
  Future<void> setSelectedSemester(String id) => _prefs.setString(_selectedSemesterKey, id);

  static const _customCoursesPrefix = 'schedule_custom_courses_';

  String? _customCoursesKey(String semesterId, String? owner) {
    if (!semesterId.startsWith(graduateSemesterPrefix)) {
      return '$_customCoursesPrefix$semesterId';
    }
    // Older graduate entries have no owner and cannot be assigned safely.
    return owner == null ? null : '$_customCoursesPrefix${semesterId}_$owner';
  }

  Future<void> saveCustomCourses(
    String semesterId,
    List<CustomCourse> courses, {
    String? owner,
  }) async {
    final key = _customCoursesKey(semesterId, owner);
    if (key == null) return;
    await _prefs.setString(key, jsonEncode(courses.map((course) => course.toJson()).toList()));
  }

  List<CustomCourse> loadCustomCourses(String semesterId, {String? owner}) {
    final key = _customCoursesKey(semesterId, owner);
    final raw = key == null ? null : _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final courses = <CustomCourse>[];
      for (final item in decoded) {
        try {
          if (item is! Map) continue;
          courses.add(CustomCourse.fromJson(item.cast<String, dynamic>()));
        } catch (error) {
          debugPrint('Skipping invalid custom course: ${error.runtimeType}');
        }
      }
      return courses;
    } catch (error) {
      debugPrint('Failed to read custom courses: ${error.runtimeType}');
      return const [];
    }
  }

  static const _blackboardIndexKey = '${_campusCachePrefix}blackboard_index';

  Map<String, dynamic>? get blackboardIndex {
    final value = _prefs.getString(_blackboardIndexKey);
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> saveBlackboardIndex(Map<String, dynamic> index) =>
      _prefs.setString(_blackboardIndexKey, jsonEncode(index));
  Future<void> clearBlackboardIndex() => _prefs.remove(_blackboardIndexKey);

  // Assignments cache (non-sensitive — stored as JSON in SharedPreferences)
  static const _assignmentsKey = 'cached_assignments';

  bool get hasCachedAssignments => _prefs.containsKey(_assignmentsKey);

  bool get deadlineWidgetsEnabled => _prefs.getBool('deadline_widgets_enabled') ?? false;

  Future<void> setDeadlineWidgetsEnabled(bool enabled) async {
    await _prefs.setBool('deadline_widgets_enabled', enabled);
  }

  Future<void> saveCachedAssignments(List<Map<String, dynamic>> items) =>
      _prefs.setString(_assignmentsKey, jsonEncode(items));

  List<Map<String, dynamic>> loadCachedAssignments() {
    final raw = _prefs.getString(_assignmentsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearCachedAssignments() => _prefs.remove(_assignmentsKey);

  static String _customDeadlinesKey(String? owner) => owner == null
      ? 'custom_deadlines_guest'
      : 'custom_deadlines_account_${Uri.encodeComponent(owner)}';

  Future<void> saveCustomDeadlines(
    String? owner,
    Iterable<CustomDeadline> deadlines,
    Map<String, DeadlineReminderChange> reminderChanges,
  ) async {
    final items = deadlines.map((deadline) => deadline.toJson()).toList();
    final saved = await _prefs.setString(
      _customDeadlinesKey(owner),
      jsonEncode(
        reminderChanges.isEmpty
            ? items
            : {
                'deadlines': items,
                'reminderChanges': reminderChanges.map((key, change) => MapEntry(key, change.name)),
              },
      ),
    );
    if (!saved) throw StateError('Could not save custom deadlines');
  }

  ({
    Map<String, CustomDeadline> deadlines,
    Map<String, DeadlineReminderChange> reminderChanges,
  })? loadCustomDeadlines(String? owner) {
    final raw = _prefs.getString(_customDeadlinesKey(owner));
    if (raw == null) return null;
    final deadlines = <String, CustomDeadline>{};
    var reminderChanges = <String, DeadlineReminderChange>{};
    try {
      final decoded = jsonDecode(raw);
      final items = (decoded is Map ? decoded['deadlines'] : decoded) as List<dynamic>;
      if (decoded is Map) {
        reminderChanges = DeadlineReminderChange.decode(decoded['reminderChanges']);
      }
      for (final item in items.whereType<Map<String, dynamic>>()) {
        try {
          final deadline = CustomDeadline.fromJson(item);
          deadlines[deadline.id] = deadline;
        } catch (_) {
          debugPrint('Skipping invalid custom deadline');
        }
      }
    } catch (_) {
      debugPrint('Could not read custom deadlines');
    }
    return (deadlines: deadlines, reminderChanges: reminderChanges);
  }

  // Local user overrides on assignments (completion flips + hidden ids).
  static const _assignmentOverridesKey = 'assignment_overrides';

  Future<void> saveAssignmentOverrides(AssignmentOverrides ov) async {
    if (!await _prefs.setString(_assignmentOverridesKey, jsonEncode(ov.toJson()))) {
      throw StateError('Could not save assignment overrides');
    }
  }

  AssignmentOverrides loadAssignmentOverrides() {
    final raw = _prefs.getString(_assignmentOverridesKey);
    if (raw == null) return AssignmentOverrides();
    try {
      return AssignmentOverrides.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return AssignmentOverrides();
    }
  }

  Future<void> clearAssignmentOverrides() => _prefs.remove(_assignmentOverridesKey);

  // Local reservation contact details, scoped to the primary and eGate
  // accounts. Keep the old unscoped record, but do not assign it to a new user.
  static const _oaBookingProfileKey = 'oa_booking_profile';

  String _bookingProfileKey(String? owner) => owner == null
      ? _oaBookingProfileKey
      : '${_oaBookingProfileKey}_v2_${Uri.encodeComponent(owner)}';

  Future<void> saveOaBookingProfile(
    OaBookingProfile profile, {
    String? owner,
    OaBookingProfile? schoolProfile,
  }) {
    final data = profile.toJson();
    final school =
        schoolProfile?.toJson() ?? _bookingProfileRecord(owner)['school'];
    if (school is Map) data['school'] = school;
    return _prefs.setString(_bookingProfileKey(owner), jsonEncode(data));
  }

  Map<String, dynamic> _bookingProfileRecord(String? owner) {
    final raw = _prefs.getString(_bookingProfileKey(owner));
    if (raw == null) return const {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  OaBookingProfile loadOaBookingProfile({String? owner}) =>
      _parseBookingProfile(_bookingProfileRecord(owner));

  OaBookingProfile loadOaSchoolProfile({required String owner}) =>
      _parseBookingProfile(_bookingProfileRecord(owner)['school']);

  OaBookingProfile _parseBookingProfile(Object? value) {
    try {
      return OaBookingProfile.fromJson(
        (value as Map?)?.cast<String, dynamic>() ?? const {},
      );
    } catch (_) {
      return const OaBookingProfile(name: '', phone: '', email: '');
    }
  }
}
