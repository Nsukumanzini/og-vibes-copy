import 'package:flutter/material.dart';

class GradeAppealScreen extends StatefulWidget {
  const GradeAppealScreen({super.key});

  @override
  State<GradeAppealScreen> createState() => _GradeAppealScreenState();
}

class _GradeAppealScreenState extends State<GradeAppealScreen> {
  static const Color _navy = Color(0xFF0A192F);
  static const Color _slate = Color(0xFF5B677A);
  static const Color _white = Color(0xFFFFFFFF);

  final TextEditingController _justificationController =
      TextEditingController();
  String? _selectedReason = 'Calculation Error';

  @override
  void dispose() {
    _justificationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: _white,
        elevation: 0,
        title: const Text(
          'Formal Grade Dispute Workflow',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD7DEE8)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120A192F),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selected Assignment',
                    style: TextStyle(
                      color: _slate,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Entrepreneurship N4 - Business Plan Draft (Grader: Dr. Mabena)',
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDCE3EE)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.score_rounded, color: _slate),
                        SizedBox(width: 8),
                        Text(
                          'Current Grade: 45%',
                          style: TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Reason for Appeal',
                    style: TextStyle(
                      color: _slate,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedReason,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Calculation Error',
                        child: Text('Calculation Error'),
                      ),
                      DropdownMenuItem(
                        value: 'Missing Page Unnoticed',
                        child: Text('Missing Page Unnoticed'),
                      ),
                      DropdownMenuItem(
                        value: 'Unfair Rubric Application',
                        child: Text('Unfair Rubric Application'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedReason = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Justification',
                    style: TextStyle(
                      color: _slate,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _justificationController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'Please explain your dispute...',
                      hintStyle: const TextStyle(color: Color(0xFF8A94A6)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFDCE3EE)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _navy, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Appeal logged. Ticket #4092 sent to Head of Academics.',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: _white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Submit Formal Dispute',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
