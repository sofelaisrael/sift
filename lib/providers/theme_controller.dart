import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app theme mode. Loaded once in main() before runApp and
/// provided above MaterialApp via ChangeNotifierProvider.value.
class ThemeController extends ChangeNotifier {
  static const String _prefsKey = 'themeMode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// Loads the persisted theme mode, migrating the legacy `darkMode` bool
  /// (true -> 'dark', false -> 'light'), then deleting the legacy key.
  static Future<ThemeController> load() async {
    final controller = ThemeController();
    final prefs = await SharedPreferences.getInstance();

    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      controller._themeMode = _parseMode(stored);
    } else if (prefs.containsKey('darkMode')) {
      final legacyDark = prefs.getBool('darkMode') ?? false;
      controller._themeMode = legacyDark ? ThemeMode.dark : ThemeMode.light;
      await prefs.remove('darkMode');
      await prefs.setString(_prefsKey, _nameOf(controller._themeMode));
    }

    return controller;
  }

  static ThemeMode _parseMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _nameOf(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _nameOf(mode));
  }
}
