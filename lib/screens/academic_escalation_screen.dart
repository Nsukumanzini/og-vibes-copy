import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AcademicEscalationScreen extends StatefulWidget {
  const AcademicEscalationScreen({super.key});

  @override
  State<AcademicEscalationScreen> createState() =>
      _AcademicEscalationScreenState();
}

class _AcademicEscalationScreenState extends State<AcademicEscalationScreen> {
  static const List<String> _moduleOptions = <String>[
    'Mathematics N4',
    'Computer Practice N4',
    'Entrepreneurship N4',
    'Engineering Science N4',
  ];

  static const List<String> _helpOptions = <String>[
    '1-on-1 Tutor',
    'Lecturer Consult',
    'Study Group',
  ];

  late Future<void> _initialLoad;

  String? _selectedModule;
  String? _selectedHelpType;
  final TextEditingController _descriptionController = TextEditingController();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _initialLoad = Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Ask for Help')),
      body: FutureBuilder<void>(
        future: _initialLoad,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(),
                const SizedBox(height: 14),
                _buildFormCard(),
                const SizedBox(height: 14),
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _submitSupportRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB71C1C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.warning_amber_rounded),
                    label: Text(
                      _sending
                          ? 'Sending support ticket...'
                          : 'Request Emergency Academic Support',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Academic Support Request',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Don't struggle in silence. We are here to help.",
            style: TextStyle(
              color: Color(0xFFE3F2FD),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          DropdownButtonFormField<String>(
            value: _selectedModule,
            decoration: _inputDecoration('Module Struggling With'),
            items: _moduleOptions
                .map(
                  (String module) => DropdownMenuItem<String>(
                    value: module,
                    child: Text(module),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              setState(() => _selectedModule = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedHelpType,
            decoration: _inputDecoration('Type of Help Needed'),
            items: _helpOptions
                .map(
                  (String helpType) => DropdownMenuItem<String>(
                    value: helpType,
                    child: Text(helpType),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              setState(() => _selectedHelpType = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            decoration: _inputDecoration('Brief Description').copyWith(
              hintText:
                  'Example: I am struggling with financial maths calculations and need urgent revision support.',
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: <Widget>[
            Container(
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 210,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitSupportRequest() async {
    if (_selectedModule == null ||
        _selectedHelpType == null ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields before submitting.'),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    if (!mounted) {
      return;
    }

    setState(() {
      _sending = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF2E7D32),
        content: Text(
          '✅ Support ticket sent to the Head of Department and Student Support Center.',
        ),
      ),
    );
  }
}
