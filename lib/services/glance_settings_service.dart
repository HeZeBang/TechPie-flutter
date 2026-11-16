import 'package:flutter/foundation.dart';

import 'storage_service.dart';

enum GlanceSection { courses, assignments, payment }

/// User preferences for the rear-screen / cover-screen glance.
class GlanceSettings extends ChangeNotifier {
  GlanceSettings(this._storage)
      : _enabled = _storage.glanceEnabled,
        _courses = _storage.glanceShowCourses,
        _assignments = _storage.glanceShowAssignments,
        _payment = _storage.glanceShowPayment;

  final StorageService _storage;

  bool _enabled;
  bool _courses;
  bool _assignments;
  bool _payment;

  bool get enabled => _enabled;

  bool isEnabled(GlanceSection section) => switch (section) {
        GlanceSection.courses => _courses,
        GlanceSection.assignments => _assignments,
        GlanceSection.payment => _payment,
      };

  List<GlanceSection> get sections => [
        if (_courses) GlanceSection.courses,
        if (_assignments) GlanceSection.assignments,
        if (_payment) GlanceSection.payment,
      ];

  bool get hasSections => _courses || _assignments || _payment;

  /// The last enabled section cannot be turned off: the glance would otherwise
  /// be an empty surface with no way back.
  bool canDisable(GlanceSection section) =>
      !isEnabled(section) || sections.length > 1;

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    await _storage.setGlanceEnabled(value);
  }

  Future<void> setSection(GlanceSection section, bool value) async {
    if (isEnabled(section) == value) return;
    if (!value && !canDisable(section)) return;
    if (section == GlanceSection.courses) {
      _courses = value;
      await _storage.setGlanceShowCourses(value);
    } else if (section == GlanceSection.assignments) {
      _assignments = value;
      await _storage.setGlanceShowAssignments(value);
    } else {
      _payment = value;
      await _storage.setGlanceShowPayment(value);
    }
    notifyListeners();
  }
}
