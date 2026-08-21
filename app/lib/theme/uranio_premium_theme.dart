import 'package:flutter/material.dart';

/// Uranio Premium — paleta high-end sin neón.
/// Fondo negro absoluto, tarjetas elevadas sutiles, texto marfil/blanco.
class PremiumColors {
  static const background = Color(0xFF050505);
  static const surface = Color(0xFF141414);
  static const surfaceElevated = Color(0xFF1A1A1A);
  static const accent = Color(0xFFFFF8E7); // marfil sutil, no cian
  static const accentDim = Color(0x66FFFFF0);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8A929A);
  static const divider = Color(0x0FFFFFFF); // white 6% exacto (0x0F)
}

class UranioPremiumTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PremiumColors.background,
      primaryColor: PremiumColors.accent,
      colorScheme: const ColorScheme.dark(
        primary: PremiumColors.accent,
        secondary: PremiumColors.textSecondary,
        surface: PremiumColors.surface,
        error: Color(0xFFEF4444),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: PremiumColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Color(0xFFFFF8E7),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 8,
          fontFamily: 'Inter',
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: PremiumColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.3),
        titleMedium: TextStyle(color: PremiumColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
        bodyMedium: TextStyle(color: PremiumColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(color: PremiumColors.textSecondary, fontSize: 11),
        labelLarge: TextStyle(color: PremiumColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8),
      ),
      cardColor: PremiumColors.surface,
      dividerColor: PremiumColors.divider,
    );
  }

  static BoxDecoration cardDecoration({bool elevated = false}) {
    return BoxDecoration(
      color: PremiumColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      boxShadow: elevated
          ? [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))]
          : null,
    );
  }
}
