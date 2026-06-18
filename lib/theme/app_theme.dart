import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Raisul TV — Custom Theme
/// A dark, cinematic theme designed for both mobile and TV (10-foot UI) experiences.
class AppTheme {
  AppTheme._();

  // Brand palette
  static const Color background = Color(0xFF0A0E21);
  static const Color surface = Color(0xFF141A35);
  static const Color surfaceLight = Color(0xFF1E2747);
  static const Color primary = Color(0xFFFF5A36); // signature orange-red
  static const Color primaryDark = Color(0xFFD8431F);
  static const Color accent = Color(0xFF36D6FF); // cyan accent
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFFA0A8C0);
  static const Color liveRed = Color(0xFFFF3B30);

  static ThemeData get darkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: accent,
        surface: surface,
        background: background,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      focusColor: primary.withOpacity(0.35),
      splashColor: primary.withOpacity(0.2),
      highlightColor: primary.withOpacity(0.15),
    );
  }

  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF10162E), Color(0xFF080B1A)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surfaceLight, surface],
  );

  static const LinearGradient liveBadgeGradient = LinearGradient(
    colors: [Color(0xFFFF5A36), Color(0xFFFF3B30)],
  );
}
