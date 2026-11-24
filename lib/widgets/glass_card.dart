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
    final glassColor = tint.withValues(alpha: tint.a * .82);
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
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            type: MaterialType.card,
            color: glassColor,
            shadowColor: resolvedShadow,
            surfaceTintColor: surfaceTintColor ?? themeCard.surfaceTintColor,
            elevation: 0,
            shape: resolvedShape,
            borderOnForeground: borderOnForeground,
            clipBehavior: resolvedClip,
            child: Semantics(
              container: semanticContainer,
              child: Stack(
                children: [
                  if (child != null) child!,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.white.withValues(alpha: .1),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass card content with a consistent, adjustable inset and corner radius.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.margin = EdgeInsets.zero,
    this.color,
    this.width,
    this.elevation = 1.5,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final double? width;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      margin: margin,
      color: color,
      elevation: elevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: Colors.white.withValues(alpha: isDark ? .2 : .78),
        ),
      ),
      child: SizedBox(
        width: width,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
