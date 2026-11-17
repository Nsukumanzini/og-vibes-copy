import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class ExamTimetableSeatPlanScreen extends StatelessWidget {
  const ExamTimetableSeatPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final exams = [
      {
        'course': 'Mathematics N4',
        'code': 'MTHN4-201',
        'date': 'Mon 08 Apr',
        'time': '14:00 - 16:00',
        'venue': 'Hall A',
        'seat': 'A-17',
        'gate': 'Gate 2',
      },
      {
        'course': 'Engineering Science',
        'code': 'ENGS-116',
        'date': 'Wed 10 Apr',
        'time': '09:00 - 11:00',
        'venue': 'Lab 3',
        'seat': 'B-04',
        'gate': 'Gate 1',
      },
      {
        'course': 'Industrial Management',
        'code': 'INM-220',
        'date': 'Fri 12 Apr',
        'time': '13:00 - 15:00',
        'venue': 'Block C Room 12',
        'seat': 'C-22',
        'gate': 'Gate 3',
      },
    ];

    return DefaultTabController(
      length: 2,
      child: VibeScaffold(
        appBar: AppBar(
          title: const Text('Exam Timetable & Seat Plan'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Schedule'),
              Tab(text: 'Seat Plan'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ScheduleTab(exams: exams),
            _SeatPlanTab(exam: exams.first),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.exams});

  final List<Map<String, String>> exams;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      itemBuilder: (context, index) {
        final exam = exams[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam['course'] ?? 'Exam',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text('${exam['code']} • ${exam['date']}'),
                const SizedBox(height: 4),
                Text('${exam['time']} • ${exam['venue']}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text('Add to Calendar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.chair_alt_outlined),
                        label: const Text('Seat Details'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemCount: exams.length,
    );
  }
}

class _SeatPlanTab extends StatelessWidget {
  const _SeatPlanTab({required this.exam});

  final Map<String, String> exam;

  @override
  Widget build(BuildContext context) {
    final seats = List.generate(36, (index) {
      final row = (index ~/ 6) + 1;
      final seat = (index % 6) + 1;
      return 'R$row-$seat';
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam['course'] ?? 'Exam',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${exam['date']} • ${exam['time']}'),
                  const SizedBox(height: 4),
                  Text('Venue: ${exam['venue']}'),
                  const SizedBox(height: 4),
                  Text('Seat: ${exam['seat']} • Entry: ${exam['gate']}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Seating Layout (Mock)',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: seats
                  .map(
                    (seat) => Container(
                      width: 48,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: seat == exam['seat']
                            ? const Color(0xFF2962FF)
                            : const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        seat,
                        style: TextStyle(
                          color: seat == exam['seat']
                              ? Colors.white
                              : const Color(0xFF0D47A1),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Seat plan tips'),
              subtitle: const Text(
                'Arrive 20 minutes early and keep your student card handy.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
