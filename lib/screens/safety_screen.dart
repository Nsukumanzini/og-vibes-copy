import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:og_vibes_student/services/safety_ui_state.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  static const _maximumContacts = 3;

  final _campusController = TextEditingController();
  final _locationController = TextEditingController();
  final _medicalNotesController = TextEditingController();
  final _contacts = List.generate(_maximumContacts, (_) => _ContactFields());

  bool _isOnline = false;
  bool _isLoading = true;
  bool _isSaving = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    SafetyUiState.showFloatingAction.value = false;
    _loadSavedDetails();
    _primeStatus();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final nextOnline = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (mounted && nextOnline != _isOnline) {
        setState(() => _isOnline = nextOnline);
      }
    });
  }

  @override
  void dispose() {
    SafetyUiState.showFloatingAction.value = true;
    _connectivitySub?.cancel();
    _campusController.dispose();
    _locationController.dispose();
    _medicalNotesController.dispose();
    for (final contact in _contacts) {
      contact.name.dispose();
      contact.phone.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSavedDetails() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _campusController.text = preferences.getString('safety_campus') ?? '';
      _locationController.text = preferences.getString('safety_location') ?? '';
      _medicalNotesController.text =
          preferences.getString('safety_medical_notes') ?? '';
      for (var index = 0; index < _maximumContacts; index++) {
        _contacts[index]
          ..name.text =
              preferences.getString('safety_contact_name_$index') ?? ''
          ..phone.text =
              preferences.getString('safety_contact_phone_$index') ?? '';
      }
    } catch (_) {
      // The screen remains usable if local preferences cannot be read.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _primeStatus() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final online = results.any((result) => result != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);
    } catch (_) {
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _saveDetails() async {
    setState(() => _isSaving = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'safety_campus',
        _campusController.text.trim(),
      );
      await preferences.setString(
        'safety_location',
        _locationController.text.trim(),
      );
      await preferences.setString(
        'safety_medical_notes',
        _medicalNotesController.text.trim(),
      );
      for (var index = 0; index < _maximumContacts; index++) {
        await preferences.setString(
          'safety_contact_name_$index',
          _contacts[index].name.text.trim(),
        );
        await preferences.setString(
          'safety_contact_phone_$index',
          _contacts[index].phone.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Safety details saved on this device.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save details on this device.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Safety setup'),
        backgroundColor: const Color(0xFF191C20),
        foregroundColor: Colors.white,
      ),
      body: ColoredBox(
        color: const Color(0xFF191C20),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF786F)),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  _SafetyNotice(isOnline: _isOnline),
                  const SizedBox(height: 16),
                  _SafetySection(
                    title: 'Emergency contacts',
                    subtitle:
                        'Up to three people you may choose to call from the floating SOS button.',
                    icon: Icons.contacts_rounded,
                    children: [
                      for (var index = 0; index < _maximumContacts; index++)
                        _ContactEditor(index: index, fields: _contacts[index]),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SafetySection(
                    title: 'Personal safety information',
                    subtitle:
                        'Optional notes to help you remember key details.',
                    icon: Icons.badge_outlined,
                    children: [
                      _SafetyField(
                        controller: _campusController,
                        label: 'Campus or institution',
                        icon: Icons.school_outlined,
                      ),
                      const SizedBox(height: 12),
                      _SafetyField(
                        controller: _locationController,
                        label: 'Usual building or meeting point',
                        icon: Icons.place_outlined,
                      ),
                      const SizedBox(height: 12),
                      _SafetyField(
                        controller: _medicalNotesController,
                        label: 'Medical or safety notes (optional)',
                        icon: Icons.health_and_safety_outlined,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _NetworkStatusCard(isOnline: _isOnline),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveDetails,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB42318),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      icon: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSaving ? 'Saving…' : 'Save safety details',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your information is stored in this app on this device. This setup screen does not activate SOS, place calls, send alerts, or share your location.',
                    style: TextStyle(
                      color: Color(0xFFD4D7DC),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ContactFields {
  final name = TextEditingController();
  final phone = TextEditingController();
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF262A30),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFFF786F), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFFFF9189)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Safety Hub setup',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Add contact and personal details here. To open emergency call choices, use the floating SOS button and hold it for 3 seconds.',
          style: TextStyle(color: Color(0xFFF1F2F4), height: 1.45),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              size: 18,
              color: isOnline
                  ? const Color(0xFF8DE0A9)
                  : const Color(0xFFFF9189),
            ),
            const SizedBox(width: 8),
            Text(
              'Network ${isOnline ? 'connected' : 'offline'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF262A30),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF565C64)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFF9189)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFD4D7DC),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

class _ContactEditor extends StatelessWidget {
  const _ContactEditor({required this.index, required this.fields});

  final int index;
  final _ContactFields fields;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: index == 2 ? 0 : 16),
    child: Column(
      children: [
        _SafetyField(
          controller: fields.name,
          label: 'Contact ${index + 1} name',
          icon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 10),
        _SafetyField(
          controller: fields.phone,
          label: 'Phone number',
          icon: Icons.call_outlined,
          keyboardType: TextInputType.phone,
        ),
      ],
    ),
  );
}

class _SafetyField extends StatelessWidget {
  const _SafetyField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    maxLines: maxLines,
    style: const TextStyle(color: Colors.white, fontSize: 16),
    cursorColor: const Color(0xFFFF9189),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFE0E2E5)),
      prefixIcon: Icon(icon, color: const Color(0xFFFF9189)),
      filled: true,
      fillColor: const Color(0xFF17191D),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFF686E77)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: Color(0xFFFF9189), width: 2),
      ),
    ),
  );
}

class _NetworkStatusCard extends StatelessWidget {
  const _NetworkStatusCard({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF262A30),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF565C64)),
    ),
    child: Row(
      children: [
        Icon(
          isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: isOnline ? const Color(0xFF8DE0A9) : const Color(0xFFFF9189),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Network status',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                isOnline ? 'Connected' : 'Offline',
                style: const TextStyle(color: Color(0xFFE0E2E5)),
              ),
            ],
          ),
        ),
        Icon(
          Icons.circle,
          size: 10,
          color: isOnline ? const Color(0xFF8DE0A9) : const Color(0xFFFF9189),
        ),
      ],
    ),
  );
}
