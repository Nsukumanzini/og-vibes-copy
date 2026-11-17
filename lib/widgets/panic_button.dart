import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A long-press safety control. This offline build never claims to dispatch an
/// alert; it offers a direct call action after the user confirms.
class PanicButton extends StatefulWidget {
  const PanicButton({super.key, this.iconSize = 24});

  final double iconSize;

  static Widget asAppBarAction({double iconSize = 24}) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: PanicButton(iconSize: iconSize),
  );

  @override
  State<PanicButton> createState() => _PanicButtonState();
}

class _PanicButtonState extends State<PanicButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 3);

  late final _progress = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );
  Timer? _holdTimer;
  bool _triggered = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _startHold(LongPressStartDetails _) {
    _triggered = false;
    _progress.forward(from: 0);
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () async {
      _triggered = true;
      _progress.reset();
      if (mounted) await _showSafetyOptions();
    });
  }

  void _cancelHold([Object? _]) {
    if (_triggered) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _progress.reverse();
  }

  Future<void> _showSafetyOptions() async {
    final call = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Need immediate help?'),
        content: const Text(
          'This offline app cannot send a campus safety alert or share your '
          'location. If you are in immediate danger, call emergency services.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call),
            label: const Text('Call 112'),
          ),
        ],
      ),
    );
    if (call == true) {
      await launchUrl(Uri(scheme: 'tel', path: '112'));
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: _startHold,
    onLongPressEnd: (_) => _cancelHold(),
    onLongPressCancel: _cancelHold,
    child: Semantics(
      button: true,
      label: 'Hold for three seconds to open emergency call options',
      child: SizedBox(
        width: widget.iconSize + 24,
        height: widget.iconSize + 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: widget.iconSize + 16,
              height: widget.iconSize + 16,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => CircularProgressIndicator(
                  value: _progress.value,
                  strokeWidth: 3,
                  color: Colors.redAccent,
                  backgroundColor: Colors.redAccent.withValues(alpha: .2),
                ),
              ),
            ),
            Icon(
              Icons.emergency_share_rounded,
              color: Colors.red,
              size: widget.iconSize,
            ),
          ],
        ),
      ),
    ),
  );
}
