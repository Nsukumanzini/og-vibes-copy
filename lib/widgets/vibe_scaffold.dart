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
  bool _reduceMotion = false;
  bool _hasScrolled = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce == _reduceMotion) {
      if (!reduce && !_ambientController.isAnimating) {
        _ambientController.repeat(reverse: true);
      }
      return;
    }
    _reduceMotion = reduce;
    if (reduce) {
      _ambientController
        ..stop()
        ..value = 0.5;
    } else {
      _ambientController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          final double drift = _reduceMotion ? 0.5 : _ambientController.value;
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
            appBar: _scrollAwareAppBar,
            drawer: widget.drawer,
            body: SafeArea(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: widget.body,
              ),
            ),
            floatingActionButton: widget.floatingActionButton,
            bottomNavigationBar: widget.bottomNavigationBar,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? get _scrollAwareAppBar {
    final appBar = widget.appBar;
    if (!_hasScrolled || appBar is! AppBar) return appBar;
    return AppBar(
      key: appBar.key,
      leading: appBar.leading,
      automaticallyImplyLeading: appBar.automaticallyImplyLeading,
      title: appBar.title,
      actions: appBar.actions,
      automaticallyImplyActions: appBar.automaticallyImplyActions,
      flexibleSpace: appBar.flexibleSpace,
      bottom: appBar.bottom,
      elevation: appBar.elevation,
      scrolledUnderElevation: 0,
      notificationPredicate: appBar.notificationPredicate,
      shadowColor: appBar.shadowColor,
      shape: appBar.shape,
      backgroundColor: AppColors.vibeBlue,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      iconTheme: appBar.iconTheme,
      actionsIconTheme: appBar.actionsIconTheme,
      primary: appBar.primary,
      centerTitle: appBar.centerTitle,
      excludeHeaderSemantics: appBar.excludeHeaderSemantics,
      titleSpacing: appBar.titleSpacing,
      toolbarOpacity: appBar.toolbarOpacity,
      bottomOpacity: appBar.bottomOpacity,
      toolbarHeight: appBar.toolbarHeight,
      leadingWidth: appBar.leadingWidth,
      toolbarTextStyle: appBar.toolbarTextStyle,
      titleTextStyle: appBar.titleTextStyle,
      systemOverlayStyle: appBar.systemOverlayStyle,
      forceMaterialTransparency: appBar.forceMaterialTransparency,
      useDefaultSemanticsOrder: appBar.useDefaultSemanticsOrder,
      clipBehavior: appBar.clipBehavior,
      actionsPadding: appBar.actionsPadding,
      animateColor: true,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final isScrolled = notification.metrics.pixels > 24;
    if (isScrolled != _hasScrolled && mounted) {
      setState(() => _hasScrolled = isScrolled);
    }
    return false;
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
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
