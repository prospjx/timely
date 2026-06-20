import 'package:flutter/material.dart';
import 'package:kairos/core/app_spacing.dart';
import 'package:kairos/core/timely_theme_extension.dart';

class ZenCard extends StatelessWidget {
  const ZenCard({
    super.key,
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final timely = context.timelyColors;
    final fill = tint ?? timely.surface;

    final card = Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: card,
      ),
    );
  }
}
