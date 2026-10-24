import 'package:flutter/material.dart';

/// Blackwake palette: dark wood and parchment UI over a turquoise sea.
class BwColors {
  static const wood = Color(0xFF3B2416);
  static const woodLight = Color(0xFF5C3A22);
  static const parchment = Color(0xFFF3E3C3);
  static const parchmentDark = Color(0xFFE2CB9D);
  static const gold = Color(0xFFD9A441);
  static const ink = Color(0xFF2A1A10);
  static const sea = Color(0xFF1FB5B0);
  static const deepSea = Color(0xFF0B4F6C);
  static const sand = Color(0xFFE8D3A2);
  static const jungle = Color(0xFF5FA84D);
  static const danger = Color(0xFFB3412E);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BwColors.wood,
    primary: BwColors.wood,
    onPrimary: BwColors.parchment,
    secondary: BwColors.gold,
    onSecondary: BwColors.ink,
    surface: BwColors.parchment,
    onSurface: BwColors.ink,
    error: BwColors.danger,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: BwColors.deepSea,
    appBarTheme: const AppBarTheme(
      backgroundColor: BwColors.wood,
      foregroundColor: BwColors.parchment,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BwColors.wood,
        foregroundColor: BwColors.parchment,
        disabledBackgroundColor: BwColors.parchmentDark,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: BwColors.wood,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: BwColors.wood),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BwColors.parchment,
      showDragHandle: true,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white70,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
