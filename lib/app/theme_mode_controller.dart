import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.light) {
    _load();
  }

  static const _prefsKey = 'mindnest_theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    switch (stored) {
      case 'dark':
        state = ThemeMode.dark;
        return;
      case 'light':
      default:
        state = ThemeMode.light;
        return;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) {
      return;
    }
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final value = mode == ThemeMode.dark ? 'dark' : 'light';
    await prefs.setString(_prefsKey, value);
  }
}

final themeModeControllerProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
      (ref) => ThemeModeController(),
    );
