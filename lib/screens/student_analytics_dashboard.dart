import 'package:flutter/material.dart';

class StudentAnalyticsDashboard extends StatelessWidget {
  const StudentAnalyticsDashboard({super.key});

  static const Color _navy = Color(0xFF0A192F);
  // ignore: unused_field
  static const Color _slate = Color(0xFF5B677A);
  static const Color _white = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    const totalHours = 14.5;
    const breakdown = [
      _CourseHours(
        course: 'Mathematics N4',
        hours: 6.2,
        color: Color(0xFF1D4ED8),
      ),
      _CourseHours(
        course: 'Computer Practice N4',
        hours: 5.0,
        color: Color(0xFF0F766E),
      ),
      _CourseHours(
        course: 'Entrepreneurship N4',
        hours: 3.3,
        color: Color(0xFF7C3AED),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _navy,
        foregroundColor: _white,
        title: const Text(
          'My Learning Analytics (This Week)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroMetricCard(totalHours: totalHours),
            const SizedBox(height: 14),
            _BreakdownCard(totalHours: totalHours, breakdown: breakdown),
            const SizedBox(height: 14),
            _InsightCard(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Analytics report download started (PDF).'),
                    ),
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text(
                  'Download Analytics Report (PDF)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMetricCard extends StatelessWidget {
  const _HeroMetricCard({required this.totalHours});

  final double totalHours;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A192F), Color(0xFF1E3A5F)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x290A192F),
            blurRadius: 16,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: CircularProgressIndicator(
                    value: 14.5 / 20,
                    strokeWidth: 9,
                    backgroundColor: const Color(0x3DFFFFFF),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF67E8F9),
                    ),
                  ),
                ),
                Text(
                  totalHours.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '14.5 Hours',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Total Time Spent Learning This Week (+2 hrs from last week)',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.totalHours, required this.breakdown});

  final double totalHours;
  final List<_CourseHours> breakdown;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Breakdown By Course',
            style: TextStyle(
              color: Color(0xFF0A192F),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          ...breakdown.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _BreakdownRow(
                course: item.course,
                hours: item.hours,
                color: item.color,
                ratio: item.hours / totalHours,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.course,
    required this.hours,
    required this.color,
    required this.ratio,
  });

  final String course;
  final double hours;
  final Color color;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                course,
                style: const TextStyle(
                  color: Color(0xFF0A192F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${hours.toStringAsFixed(1)} hours',
              style: const TextStyle(
                color: Color(0xFF5B677A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: ratio,
            backgroundColor: const Color(0xFFE8EDF4),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7DEE8)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_rounded, color: Color(0xFFCA8A04)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Insight: You are in the Top 15% of active learners at the Ermelo Campus this month! Keep it up.',
              style: TextStyle(
                color: Color(0xFF0A192F),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseHours {
  const _CourseHours({
    required this.course,
    required this.hours,
    required this.color,
  });

  final String course;
  final double hours;
  final Color color;
}
