import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme_constants.dart';
import '../widgets/glass_card.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BentoCard
// ═══════════════════════════════════════════════════════════════════════════════

/// A rounded card surface that forms the building-block of the Bento Box UI.
///
/// Drop any [child] widget inside and it will be presented on a clean,
/// softly-shadowed tile with [AppStyles.bentoRadius] corners.
///
/// Example:
/// ```dart
/// BentoCard(
///   child: Text('Hello Bento!'),
///   padding: EdgeInsets.all(20),
/// )
/// ```
class BentoCard extends StatelessWidget {
  const BentoCard({super.key, required this.child, this.padding, this.color});

  /// The widget displayed inside the card.
  final Widget child;

  /// Internal padding applied around [child]. Defaults to 20 px on all sides.
  final EdgeInsets? padding;

  /// Card background colour. Defaults to [AppColors.crispWhite] (light mode).
  /// Pass [AppColors.navyBlue] for a dark LMS surface.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: padding ?? const EdgeInsets.all(20),
      color: color,
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PrimaryHapticButton
// ═══════════════════════════════════════════════════════════════════════════════

/// A branded elevated button that fires a light haptic pulse before invoking
/// [onPressed], giving the interaction a premium tactile feel on real devices.
///
/// Example:
/// ```dart
/// PrimaryHapticButton(
///   label: 'Submit Assignment',
///   icon: Icons.send_rounded,
///   onPressed: () => _submit(),
/// )
/// ```
class PrimaryHapticButton extends StatelessWidget {
  const PrimaryHapticButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.icon,
    this.color,
  });

  /// Text label displayed on the button.
  final String label;

  /// Callback invoked after the haptic feedback has fired.
  final VoidCallback onPressed;

  /// Leading icon shown to the left of [label].
  final IconData icon;

  /// Button background colour. Defaults to [AppColors.deepBlue].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: (color ?? AppColors.deepBlue).withValues(alpha: .88),
        foregroundColor: AppColors.crispWhite,
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
        shape: RoundedRectangleBorder(
          borderRadius: AppStyles.controlRadius,
          side: BorderSide(color: Colors.white.withValues(alpha: .8)),
        ),
        overlayColor: Colors.white.withValues(alpha: .14),
        elevation: 2,
        shadowColor: AppColors.deepBlue.withValues(alpha: .2),
      ),
      icon: Icon(icon),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.0),
      ),
      onPressed: onPressed,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GlassOverlay
// ═══════════════════════════════════════════════════════════════════════════════

/// A frosted-glass container that blurs whatever is rendered behind it using
/// [BackdropFilter] and wraps the result in a semi-transparent tinted surface
/// with a subtle white border.
///
/// Use this over image backgrounds, gradient heroes, or colourful tiles to
/// achieve the Glassmorphism aesthetic.
///
/// Example:
/// ```dart
/// GlassOverlay(
///   blur: 12.0,
///   child: Text('Live Now', style: TextStyle(color: Colors.white)),
/// )
/// ```
class GlassOverlay extends StatelessWidget {
  const GlassOverlay({super.key, required this.child, this.blur = 10.0});

  /// The widget rendered inside the frosted-glass surface.
  final Widget child;

  /// Intensity of the Gaussian blur (applied to both axes). Default is 10.0.
  final double blur;

  @override
  Widget build(BuildContext context) {
    final reduceEffects =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBlur = reduceEffects
        ? 0.0
        : blur.clamp(0, AppStyles.heroBlur).toDouble();
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            // Semi-transparent white tint creates the "frosted" look.
            color: (dark ? AppColors.surfaceDark : Colors.white).withValues(
              alpha: dark ? .56 : .48,
            ),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(
              // Subtle white border reinforces the glass edge.
              color: Colors.white.withValues(alpha: dark ? .22 : .76),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
