import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF253331);
  static const muted = Color(0xFF667572);
  static const paper = Color(0xFFFFFBF4);
  static const cream = Color(0xFFF5EEDC);
  static const jade = Color(0xFF147A6B);
  static const jadeSoft = Color(0xFFDCEDE8);
  static const coral = Color(0xFFE96B52);
  static const coralSoft = Color(0xFFFFE5DE);
  static const yellow = Color(0xFFF2C94C);
  static const sun = Color(0xFFFFC857);
  static const sunSoft = Color(0xFFFFF1BF);
  static const sky = Color(0xFF4C9BE8);
  static const skySoft = Color(0xFFDDEEFF);
  static const berry = Color(0xFF7656C5);
  static const berrySoft = Color(0xFFEAE2FF);
  static const border = Color(0xFFE2DDD1);
}

abstract final class AppType {
  static TextStyle emoji(double size) => TextStyle(
        fontSize: size,
        fontFamily: 'Segoe UI Emoji',
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Noto Color Emoji',
          'sans-serif',
        ],
      );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.jade,
    brightness: Brightness.light,
    primary: AppColors.jade,
    secondary: AppColors.coral,
    surface: AppColors.paper,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    fontFamily: 'NotoSansTC',
    fontFamilyFallback: const [
      'Noto Sans TC',
      'Microsoft JhengHei UI',
      'Segoe UI Emoji',
      'Apple Color Emoji',
      'Noto Color Emoji',
      'Noto Sans',
      'sans-serif',
    ],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 29,
        height: 1.22,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 24,
        height: 1.28,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: TextStyle(
        color: AppColors.ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: AppColors.ink, fontSize: 16, height: 1.55),
      bodyMedium: TextStyle(color: AppColors.ink, fontSize: 14, height: 1.5),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 1,
      shadowColor: Color(0x14000000),
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.jade, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.sunSoft,
      elevation: 4,
      height: 72,
    ),
  );
}
