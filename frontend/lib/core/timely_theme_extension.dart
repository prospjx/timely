import 'package:flutter/material.dart';
import 'package:kairos/core/app_colors.dart';
import 'package:kairos/models/schedule_block.dart';
import 'package:kairos/utils/block_colors.dart';

/// Semantic theme extension for Timely-specific colors.
class TimelyColors extends ThemeExtension<TimelyColors> {
  const TimelyColors({
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

  Color get conflictBorder => warning;
  Color get conflictSurface => warningSurface;
  Color get conflictIcon => warning;

  Color blockColorForBlock(ScheduleBlock block) => blockColorFor(block, this);

  factory TimelyColors.fromPalette(AppColorPalette palette) {
    return TimelyColors(
      background: palette.background,
      surface: palette.surface,
      surfaceElevated: palette.surfaceElevated,
      primary: palette.primary,
      secondary: palette.secondary,
      tertiary: palette.tertiary,
      accentTeal: palette.accentTeal,
      warning: palette.warning,
      warningSurface: palette.warningSurface,
      wellbeing: palette.wellbeing,
      wellbeingAccent: palette.wellbeingAccent,
      completed: palette.completed,
      onSurfaceMuted: palette.onSurfaceMuted,
      calendarCell: palette.calendarCell,
      calendarBorder: palette.calendarBorder,
      briefBubbleBackground: palette.briefBubbleBackground,
      briefBubbleBorder: palette.briefBubbleBorder,
      deleteAction: palette.deleteAction,
      splashGradientStart: palette.splashGradientStart,
      splashGradientMid: palette.splashGradientMid,
      splashGradientEnd: palette.splashGradientEnd,
    );
  }

  static final light = TimelyColors.fromPalette(AppColorPalette.light);
  static final dark = TimelyColors.fromPalette(AppColorPalette.dark);

  @override
  TimelyColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? accentTeal,
    Color? warning,
    Color? warningSurface,
    Color? wellbeing,
    Color? wellbeingAccent,
    Color? completed,
    Color? onSurfaceMuted,
    Color? calendarCell,
    Color? calendarBorder,
    Color? briefBubbleBackground,
    Color? briefBubbleBorder,
    Color? deleteAction,
    Color? splashGradientStart,
    Color? splashGradientMid,
    Color? splashGradientEnd,
  }) {
    return TimelyColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      accentTeal: accentTeal ?? this.accentTeal,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      wellbeing: wellbeing ?? this.wellbeing,
      wellbeingAccent: wellbeingAccent ?? this.wellbeingAccent,
      completed: completed ?? this.completed,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      calendarCell: calendarCell ?? this.calendarCell,
      calendarBorder: calendarBorder ?? this.calendarBorder,
      briefBubbleBackground: briefBubbleBackground ?? this.briefBubbleBackground,
      briefBubbleBorder: briefBubbleBorder ?? this.briefBubbleBorder,
      deleteAction: deleteAction ?? this.deleteAction,
      splashGradientStart: splashGradientStart ?? this.splashGradientStart,
      splashGradientMid: splashGradientMid ?? this.splashGradientMid,
      splashGradientEnd: splashGradientEnd ?? this.splashGradientEnd,
    );
  }

  @override
  TimelyColors lerp(TimelyColors? other, double t) {
    if (other == null) {
      return this;
    }
    return TimelyColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      accentTeal: Color.lerp(accentTeal, other.accentTeal, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      wellbeing: Color.lerp(wellbeing, other.wellbeing, t)!,
      wellbeingAccent: Color.lerp(wellbeingAccent, other.wellbeingAccent, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      calendarCell: Color.lerp(calendarCell, other.calendarCell, t)!,
      calendarBorder: Color.lerp(calendarBorder, other.calendarBorder, t)!,
      briefBubbleBackground: Color.lerp(briefBubbleBackground, other.briefBubbleBackground, t)!,
      briefBubbleBorder: Color.lerp(briefBubbleBorder, other.briefBubbleBorder, t)!,
      deleteAction: Color.lerp(deleteAction, other.deleteAction, t)!,
      splashGradientStart: Color.lerp(splashGradientStart, other.splashGradientStart, t)!,
      splashGradientMid: Color.lerp(splashGradientMid, other.splashGradientMid, t)!,
      splashGradientEnd: Color.lerp(splashGradientEnd, other.splashGradientEnd, t)!,
    );
  }
}

extension TimelyTheme on BuildContext {
  TimelyColors get timelyColors => Theme.of(this).extension<TimelyColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
}
