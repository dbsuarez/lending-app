import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy900 = Color(0xFF0C1C45),
      navy800 = Color(0xFF142B62),
      blue600 = Color(0xFF1463F3),
      blue500 = Color(0xFF287DFF),
      violet600 = Color(0xFF6744DC),
      canvas = Color(0xFFF4F7FF),
      surfaceTint = Color(0xFFEAF1FF),
      textPrimary = Color(0xFF15223B),
      textMuted = Color(0xFF64748B),
      border = Color(0xFFDFE6F3),
      success = Color(0xFF168451),
      warning = Color(0xFF9A6200),
      danger = Color(0xFFC53040);
}

abstract final class AppTheme {
  static ThemeData get light => lightFor(AppColors.blue600);
  static ThemeData lightFor(Color seed) => _build(seed, Brightness.light);

  static ThemeData get dark => darkFor(AppColors.blue500);
  static ThemeData darkFor(Color seed) => _build(seed, Brightness.dark);

  static ThemeData _build(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      error: brightness == Brightness.light
          ? AppColors.danger
          : const Color(0xFFFF7D88),
    );
    final background =
        Color.lerp(scheme.surface, scheme.primary, .035) ?? scheme.surface;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
