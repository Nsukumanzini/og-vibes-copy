import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:flutter/material.dart';
import '../services/offline_data_adapter.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class WhistleblowerScreen extends StatefulWidget {
  const WhistleblowerScreen({super.key});

  @override
  State<WhistleblowerScreen> createState() => _WhistleblowerScreenState();
}

class _WhistleblowerScreenState extends State<WhistleblowerScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dateTimeController = TextEditingController();

  static const List<String> _incidentTypes = [
    'Vandalism',
    'Bullying',
    'Theft',
    'Academic Fraud',
    'Maintenance Hazard',
  ];

  String? _selectedIncidentType;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _dateTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Report a serious concern')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSecurityHeader(),
              const SizedBox(height: 14),
              _buildReportForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blueTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_good_rounded, color: AppColors.deepBlue, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This report is 100% anonymous and goes directly to Campus Management. IP addresses are not tracked.',
              style: TextStyle(
                color: AppColors.midnightInk,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionLabel('Incident Type'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedIncidentType,
              dropdownColor: AppColors.surface,
              iconEnabledColor: AppColors.midnightInk,
              style: const TextStyle(color: AppColors.midnightInk),
              decoration: _fieldDecoration(
                hintText: 'Select incident type',
                icon: Icons.report_problem_outlined,
              ),
              items: _incidentTypes
                  .map(
                    (type) => DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedIncidentType = value),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please choose an incident type';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildSectionLabel('Location on Campus'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationController,
              style: const TextStyle(color: AppColors.midnightInk),
              decoration: _fieldDecoration(
                hintText: 'Example: Near Block B stairwell',
                icon: Icons.location_on_outlined,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a location';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildSectionLabel('Description of Event'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              maxLines: 5,
              style: const TextStyle(color: AppColors.midnightInk),
              decoration: _fieldDecoration(
                hintText: 'Describe what happened in clear detail.',
                icon: Icons.notes_rounded,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please provide event details';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildSectionLabel('Date & Time'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _dateTimeController,
              style: const TextStyle(color: AppColors.midnightInk),
              decoration: _fieldDecoration(
                hintText: 'Example: 26 Mar 2026, 11:45 AM',
                icon: Icons.schedule,
              ).copyWith(
                suffixIcon: IconButton(
                  onPressed: () {
                    _dateTimeController.text = '26 Mar 2026, 11:45 AM';
                  },
                  icon: const Icon(Icons.event_available, color: AppColors.textMuted),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please provide date and time';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitAnonymously,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vibeBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Submit Anonymously',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.midnightInk,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      prefixIcon: Icon(icon, color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface,
      errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF5350)),
      ),
    );
  }

  Future<void> _submitAnonymously() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await OfflineData.instance.client.from('whistleblower_reports').insert({
        'incident_type': _selectedIncidentType,
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'occurred_at_text': _dateTimeController.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _selectedIncidentType = null;
        _locationController.clear();
        _descriptionController.clear();
        _dateTimeController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2E7D32),
          content: Text(
            '🔒 Report securely submitted to Campus Management.',
          ),
        ),
      );
    } on OfflinePostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Secure submission failed: ${error.message}')),
      );
    }
  }
}
