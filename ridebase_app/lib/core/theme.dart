import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// RideBase app theme — Teal Mobility design system.
class RideBaseTheme {
  RideBaseTheme._();

  // ── Primary ───────────────────────────────────────────────────────
  static const Color teal             = Color(0xFF005E53); // primary
  static const Color tealDark         = Color(0xFF044C44); // deep header teal
  static const Color tealLight        = Color(0xFF7AD7C6); // inverse-primary
  static const Color primaryContainer = Color(0xFF00796B); // button fill bg

  // ── Surface ───────────────────────────────────────────────────────
  static const Color white            = Colors.white;
  static const Color surface          = Color(0xFFF9F9F9); // scaffold bg
  static const Color offWhite         = Color(0xFFF3F3F3); // surface-container-low
  static const Color surfaceContainer = Color(0xFFEEEEEE); // surface-container

  // ── Secondary ────────────────────────────────────────────────────
  static const Color secondary          = Color(0xFF516161);
  static const Color secondaryContainer = Color(0xFFD4E6E5); // replaces teal.shade50
  static const Color onSecondaryContainer = Color(0xFF576867);

  // ── Text ─────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A1C1C); // on-surface
  static const Color textSecondary = Color(0xFF3E4946); // on-surface-variant

  // ── Outline ──────────────────────────────────────────────────────
  static const Color outline        = Color(0xFF6E7A76);
  static const Color outlineVariant = Color(0xFFBDC9C5);
  static const Color dividerColor   = Color(0xFFEEEEEE);

  // ── Semantic ─────────────────────────────────────────────────────
  static const Color error          = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);

  // ── Theme Data ───────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: teal,
        onPrimary: white,
        primaryContainer: primaryContainer,
        onPrimaryContainer: Color(0xFFA1FEEC),
        secondary: secondary,
        onSecondary: white,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: Color(0xFF1B5D4F),
        onTertiary: white,
        tertiaryContainer: Color(0xFF377667),
        onTertiaryContainer: Color(0xFFBAFAE8),
        error: error,
        onError: white,
        errorContainer: errorContainer,
        onErrorContainer: Color(0xFF93000A),
        surface: surface,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: Color(0xFF2F3131),
        onInverseSurface: Color(0xFFF1F1F1),
        inversePrimary: tealLight,
        surfaceTint: Color(0xFF006B5E),
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: tealDark,
        foregroundColor: white,
        elevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: white,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: white,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryContainer,
        foregroundColor: white,
        elevation: 4,
      ),
      scaffoldBackgroundColor: surface,
      dividerColor: dividerColor,
    );
  }
}
