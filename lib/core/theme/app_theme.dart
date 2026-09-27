import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:offline_pdf_reader/core/theme/editorial_tokens.dart';

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: EditorialTokens.canvas,
    fontFamily: EditorialTokens.sansFamily,
    colorScheme: const ColorScheme.light(
      primary: EditorialTokens.primary,
      onPrimary: Colors.white,
      secondary: EditorialTokens.secondary,
      onSecondary: Colors.white,
      tertiary: EditorialTokens.tertiary,
      onTertiary: Colors.white,
      surface: EditorialTokens.surface,
      onSurface: EditorialTokens.ink,
      surfaceContainerLowest: EditorialTokens.surfaceStrong,
      surfaceContainerLow: EditorialTokens.surface,
      surfaceContainer: EditorialTokens.surfaceMuted,
      surfaceContainerHigh: EditorialTokens.canvas,
      outline: EditorialTokens.border,
      outlineVariant: EditorialTokens.borderSoft,
      error: EditorialTokens.error,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: EditorialTokens.canvas,
      foregroundColor: EditorialTokens.ink,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: EditorialTokens.borderSoft,
      thickness: EditorialTokens.hairline,
      space: 1,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: EditorialTokens.darkCanvas,
    fontFamily: EditorialTokens.sansFamily,
    colorScheme: const ColorScheme.dark(
      primary: EditorialTokens.primary,
      onPrimary: Colors.white,
      secondary: EditorialTokens.secondary,
      onSecondary: Colors.white,
      tertiary: EditorialTokens.tertiary,
      onTertiary: Colors.white,
      surface: EditorialTokens.darkSurface,
      onSurface: EditorialTokens.darkInk,
      surfaceContainerLowest: EditorialTokens.darkCanvas,
      surfaceContainerLow: EditorialTokens.darkSurface,
      surfaceContainer: EditorialTokens.darkSurfaceMuted,
      surfaceContainerHigh: EditorialTokens.darkSurfaceStrong,
      outline: EditorialTokens.darkBorder,
      outlineVariant: EditorialTokens.darkBorderSoft,
      error: EditorialTokens.error,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: EditorialTokens.darkCanvas,
      foregroundColor: EditorialTokens.darkInk,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: EditorialTokens.darkBorderSoft,
      thickness: EditorialTokens.hairline,
      space: 1,
    ),
  );

  // Reader Night Mode Theme for PDF Viewer container
  static const Color nightReaderBg = Color(0xFF141210);

  // Reader Eye Comfort Sepia/Amber Warm Tint Theme (filters harsh blue light)
  static const Color eyeComfortReaderBg = Color(0xFFF4EDE2);
  static const Color eyeComfortCardBg = Color(0xFFEBE0CE);
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  static const String _key = 'app_theme_mode';

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString(_key);
      if (savedStr != null) {
        if (savedStr == 'dark') state = ThemeMode.dark;
        if (savedStr == 'light') state = ThemeMode.light;
        if (savedStr == 'system') state = ThemeMode.system;
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class EyeComfortNotifier extends StateNotifier<bool> {
  EyeComfortNotifier() : super(false) {
    _loadState();
  }

  static const String _key = 'is_eye_comfort_mode';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {}
  }
}

final isEyeComfortModeProvider =
    StateNotifierProvider<EyeComfortNotifier, bool>((ref) {
  return EyeComfortNotifier();
});

class NightReadingNotifier extends StateNotifier<bool> {
  NightReadingNotifier() : super(false) {
    _loadState();
  }

  static const String _key = 'is_night_reading_mode';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {}
  }
}

final isNightReadingModeProvider =
    StateNotifierProvider<NightReadingNotifier, bool>((ref) {
  return NightReadingNotifier();
});
