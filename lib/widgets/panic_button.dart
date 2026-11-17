import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Global emergency shortcut. Holding it for three seconds opens call choices;
/// no call or alert is sent until the user selects an action in the dialog.
class PanicButton extends StatefulWidget {
  const PanicButton({super.key, this.iconSize = 26, this.navigatorKey});

  final double iconSize;
  final GlobalKey<NavigatorState>? navigatorKey;

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
  static const _maximumContacts = 3;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );
  Timer? _holdTimer;
  bool _holding = false;
  bool _triggered = false;
  bool _showingOptions = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _startHold(TapDownDetails _) {
    _triggered = false;
    _holding = true;
    _progress.forward(from: 0);
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () async {
      _triggered = true;
      _holding = false;
      _progress
        ..stop()
        ..value = 1;
      HapticFeedback.heavyImpact();
      if (mounted) setState(() {});
      if (mounted) await _showSafetyOptions();
    });
  }

  void _cancelHold([Object? _]) {
    if (_triggered || !_holding) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _holding = false;
    _progress.reverse();
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  Future<List<_CallContact>> _readContacts() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return List.generate(_maximumContacts, (index) {
        final name = preferences.getString('safety_contact_name_$index') ?? '';
        final phone =
            preferences.getString('safety_contact_phone_$index') ?? '';
        if (name.trim().isEmpty || phone.trim().isEmpty) return null;
        return _CallContact(name: name.trim(), phone: phone.trim());
      }).whereType<_CallContact>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _showSafetyOptions() async {
    final contacts = await _readContacts();
    if (!mounted) return;

    final navigator = widget.navigatorKey?.currentState;
    final dialogContext = navigator?.overlay?.context ?? context;
    setState(() => _showingOptions = true);
    try {
      final selectedContact = await showDialog<_CallContact>(
        context: dialogContext,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.emergency_rounded, color: Color(0xFFB42318)),
          title: const Text('Emergency options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose who to call. Your phone app will open; no alert or call '
                'is sent automatically.',
              ),
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final contact in contacts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(contact.name),
                    subtitle: Text(contact.phone),
                    onTap: () => Navigator.pop(dialogContext, contact),
                  ),
              ],
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.call_rounded,
                  color: Color(0xFFB42318),
                ),
                title: const Text('Emergency services — 112'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  const _CallContact(name: 'Emergency services', phone: '112'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedContact == null) return;
      final uri = Uri(scheme: 'tel', path: selectedContact.phone);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } finally {
      if (mounted) setState(() => _showingOptions = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _showingOptions ? 0 : 1,
    duration: const Duration(milliseconds: 150),
    child: IgnorePointer(
      ignoring: _showingOptions,
      child: Semantics(
        button: true,
        label: _holding
            ? 'Keep holding for emergency call options'
            : 'Hold for three seconds to open emergency call options',
        onLongPress: () => _startHold(TapDownDetails()),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _startHold,
          onTapUp: _cancelHold,
          onTapCancel: _cancelHold,
          child: SizedBox(
            width: 72,
            height: 72,
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: CircularProgressIndicator(
                      value: _progress.value,
                      strokeWidth: 4,
                      color: Colors.white,
                      backgroundColor: const Color(0xFF8E1B14),
                    ),
                  ),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB42318),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 14,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.emergency_rounded,
                          size: widget.iconSize,
                          color: Colors.white,
                        ),
                        const Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CallContact {
  const _CallContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
