import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class TutorApplicationScreen extends StatefulWidget {
  const TutorApplicationScreen({super.key});

  @override
  State<TutorApplicationScreen> createState() => _TutorApplicationScreenState();
}

class _TutorApplicationScreenState extends State<TutorApplicationScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _motivationController = TextEditingController();
  final List<String> _subjects = [
    'Math ',
    'Physics ',
    'Computer Programming',
    'Multimedia services',
  ];

  String? _selectedSubject;
  String? _attachedFileName;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _motivationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tutor Application',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF2962FF), Color(0xFF6200EA)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF0D47A1),
                        iconEnabledColor: Colors.white,
                        style: const TextStyle(color: Colors.white),
                        decoration: _glassInputDecoration('Subject you aced?'),
                        initialValue: _selectedSubject,
                        items: _subjects
                            .map(
                              (subject) => DropdownMenuItem(
                                value: subject,
                                child: Text(
                                  subject,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedSubject = value),
                        validator: (value) =>
                            value == null ? 'Select a subject' : null,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: _pickAcademicRecord,
                        icon: const Icon(Icons.attach_file),
                        label: Text(
                          _attachedFileName ?? 'Attach Academic Record (PDF)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: TextFormField(
                    controller: _motivationController,
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: _glassInputDecoration(
                      'Why should we pick you?',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().length < 30)
                        ? 'Share at least 30 characters.'
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0D47A1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _submitApplication,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Submit Application',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAcademicRecord() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    setState(() => _attachedFileName = result.files.first.name);
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_attachedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please attach your academic record.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Application submitted! We will email or call you soon.'),
      ),
    );
    _formKey.currentState!.reset();
    setState(() {
      _selectedSubject = null;
      _attachedFileName = null;
      _motivationController.clear();
    });
  }

  InputDecoration _glassInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white),
      ),
      hintStyle: const TextStyle(color: Colors.white54),
    );
  }
}
