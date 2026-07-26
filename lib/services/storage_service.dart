import 'dart:convert';
import 'dart:math';

// NOTE: import the OHOS package, not the upstream `flutter_secure_storage`.
// Despite the name, `flutter_secure_storage_ohos` is a hard fork (declares
// `library flutter_secure_storage;` and ships its own FlutterSecureStorage
// class with OhosOptions) — it is NOT a federated platform implementation.
// Importing the upstream facade falls through to UNSUPPORTED_PLATFORM on OHOS
// and crashes at boot. Keep this import as-is on the OHOS branch.
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assignment_overrides.dart';
import '../models/course_table.dart';
import '../models/oa_gym.dart';
import '../models/third_party_account.dart';
import '../models/user_session.dart';

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


  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  StorageService(this._prefs)
      : _secure = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  // Secure session storage
  Future<void> saveSession(UserSession session) async {
    await _secure.write(key: _sessionKey, value: jsonEncode(session.toJson()));
  }

  Future<UserSession?> loadSession() async {
    final raw = await _secure.read(key: _sessionKey);
    if (raw == null) return null;
    return UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clearSession() async {
    await _secure.delete(key: _sessionKey);
  }

  // Secure third-party account storage (one secure key per platform)
  static const _thirdPartyKeyPrefix = 'third_party_';
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
      // One-time migration: cpdaily was previously stored under the legacy
      // 'egate' key (platform id before the rename). If the new key is empty
      // but the legacy key has data, adopt it and delete the old key.
      if (p == ThirdPartyPlatform.cpdaily && acc == null) {
        const legacyKey = '${_thirdPartyKeyPrefix}egate';
        final raw = await _secure.read(key: legacyKey);
        if (raw != null) {
          try {
            acc = ThirdPartyAccount.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            );
            await _secure.write(key: _thirdPartyKey(p), value: raw);
            await _secure.delete(key: legacyKey);
          } catch (_) {
            // Corrupt legacy entry — leave it; clearThirdPartyAccount can
            // still remove it via the fromId alias path.
          }
        }
      }
      if (acc != null) result.add(acc);
    }
    return result;
  }

  Future<void> clearThirdPartyAccount(ThirdPartyPlatform p) async {
    await _secure.delete(key: _thirdPartyKey(p));
  }

  Future<void> clearAllThirdPartyAccounts() async {
    for (final p in ThirdPartyPlatform.values) {
      await _secure.delete(key: _thirdPartyKey(p));
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
    for (final id in const ['eams', 'elearning']) {
      await _secure.delete(key: '$_derivedCookieKeyPrefix$id');
    }
  }

  // SharedPreferences for non-sensitive data
  bool get debugMode => _prefs.getBool(_debugModeKey) ?? false;
  Future<void> setDebugMode(bool value) => _prefs.setBool(_debugModeKey, value);

  String get cachedSchoolName => _prefs.getString(_schoolNameKey) ?? '';
  Future<void> setCachedSchoolName(String name) =>
      _prefs.setString(_schoolNameKey, name);

  String get cachedPhone => _prefs.getString(_phoneKey) ?? '';
  Future<void> setCachedPhone(String phone) =>
      _prefs.setString(_phoneKey, phone);

  String get themeMode => _prefs.getString(_themeModeKey) ?? 'system';
  Future<void> setThemeMode(String mode) =>
      _prefs.setString(_themeModeKey, mode);

  String get colorScheme => _prefs.getString(_colorSchemeKey) ?? 'system';
  Future<void> setColorScheme(String scheme) =>
      _prefs.setString(_colorSchemeKey, scheme);

  bool get useLocalhost => _prefs.getBool(_useLocalhostKey) ?? false;
  Future<void> setUseLocalhost(bool value) =>
      _prefs.setBool(_useLocalhostKey, value);

  // Cloud-sync settings. The master-password-derived key is the one sensitive
  // piece — it lives in secure storage, never in SharedPreferences.
  bool get syncEnabled => _prefs.getBool(_syncEnabledKey) ?? false;
  Future<void> setSyncEnabled(bool value) =>
      _prefs.setBool(_syncEnabledKey, value);

  String? get syncLastAt => _prefs.getString(_syncLastAtKey);
  Future<void> setSyncLastAt(String iso) =>
      _prefs.setString(_syncLastAtKey, iso);

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

  // Schedule cache
  static const _semestersKey = 'schedule_semesters';
  static const _courseTablePrefix = 'schedule_course_table_';
  static const _termBeginPrefix = 'schedule_term_begin_';
  static const _selectedSemesterKey = 'schedule_selected_semester';

  Future<void> saveSemesters(SemesterInfo info) =>
      _prefs.setString(_semestersKey, jsonEncode(info.toJson()));

  SemesterInfo? loadSemesters() {
    final raw = _prefs.getString(_semestersKey);
    if (raw == null) return null;
    return SemesterInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveCourseTable(String semesterId, CourseTable table) => _prefs
      .setString('$_courseTablePrefix$semesterId', jsonEncode(table.toJson()));

  CourseTable? loadCourseTable(String semesterId) {
    final raw = _prefs.getString('$_courseTablePrefix$semesterId');
    if (raw == null) return null;
    return CourseTable.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveTermCalendar(String key, TermCalendar info) => _prefs
      .setString('$_termBeginPrefix$key', jsonEncode(info.toJson()));

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
  Future<void> setSelectedSemester(String id) =>
      _prefs.setString(_selectedSemesterKey, id);

  // Assignments cache (non-sensitive — stored as JSON in SharedPreferences)
  static const _assignmentsKey = 'cached_assignments';

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

  // Local user overrides on assignments (completion flips + hidden ids).
  static const _assignmentOverridesKey = 'assignment_overrides';

  Future<void> saveAssignmentOverrides(AssignmentOverrides ov) =>
      _prefs.setString(_assignmentOverridesKey, jsonEncode(ov.toJson()));

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

  Future<void> clearAssignmentOverrides() =>
      _prefs.remove(_assignmentOverridesKey);

  // OA gym booking profile. This is non-sensitive contact info used to submit
  // reservation forms and can be edited by the user.
  static const _oaBookingProfileKey = 'oa_booking_profile';

  Future<void> saveOaBookingProfile(OaBookingProfile profile) =>
      _prefs.setString(_oaBookingProfileKey, jsonEncode(profile.toJson()));

  OaBookingProfile loadOaBookingProfile() {
    final raw = _prefs.getString(_oaBookingProfileKey);
    if (raw == null) {
      return const OaBookingProfile(name: '', phone: '', email: '');
    }
    try {
      return OaBookingProfile.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const OaBookingProfile(name: '', phone: '', email: '');
    }
  }
}
