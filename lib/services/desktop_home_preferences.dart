import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DesktopHomeModule {
  todayCourses('今日课程'),
  deadlines('Deadlines'),
  campusCard('校园卡'),
  quickActions('快捷功能');

  const DesktopHomeModule(this.label);
  final String label;
}

class DesktopHomePreferences extends ChangeNotifier {
  DesktopHomePreferences(this._prefs);

  final SharedPreferences _prefs;

  bool isVisible(DesktopHomeModule module) =>
      _prefs.getBool('desktop_home_show_${module.name}') ?? true;

  bool get balanceOnly => _prefs.getBool('desktop_home_balance_only') ?? false;

  Future<void> setVisible(DesktopHomeModule module, bool visible) =>
      _write('desktop_home_show_${module.name}', visible);

  Future<void> setBalanceOnly(bool value) => _write('desktop_home_balance_only', value);

  Future<void> _write(String key, bool value) async {
    final write = _prefs.setBool(key, value);
    notifyListeners();
    await write;
  }
}
