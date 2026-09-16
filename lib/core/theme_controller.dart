import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's light/dark appearance preference.
class ThemeController extends ChangeNotifier {
  static const _preferenceKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  int _revision = 0;
  bool _disposed = false;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final revision = _revision;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || revision != _revision) return;
    final value = prefs.getString(_preferenceKey);
    _mode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_disposed) return;
    if (_mode == mode) return;
    _mode = mode;
    final revision = ++_revision;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_disposed || revision != _revision) return;
    await prefs.setString(_preferenceKey, mode.name);
  }

  Future<void> cycle() async {
    final next = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String get label => switch (_mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '日间模式',
    ThemeMode.dark => '夜间模式',
  };

  IconData get icon => switch (_mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };
}
