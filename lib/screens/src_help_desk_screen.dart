import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:flutter/material.dart';

class SrcHelpDeskScreen extends StatefulWidget {
  const SrcHelpDeskScreen({super.key});

  @override
  State<SrcHelpDeskScreen> createState() => _SrcHelpDeskScreenState();
}

class _SrcHelpDeskScreenState extends State<SrcHelpDeskScreen> {
  final List<String> _categories = ['Maintenance', 'Safety', 'Academics'];
  final TextEditingController _issueController = TextEditingController();
  String? _selectedCategory;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SRC Help Desk',
          style: TextStyle(color: AppColors.midnightInk),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.midnightInk),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surface, AppColors.auroraCanvas, AppColors.blueTint],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                decoration: _glassInputDecoration(
                  'What do you need help with?',
                ),
                dropdownColor: const Color(0xFF2457F5),
                style: const TextStyle(color: AppColors.midnightInk),
                iconEnabledColor: AppColors.midnightInk,
                initialValue: _selectedCategory,
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(
                          category,
                          style: const TextStyle(color: AppColors.midnightInk),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedCategory = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _issueController,
                maxLines: 6,
                style: const TextStyle(color: AppColors.midnightInk),
                cursorColor: AppColors.midnightInk,
                decoration: _glassInputDecoration('Describe your issue...'),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vibeBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: _isSubmitting ? null : _submitTicket,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.midnightInk,
                        ),
                      )
                    : const Text(
                        'Open Ticket',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitTicket() async {
    if (_selectedCategory == null || _issueController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a category and describe your issue.'),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ticket opened under $_selectedCategory.')),
    );
    setState(() {
      _selectedCategory = null;
      _issueController.clear();
    });
  }

  InputDecoration _glassInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface,
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
        borderSide: const BorderSide(color: AppColors.midnightInk),
      ),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    );
  }
}
