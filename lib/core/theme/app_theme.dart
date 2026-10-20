import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../motion.dart';

/// Dark, layered, game-like palette. See docs/DESIGN.md.
abstract final class AppColors {
  static const background = Color(0xFF090C12);
  static const surface = Color(0xFF11161F);
  static const surfaceHigh = Color(0xFF18202D);
  static const surfaceTop = Color(0xFF212B3B);
  static const outline = Color(0xFF263043);
  static const outlineBright = Color(0xFF34405A);
  static const primary = Color(0xFF7CF29C); // success + readiness Green
  static const accent = Color(0xFF5AB8FF);
  static const warning = Color(0xFFFFC145);
  static const danger = Color(0xFFFF5D6C);
  static const textPrimary = Color(0xFFF2F5FA);
  static const textSecondary = Color(0xFF9AA6BC);
  static const textTertiary = Color(0xFF667189);
  static const xp = Color(0xFFB98CFF);
  static const hold = Color(0xFF4FD8C4); // static-hold sets

  static const green = Color(0xFF3DDC84);
  static const yellow = Color(0xFFFFC145);
  static const red = Color(0xFFFF5D6C);

  /// Unranked muscles: a dark slate, clearly darker than any tier color.
  static const unranked = Color(0xFF3A4255);

  /// Non-muscle parts of the body map (head, hair, hands, feet, knees): the silhouette.
  static const bodyBase = Color(0xFF1C2230);
}

/// Type scale. Oxanium for numbers, ranks and headers (its digits are equal-width, so numbers are
/// tabular); Barlow for UI text.
abstract final class AppType {
  static const display = 'Oxanium';
  static const ui = 'Barlow';
  static const tabular = [FontFeature.tabularFigures()];

  static const displayXL = TextStyle(fontFamily: display, fontSize: 44, fontWeight: FontWeight.w800, height: 1.05);
  static const displayL = TextStyle(fontFamily: display, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1);
  static const titleL = TextStyle(fontFamily: display, fontSize: 24, fontWeight: FontWeight.w700, height: 1.15);
  static const title = TextStyle(fontFamily: display, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2);
  static const number = TextStyle(fontFamily: display, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1);
  static const body = TextStyle(fontFamily: ui, fontSize: 16, fontWeight: FontWeight.w500, height: 1.35);
  static const bodyS = TextStyle(fontFamily: ui, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35);
  static const label = TextStyle(fontFamily: ui, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2);
}

abstract final class Space {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 20, xxl = 24, xxxl = 32;
}

abstract final class Radii {
  static const double chip = 10, control = 14, card = 20, sheet = 28;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 450);
  static const enter = Curves.easeOutCubic;
  static const pop = Curves.easeOutBack;
}

/// One colour per rank tier, Iron → Immortal: Valorant's own tier colours (the game's competitive-tier data, via
/// valorant-api.com; docs/DECISIONS.md has the table and the gradients). Only colours: the badge artwork is
/// original. Every tier keeps ≥ 3:1 contrast with [AppColors.bodyBase] and is lighter than [AppColors.unranked]
/// (test/widget/tier_palette_test.dart).
const List<Color> tierColors = [
  Color(0xFF868986), // Iron
  Color(0xFFA5855D), // Bronze
  Color(0xFFBBC2C2), // Silver
  Color(0xFFECCF56), // Gold
  Color(0xFF59A9B6), // Platinum
  Color(0xFFB489C4), // Diamond
  Color(0xFF6AE2AF), // Champion (Valorant's Ascendant)
  Color(0xFF4F7DFF), // Olympian (royal blue and gold)
  Color(0xFFBB3D65), // Immortal
];

/// Each tier's two-colour gradient: a lighter and a deeper shade of its hue (top-left → bottom-right on badges,
/// body-map fills, RR bars and legends).
const List<(Color, Color)> tierGradients = [
  (Color(0xFFB4B7B5), Color(0xFF5E6160)), // Iron: pale steel → dark steel
  (Color(0xFFD1B085), Color(0xFF7C5522)), // Bronze: sand → deep bronze
  (Color(0xFFE6EBEB), Color(0xFF8E9696)), // Silver: bright → slate
  (Color(0xFFF7E9A2), Color(0xFFC98F1E)), // Gold: pale gold → deep amber
  (Color(0xFF8FD8E0), Color(0xFF2B7F8C)), // Platinum: ice → deep teal
  (Color(0xFFDDBDEB), Color(0xFF763BAF)), // Diamond: lilac → deep violet
  (Color(0xFFA6F5CF), Color(0xFF1C7245)), // Champion: mint → deep green
  (Color(0xFFFFD25E), Color(0xFF2F58D0)), // Olympian: bright gold → deep royal blue
  (Color(0xFFFF6E8E), Color(0xFFA02D55)), // Immortal: rose → deep crimson
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
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainer: AppColors.surface,
    error: AppColors.danger,
    outline: AppColors.outline,
    outlineVariant: AppColors.outline,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark, fontFamily: AppType.ui);
  final text = base.textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);
  TextStyle? disp(TextStyle? s, double size, FontWeight w) =>
      s?.copyWith(fontFamily: AppType.display, fontSize: size, fontWeight: w, letterSpacing: 0.2);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: text.copyWith(
      displayLarge: disp(text.displayLarge, 44, FontWeight.w800),
      displayMedium: disp(text.displayMedium, 36, FontWeight.w800),
      displaySmall: disp(text.displaySmall, 32, FontWeight.w800),
      headlineLarge: disp(text.headlineLarge, 30, FontWeight.w800),
      headlineMedium: disp(text.headlineMedium, 26, FontWeight.w800),
      headlineSmall: disp(text.headlineSmall, 22, FontWeight.w700),
      titleLarge: disp(text.titleLarge, 20, FontWeight.w700),
      titleMedium: disp(text.titleMedium, 17, FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: ReduceMotionTransitions(CupertinoPageTransitionsBuilder()), // swipe-back for one-handed use
      TargetPlatform.android: ReduceMotionTransitions(FadeForwardsPageTransitionsBuilder()),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: AppType.display, fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontFamily: AppType.display, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: AppType.ui, fontSize: 16, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.outlineBright),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: AppType.ui, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: AppColors.surfaceHigh,
        selectedBackgroundColor: AppColors.primary.withValues(alpha: 0.18),
        selectedForegroundColor: AppColors.primary,
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.outline),
        textStyle: const TextStyle(fontFamily: AppType.ui, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.control), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primary.withValues(alpha: 0.16),
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: AppType.ui,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.textPrimary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      dividerColor: AppColors.outline,
      labelStyle: TextStyle(fontFamily: AppType.display, fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: TextStyle(fontFamily: AppType.display, fontWeight: FontWeight.w600, fontSize: 15),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surfaceHigh,
      side: const BorderSide(color: AppColors.outline),
      labelStyle: const TextStyle(fontFamily: AppType.ui, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet))),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontFamily: AppType.display, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
  );
}
