import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  final String _key = "themeMode";

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    loadTheme();
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_key) ?? ThemeMode.light.index;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == ThemeMode.system) {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = mode;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, _themeMode.index);
    notifyListeners();
  }
}
