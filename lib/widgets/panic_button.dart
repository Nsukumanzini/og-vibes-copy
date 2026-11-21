import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme_constants.dart';
import '../services/sos_local_evidence_service.dart';

/// Global emergency shortcut. Holding it for three seconds opens emergency
/// choices. Calls open the phone app; this offline build cannot dispatch data.
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

/// Keeps the SOS control above every route and lets the user drag it out of
/// the way. Its position is remembered locally on this device.
class PanicButtonDock extends StatefulWidget {
  const PanicButtonDock({
    super.key,
    required this.child,
    required this.visible,
    required this.navigatorKey,
  });

  final Widget child;
  final bool visible;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<PanicButtonDock> createState() => _PanicButtonDockState();
}

class _PanicButtonDockState extends State<PanicButtonDock> {
  static const _buttonSize = 72.0;
  static const _horizontalPadding = 12.0;
  static const _verticalPadding = 12.0;
  static const _xPreference = 'safety_sos_position_x';
  static const _yPreference = 'safety_sos_position_y';

  Offset? _normalizedPosition;
  Offset? _dragPosition;

  @override
  void initState() {
    super.initState();
    unawaited(_restorePosition());
  }

  Future<void> _restorePosition() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final x = preferences.getDouble(_xPreference);
      final y = preferences.getDouble(_yPreference);
      if (!mounted || x == null || y == null) return;
      setState(() {
        _normalizedPosition = Offset(
          x.clamp(0.0, 1.0).toDouble(),
          y.clamp(0.0, 1.0).toDouble(),
        );
      });
    } catch (_) {
      // The default position still works if local storage is unavailable.
    }
  }

  Future<void> _savePosition(Offset position) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble(_xPreference, position.dx);
      await preferences.setDouble(_yPreference, position.dy);
    } catch (_) {
      // Dragging remains usable for this session if preferences fail.
    }
  }

  double _clamp(double value, double minimum, double maximum) =>
      value.clamp(minimum, maximum).toDouble();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final minX = math
          .max(_horizontalPadding, media.padding.left + 8)
          .toDouble();
      final maxX = math
          .max(
            minX,
            constraints.maxWidth -
                _buttonSize -
                math.max(_horizontalPadding, media.padding.right + 8),
          )
          .toDouble();
      final minY = math.max(_verticalPadding, media.padding.top + 8).toDouble();
      final bottomInset = math
          .max(media.viewInsets.bottom, media.padding.bottom)
          .toDouble();
      final maxY = math
          .max(
            minY,
            constraints.maxHeight -
                _buttonSize -
                bottomInset -
                _verticalPadding,
          )
          .toDouble();
      final defaultPosition = Offset(
        maxX,
        _clamp(
          constraints.maxHeight - _buttonSize - bottomInset - 170,
          minY,
          maxY,
        ),
      );
      final normalized = _normalizedPosition;
      final savedPosition = normalized == null
          ? defaultPosition
          : Offset(
              minX + normalized.dx * (maxX - minX),
              minY + normalized.dy * (maxY - minY),
            );
      final position = _dragPosition ?? savedPosition;

      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.visible)
            Positioned(
              left: position.dx,
              top: position.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _dragPosition = position),
                onPanUpdate: (details) {
                  final current = _dragPosition ?? position;
                  setState(() {
                    _dragPosition = Offset(
                      _clamp(current.dx + details.delta.dx, minX, maxX),
                      _clamp(current.dy + details.delta.dy, minY, maxY),
                    );
                  });
                },
                onPanEnd: (_) => _finishDrag(minX, maxX, minY, maxY),
                onPanCancel: () => _finishDrag(minX, maxX, minY, maxY),
                child: PanicButton(navigatorKey: widget.navigatorKey),
              ),
            ),
        ],
      );
    },
  );

  void _finishDrag(double minX, double maxX, double minY, double maxY) {
    final position = _dragPosition;
    if (position == null) return;
    final normalized = Offset(
      maxX == minX ? 0 : (position.dx - minX) / (maxX - minX),
      maxY == minY ? 0 : (position.dy - minY) / (maxY - minY),
    );
    setState(() {
      _normalizedPosition = normalized;
      _dragPosition = null;
    });
    unawaited(_savePosition(normalized));
  }
}

class _PanicButtonState extends State<PanicButton>
    with SingleTickerProviderStateMixin {
  static const _sosDisplayChannel = MethodChannel('ogvibes/sos_display');
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
    await _setStealthMode(true);
    try {
      final selectedContact = await showDialog<_CallContact>(
        context: dialogContext,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.82),
        builder: (dialogContext) => _EmergencyOptionsDialog(
          contacts: contacts,
          onSelect: (contact) => Navigator.pop(dialogContext, contact),
          onSafe: () => Navigator.pop(dialogContext),
        ),
      );

      if (selectedContact == null) return;
      final decision = await showDialog<_SosConsentDecision>(
        context: dialogContext,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.82),
        builder: (context) =>
            _SosCaptureConsentDialog(serviceName: selectedContact.name),
      );
      if (decision == null) return;
      if (decision == _SosConsentDecision.callWithoutCapture) {
        await _openPhone(selectedContact.phone);
        return;
      }

      final packet = await showDialog<SosLocalEvidencePacket>(
        context: dialogContext,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.82),
        builder: (context) => _SosCaptureProgressDialog(
          serviceName: selectedContact.name,
          options: decision.options!,
        ),
      );
      if (packet == null || !mounted) return;
      final receiptAction = await showDialog<_SosReceiptAction>(
        context: dialogContext,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.82),
        builder: (context) => _SosEvidenceReceiptDialog(packet: packet),
      );
      if (receiptAction == _SosReceiptAction.delete && packet.saved) {
        await const SosLocalEvidenceService().deleteLatest();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Local SOS packet deleted.')),
          );
        }
      } else if (receiptAction == _SosReceiptAction.call) {
        await _openPhone(selectedContact.phone);
      }
    } finally {
      await _setStealthMode(false);
      if (mounted) setState(() => _showingOptions = false);
    }
  }

  Future<void> _setStealthMode(bool enabled) async {
    try {
      await _sosDisplayChannel.invokeMethod<void>(
        'setStealthMode',
        <String, Object>{'enabled': enabled},
      );
    } on MissingPluginException {
      // The dark modal overlay still dims the app on unsupported platforms.
    } on PlatformException {
      // Keep the SOS dialog usable if the platform cannot change brightness.
    }
  }

  Future<void> _openPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone app.')),
      );
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

class _EmergencyOptionsDialog extends StatelessWidget {
  const _EmergencyOptionsDialog({
    required this.contacts,
    required this.onSelect,
    required this.onSafe,
  });

  final List<_CallContact> contacts;
  final ValueChanged<_CallContact> onSelect;
  final VoidCallback onSafe;

  static const _services = <_EmergencyServiceChoice>[
    _EmergencyServiceChoice(
      name: 'Police',
      detail: 'Police emergency line',
      number: '10111',
      icon: Icons.local_police_rounded,
    ),
    _EmergencyServiceChoice(
      name: 'Ambulance',
      detail: 'Medical emergency line',
      number: '10177',
      icon: Icons.medical_services_rounded,
    ),
    _EmergencyServiceChoice(
      name: 'Fire & Rescue',
      detail: 'Emergency services from a mobile phone',
      number: '112',
      icon: Icons.fire_truck_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.94, end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: const CircleAvatar(
                      radius: 25,
                      backgroundColor: Color(0xFFFFE8E5),
                      child: Icon(
                        Icons.emergency_rounded,
                        color: Color(0xFFB42318),
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOS activated',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose what help you need.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              for (final service in _services) ...[
                _EmergencyServiceCard(
                  choice: service,
                  onTap: () => onSelect(
                    _CallContact(name: service.name, phone: service.number),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (contacts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'CALL A SAVED CONTACT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 7),
                for (final contact in contacts)
                  _SavedContactCard(contact: contact, onTap: onSelect),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.vibeBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.vibeBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.vibeBlue,
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Choosing a service opens your phone app. This offline '
                        'version does not send your location, photos, audio, '
                        'or alerts to responders.',
                        style: TextStyle(height: 1.35, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              TextButton.icon(
                onPressed: onSafe,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('I’m safe — close SOS'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.vibeBlue,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCaptureConsentDialog extends StatefulWidget {
  const _SosCaptureConsentDialog({required this.serviceName});

  final String serviceName;

  @override
  State<_SosCaptureConsentDialog> createState() =>
      _SosCaptureConsentDialogState();
}

class _SosCaptureConsentDialogState extends State<_SosCaptureConsentDialog> {
  bool _includeLocation = true;
  bool _includePhotos = true;
  bool _includeAudio = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Save SOS details locally?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              'For ${widget.serviceName.toLowerCase()}. Nothing is uploaded or '
              'sent to responders. Camera and microphone activity will be '
              'visible while capture is in progress.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _consentSwitch(
              icon: Icons.location_on_outlined,
              title: 'Current location',
              value: _includeLocation,
              onChanged: (value) => setState(() => _includeLocation = value),
            ),
            _consentSwitch(
              icon: Icons.cameraswitch_outlined,
              title: 'Front and rear photos',
              value: _includePhotos,
              onChanged: (value) => setState(() => _includePhotos = value),
            ),
            _consentSwitch(
              icon: Icons.mic_none_rounded,
              title: '10-second audio recording',
              value: _includeAudio,
              onChanged: (value) => setState(() => _includeAudio = value),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.vibeBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Only the newest SOS packet is kept on this device. Starting '
                'a new capture replaces the previous packet. You can call '
                'without capturing anything.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _SosConsentDecision.capture(
                  SosCaptureOptions(
                    includeLocation: _includeLocation,
                    includePhotos: _includePhotos,
                    includeAudio: _includeAudio,
                  ),
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Capture and save locally'),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _SosConsentDecision.callWithoutCapture,
              ),
              icon: const Icon(Icons.call_rounded),
              label: const Text('Call now without capture'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.vibeBlue,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _consentSwitch({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    secondary: Icon(icon, color: AppColors.vibeBlue),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    value: value,
    onChanged: onChanged,
    activeThumbColor: AppColors.vibeBlue,
  );
}

class _SosCaptureProgressDialog extends StatefulWidget {
  const _SosCaptureProgressDialog({
    required this.serviceName,
    required this.options,
  });

  final String serviceName;
  final SosCaptureOptions options;

  @override
  State<_SosCaptureProgressDialog> createState() =>
      _SosCaptureProgressDialogState();
}

class _SosCaptureProgressDialogState extends State<_SosCaptureProgressDialog> {
  SosCaptureProgress _progress = const SosCaptureProgress(
    'Preparing local capture…',
    0,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_capture());
  }

  Future<void> _capture() async {
    SosLocalEvidencePacket packet;
    try {
      packet = await const SosLocalEvidenceService().capture(
        serviceName: widget.serviceName,
        options: widget.options,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } catch (_) {
      packet = SosLocalEvidencePacket(
        serviceName: widget.serviceName,
        createdAt: DateTime.now(),
        location: null,
        photos: const {},
        audio: null,
        issues: const ['Capture could not be completed.'],
        saved: false,
        saveError: 'Capture could not be completed.',
      );
    }
    if (mounted) Navigator.of(context).pop(packet);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_outlined,
              color: AppColors.vibeBlue,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              'Saving SOS details on this device',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _progress.label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: _progress.value,
              color: AppColors.vibeBlue,
              borderRadius: BorderRadius.circular(8),
              minHeight: 8,
            ),
            const SizedBox(height: 14),
            const Text(
              'Nothing is being sent. You can call after this capture finishes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SosEvidenceReceiptDialog extends StatelessWidget {
  const _SosEvidenceReceiptDialog({required this.packet});

  final SosLocalEvidencePacket packet;

  @override
  Widget build(BuildContext context) {
    final location = packet.location;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              packet.saved ? Icons.verified_user_rounded : Icons.error_outline,
              color: packet.saved ? AppColors.vibeBlue : AppColors.danger,
              size: 38,
            ),
            const SizedBox(height: 8),
            Text(
              packet.saved ? 'Saved on this device' : 'Could not save locally',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              'For ${packet.serviceName}. This packet has not been sent to anyone.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 15),
            if (packet.photos.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  for (final entry in packet.photos.entries)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        entry.value,
                        width: 112,
                        height: 84,
                        fit: BoxFit.cover,
                        semanticLabel:
                            '${entry.key.name} camera evidence photo',
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            _receiptRow(
              Icons.location_on_outlined,
              location == null
                  ? 'Location not captured'
                  : 'Location saved · ${location.latitude.toStringAsFixed(5)}, '
                        '${location.longitude.toStringAsFixed(5)}',
            ),
            _receiptRow(
              Icons.camera_alt_outlined,
              '${packet.photos.length} of 2 camera photos saved',
            ),
            _receiptRow(
              Icons.mic_none_rounded,
              packet.audio == null
                  ? 'Audio not recorded'
                  : '10-second audio saved',
            ),
            if (packet.issues.isNotEmpty) ...[
              const SizedBox(height: 7),
              for (final issue in packet.issues)
                Text(
                  issue,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
            ],
            if (packet.saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                packet.saveError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _SosReceiptAction.call),
              icon: const Icon(Icons.call_rounded),
              label: Text('Call ${packet.serviceName}'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            if (packet.saved)
              TextButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _SosReceiptAction.delete),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete local packet'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, _SosReceiptAction.close),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptRow(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.vibeBlue, size: 19),
        const SizedBox(width: 9),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _SosConsentDecision {
  const _SosConsentDecision._({this.options, this.callNow = false});

  const _SosConsentDecision.capture(SosCaptureOptions options)
    : this._(options: options);

  static const callWithoutCapture = _SosConsentDecision._(callNow: true);

  final SosCaptureOptions? options;
  final bool callNow;
}

enum _SosReceiptAction { call, delete, close }

class _EmergencyServiceChoice {
  const _EmergencyServiceChoice({
    required this.name,
    required this.detail,
    required this.number,
    required this.icon,
  });

  final String name;
  final String detail;
  final String number;
  final IconData icon;
}

class _EmergencyServiceCard extends StatelessWidget {
  const _EmergencyServiceCard({required this.choice, required this.onTap});

  final _EmergencyServiceChoice choice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${choice.name}. ${choice.detail}. Call ${choice.number}.',
    child: Material(
      color: const Color(0xFFFFF5F3),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF3C8C2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFFFFE4E0),
                child: Icon(choice.icon, color: const Color(0xFFB42318)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.name,
                      style: const TextStyle(
                        color: Color(0xFF252B36),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      choice.detail,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                choice.number,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SavedContactCard extends StatelessWidget {
  const _SavedContactCard({required this.contact, required this.onTap});

  final _CallContact contact;
  final ValueChanged<_CallContact> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Call ${contact.name}, ${contact.phone}',
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEAF0FF),
        child: Icon(Icons.person_outline_rounded, color: AppColors.vibeBlue),
      ),
      title: Text(
        contact.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(contact.phone),
      trailing: const Icon(Icons.call_rounded, color: AppColors.vibeBlue),
      onTap: () => onTap(contact),
    ),
  );
}

class _CallContact {
  const _CallContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
