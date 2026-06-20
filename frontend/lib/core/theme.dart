import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kairos/core/app_colors.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';

class AppTheme {
  static ThemeData lightTheme() => _buildTheme(
        brightness: Brightness.light,
        palette: AppColorPalette.light,
        timelyColors: TimelyColors.light,
      );

  static ThemeData darkTheme() => _buildTheme(
        brightness: Brightness.dark,
        palette: AppColorPalette.dark,
        timelyColors: TimelyColors.dark,
      );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppColorPalette palette,
    required TimelyColors timelyColors,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).copyWith(
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : const Color(0xFF1F2937),
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: isDark ? Colors.white : const Color(0xFF374151),
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: palette.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: palette.primary,
        onPrimary: Colors.white,
        secondary: palette.secondary,
        onSecondary: isDark ? Colors.white : const Color(0xFF1F2937),
        error: palette.warning,
        onError: isDark ? Colors.white : const Color(0xFF1F2937),
        surface: palette.surface,
        onSurface: isDark ? Colors.white : const Color(0xFF1F2937),
        onSurfaceVariant: palette.onSurfaceMuted,
      ),
      textTheme: textTheme,
      extensions: [timelyColors],
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0 : 0.08),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: palette.primary, fontWeight: FontWeight.w600);
          }
          return TextStyle(color: palette.onSurfaceMuted);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: palette.primary);
          }
          return IconThemeData(color: palette.onSurfaceMuted);
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: palette.calendarBorder.withValues(alpha: 0.5),
      ),
    );
  }
}
