import 'package:flutter/material.dart';

/// Semantic color palettes for Zen & Biometric Calm themes.
class AppColorPalette {
  const AppColorPalette({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.accentTeal,
    required this.warning,
    required this.warningSurface,
    required this.wellbeing,
    required this.wellbeingAccent,
    required this.completed,
    required this.onSurfaceMuted,
    required this.calendarCell,
    required this.calendarBorder,
    required this.briefBubbleBackground,
    required this.briefBubbleBorder,
    required this.deleteAction,
    required this.splashGradientStart,
    required this.splashGradientMid,
    required this.splashGradientEnd,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color accentTeal;
  final Color warning;
  final Color warningSurface;
  final Color wellbeing;
  final Color wellbeingAccent;
  final Color completed;
  final Color onSurfaceMuted;
  final Color calendarCell;
  final Color calendarBorder;
  final Color briefBubbleBackground;
  final Color briefBubbleBorder;
  final Color deleteAction;
  final Color splashGradientStart;
  final Color splashGradientMid;
  final Color splashGradientEnd;

  static const light = AppColorPalette(
    background: Color(0xFFF7F8F4),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFEEF2EC),
    primary: Color(0xFF3D6B8C),
    secondary: Color(0xFF7BA68C),
    tertiary: Color(0xFF8B7BB8),
    accentTeal: Color(0xFF5A9E9E),
    warning: Color(0xFFD4A574),
    warningSurface: Color(0xFFFFF4E8),
    wellbeing: Color(0xFFB8E0D2),
    wellbeingAccent: Color(0xFFE8C4A8),
    completed: Color(0xFFB0B8B4),
    onSurfaceMuted: Color(0xFF6B7280),
    calendarCell: Color(0xFFE8EDE6),
    calendarBorder: Color(0xFFC5D0C8),
    briefBubbleBackground: Color(0xFFF0F4EF),
    briefBubbleBorder: Color(0xFFD8E4D8),
    deleteAction: Color(0xFFC9956A),
    splashGradientStart: Color(0xFFF7F8F4),
    splashGradientMid: Color(0xFFEEF2EC),
    splashGradientEnd: Color(0xFFE8E4F0),
  );

  static const dark = AppColorPalette(
    background: Color(0xFF0E1218),
    surface: Color(0xFF161D28),
    surfaceElevated: Color(0xFF1C2533),
    primary: Color(0xFF5B9FD4),
    secondary: Color(0xFF7ECBA8),
    tertiary: Color(0xFFA894D4),
    accentTeal: Color(0xFF6BBFBF),
    warning: Color(0xFFE8B88A),
    warningSurface: Color(0xFF2A2218),
    wellbeing: Color(0xFF1E3D32),
    wellbeingAccent: Color(0xFF3D2E24),
    completed: Color(0xFF5A6470),
    onSurfaceMuted: Color(0xFF9CA3AF),
    calendarCell: Color(0xFF141C1A),
    calendarBorder: Color(0xFF3A4A48),
    briefBubbleBackground: Color(0xFF1A2220),
    briefBubbleBorder: Color(0xFF2A3834),
    deleteAction: Color(0xFFD4A574),
    splashGradientStart: Color(0xFF0A0E14),
    splashGradientMid: Color(0xFF0E1218),
    splashGradientEnd: Color(0xFF161A28),
  );
}
