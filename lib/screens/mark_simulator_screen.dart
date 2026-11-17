import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class MarkSimulatorScreen extends StatefulWidget {
  const MarkSimulatorScreen({super.key});

  @override
  State<MarkSimulatorScreen> createState() => _MarkSimulatorScreenState();
}

class _MarkSimulatorScreenState extends State<MarkSimulatorScreen> {
  final TextEditingController _currentMarkController = TextEditingController();
  final TextEditingController _targetGradeController = TextEditingController();

  late Future<void> _initialLoad;

  bool _showResult = false;
  double _target = 50;
  double _requiredExam = 54;

  @override
  void initState() {
    super.initState();
    _initialLoad = Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _currentMarkController.dispose();
    _targetGradeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('What Do I Need?')),
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
                _buildInputCard(),
                const SizedBox(height: 14),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _simulate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.calculate_rounded),
                    label: const Text(
                      'Simulate Required Exam Score',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_showResult) _buildResultCard(),
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
      child: const Text(
        'Target Score Simulator',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildInputCard() {
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
          _field(
            label: 'Current ICASS / Term Mark (%)',
            controller: _currentMarkController,
          ),
          const SizedBox(height: 12),
          _field(
            label:
                'Target Final Grade (e.g., 50% for Pass, 80% for Distinction)',
            controller: _targetGradeController,
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Enter value between 0 and 100',
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final double ringValue = (_requiredExam / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE7F1)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CircularProgressIndicator(
                  value: ringValue,
                  strokeWidth: 8,
                  backgroundColor: const Color(0xFFE3ECF5),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF1565C0),
                  ),
                ),
                Text(
                  '${_requiredExam.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Color(0xFF102027),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'To achieve your target of ${_target.toStringAsFixed(0)}%, '
              'you need to score exactly ${_requiredExam.toStringAsFixed(0)}% '
              'in your final DHET Exam. You can do this! 🚀',
              style: const TextStyle(
                color: Color(0xFF263238),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
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
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 132,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 52,
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

  void _simulate() {
    final double? currentMark = _parseMark(_currentMarkController.text);
    final double? targetGrade = _parseMark(_targetGradeController.text);

    if (currentMark == null || targetGrade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid percentages between 0 and 100.'),
        ),
      );
      return;
    }

    // ICASS contributes 40% and exam contributes 60%.
    final double requiredExam = (targetGrade - (0.4 * currentMark)) / 0.6;

    setState(() {
      _target = targetGrade;
      _requiredExam = requiredExam.clamp(0, 100).toDouble();
      _showResult = true;
    });
  }

  double? _parseMark(String raw) {
    final double? value = double.tryParse(raw.trim());
    if (value == null || value < 0 || value > 100) {
      return null;
    }
    return value;
  }
}
