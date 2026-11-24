import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/theme_constants.dart';

/// A lightly frosted card surface that follows the app's light and dark theme.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.child,
    this.semanticContainer = true,
  });

  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final ShapeBorder? shape;
  final bool borderOnForeground;
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;
  final Widget? child;
  final bool semanticContainer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeCard = theme.cardTheme;
    final resolvedShape =
        shape ??
        themeCard.shape ??
        RoundedRectangleBorder(borderRadius: AppStyles.bentoRadius);
    final resolvedMargin =
        margin ?? themeCard.margin ?? const EdgeInsets.all(4);
    final tint = color ?? themeCard.color ?? theme.colorScheme.surface;
    final glassColor = tint.withValues(alpha: tint.a * .84);
    final resolvedElevation = elevation ?? themeCard.elevation ?? 1;
    final resolvedShadow =
        shadowColor ?? themeCard.shadowColor ?? AppColors.deepBlue;
    final resolvedClip = clipBehavior ?? Clip.antiAlias;
    final shapeClipper = ShapeBorderClipper(
      shape: resolvedShape,
      textDirection: Directionality.of(context),
    );

    return Padding(
      padding: resolvedMargin,
      child: PhysicalShape(
        color: Colors.transparent,
        elevation: resolvedElevation,
        shadowColor: resolvedShadow.withValues(alpha: .12),
        clipper: shapeClipper,
        clipBehavior: resolvedClip,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            type: MaterialType.card,
            color: glassColor,
            shadowColor: resolvedShadow,
            surfaceTintColor: surfaceTintColor ?? themeCard.surfaceTintColor,
            elevation: 0,
            shape: resolvedShape,
            borderOnForeground: borderOnForeground,
            clipBehavior: resolvedClip,
            child: Semantics(container: semanticContainer, child: child),
          ),
        ),
      ),
    );
  }
}
