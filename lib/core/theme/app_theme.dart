import 'package:flutter/material.dart';

/// Dark, bold, game-like palette.
abstract final class AppColors {
  static const background = Color(0xFF0B0E14);
  static const surface = Color(0xFF141925);
  static const surfaceHigh = Color(0xFF1C2333);
  static const outline = Color(0xFF2A3346);
  static const primary = Color(0xFF7CF29C); // spotter green
  static const accent = Color(0xFF5AB8FF);
  static const warning = Color(0xFFFFC145);
  static const danger = Color(0xFFFF5D6C);
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF9AA6BC);
  static const xp = Color(0xFFB98CFF);

  static const green = Color(0xFF3DDC84);
  static const yellow = Color(0xFFFFC145);
  static const red = Color(0xFFFF5D6C);

  static const unranked = Color(0xFF3A4255);
}

/// One colour per rank tier, Iron → Champion.
const List<Color> tierColors = [
  Color(0xFF8A8F98), // Iron
  Color(0xFFCD7F4A), // Bronze
  Color(0xFFC8D2DC), // Silver
  Color(0xFFFFC93C), // Gold
  Color(0xFF4FE3C1), // Platinum
  Color(0xFF6FA8FF), // Diamond
  Color(0xFFFF5DA2), // Champion
];

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Color(0xFF06210F),
    secondary: AppColors.accent,
    onSecondary: Color(0xFF04203A),
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceHigh,
    error: AppColors.danger,
    outline: AppColors.outline,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  final text = base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.18),
      height: 72,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surfaceHigh,
      side: const BorderSide(color: AppColors.outline),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
