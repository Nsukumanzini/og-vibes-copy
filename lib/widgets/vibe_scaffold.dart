import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/theme_constants.dart';

/// Shared animated shell for feature screens.
///
/// The slow ambient motion is decorative, ignores input and automatically
/// respects the platform's "reduce motion" accessibility preference.
class VibeScaffold extends StatefulWidget {
  const VibeScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.drawer,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? drawer;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  State<VibeScaffold> createState() => _VibeScaffoldState();
}

class _VibeScaffoldState extends State<VibeScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final LinearGradient background = isDark
        ? const LinearGradient(
            colors: [Color(0xFF071323), Color(0xFF0B1930), Color(0xFF082330)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : AppStyles.auroraGradient;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: background),
      child: AnimatedBuilder(
        animation: _ambientController,
        builder: (BuildContext context, Widget? child) {
          final double drift = reduceMotion ? 0.5 : _ambientController.value;
          return Stack(
            children: [
              Positioned(
                top: -150 + (drift * 28),
                right: -115 + (drift * 18),
                child: _AmbientOrb(
                  size: 330,
                  color: AppColors.vibeBlue.withValues(alpha: 0.10),
                ),
              ),
              Positioned(
                bottom: -110 + (drift * 22),
                left: -90 - (drift * 12),
                child: _AmbientOrb(
                  size: 250,
                  color: AppColors.electricCyan.withValues(alpha: 0.11),
                ),
              ),
              child!,
            ],
          );
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: widget.appBar,
            drawer: widget.drawer,
            body: SafeArea(child: widget.body),
            floatingActionButton: widget.floatingActionButton,
            bottomNavigationBar: widget.bottomNavigationBar,
          ),
        ),
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
