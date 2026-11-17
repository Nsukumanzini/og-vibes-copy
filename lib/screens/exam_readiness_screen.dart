import 'package:flutter/material.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class ExamReadinessScreen extends StatefulWidget {
  const ExamReadinessScreen({super.key});

  @override
  State<ExamReadinessScreen> createState() => _ExamReadinessScreenState();
}

class _ExamReadinessScreenState extends State<ExamReadinessScreen> {
  final List<_ChecklistItem> _items = <_ChecklistItem>[
    _ChecklistItem(label: 'Pack valid Student ID Card.'),
    _ChecklistItem(label: 'Pack 2x Black Pens, Pencil, Eraser.'),
    _ChecklistItem(label: 'Pack approved Casio Scientific Calculator.'),
    _ChecklistItem(label: 'Set alarm for 06:30 AM.'),
  ];

  bool get _allChecked => _items.every((item) => item.checked);

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Exam Readiness')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Exam-Day Readiness Checklist',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF102027),
              ),
            ),
            const SizedBox(height: 12),
            _buildHeroCard(),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE3EAF2)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (BuildContext context, int index) {
                    return const Divider(height: 1);
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final _ChecklistItem item = _items[index];
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: item.checked,
                      onChanged: (bool? value) {
                        setState(() {
                          item.checked = value ?? false;
                        });
                      },
                      title: Text(
                        item.label,
                        style: const TextStyle(
                          color: Color(0xFF263238),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _allChecked
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Good luck! You've got this."),
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFB0BEC5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'I am ready for this exam!',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
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
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Text(
        'Next Exam: Mathematics N4\n(Tomorrow, 09:00 AM @ Main Hall)',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ChecklistItem {
  _ChecklistItem({required this.label});

  final String label;
  bool checked = false;
}
