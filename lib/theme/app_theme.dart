import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF57C200);
  static const Color surface = Color(0xFF1C1A1A);
  static const Color background = Color(0xFF000000);
  static const Color muted = Color(0xFF9CA3AF);

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      background: background,
      surface: surface,
    ),
  );
}
