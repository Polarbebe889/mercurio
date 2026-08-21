/// Tema oscuro estilo bunker.

import 'package:flutter/material.dart';

Color colorBunker(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse(h, radix: 16) | 0xFF000000);
}

ThemeData temaBunker() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0E1113),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF22D3EE),
        brightness: Brightness.dark,
        surface: const Color(0xFF171B1E),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E1113),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF171B1E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF23282C)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF12161A),
        indicatorColor: const Color(0xFF22D3EE).withValues(alpha: .2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1C2125),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );