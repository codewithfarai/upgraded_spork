import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// RideBase app theme — teal + white to match the MAUI app aesthetic.
class RideBaseTheme {
  RideBaseTheme._();

  // ── Brand Colors ──────────────────────────────────────────────────
  static const Color teal = Color(0xFF008080);
  static const Color tealDark = Color(0xFF006666);
  static const Color tealLight = Color(0xFF00A3A3);
  static const Color white = Colors.white;
  static const Color offWhite = Color(0xFFF5F5F5);
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color dividerColor = Color(0xFFE5E7EB);

  // ── Theme Data ────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final textTheme = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        onPrimary: white,
        surface: white,
        onSurface: textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: teal,
        foregroundColor: white,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
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
        backgroundColor: white,
        foregroundColor: teal,
        elevation: 4,
      ),
      scaffoldBackgroundColor: white,
      dividerColor: dividerColor,
    );
  }
}
