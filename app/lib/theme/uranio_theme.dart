import 'package:flutter/material.dart';

/// Paleta "Uranio" — design system de Mercurio.
class UranioColors {
  static const background = Color(0xFF0E1113);
  static const surface = Color(0xFF171B1E);
  static const surfaceElevated = Color(0xFF1D2226);
  static const accent = Color(0xFF22D3EE);
  static const textPrimary = Color(0xFFF4F6F7);
  static const textSecondary = Color(0xFF8B959A);
  static const divider = Color(0xFF23282B);
  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF34D399);
}

class UranioTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: UranioColors.background,
      primaryColor: UranioColors.accent,
      colorScheme: const ColorScheme.dark(
        primary: UranioColors.accent,
        secondary: UranioColors.accent,
        surface: UranioColors.surface,
        error: UranioColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: UranioColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: UranioColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: UranioColors.textSecondary),
        bodySmall: TextStyle(color: UranioColors.textSecondary, fontSize: 12),
      ),
      cardColor: UranioColors.surface,
      dividerColor: UranioColors.divider,
    );
  }

  static BoxDecoration cardDecoration({bool glow = false}) {
    return BoxDecoration(
      color: UranioColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: UranioColors.divider, width: 1),
      boxShadow: glow
          ? [
              BoxShadow(
                color: UranioColors.accent.withOpacity(0.15),
                blurRadius: 24,
                spreadRadius: -4,
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
    );
  }
}
