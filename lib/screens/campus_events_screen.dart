import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class CampusEventsScreen extends StatefulWidget {
  const CampusEventsScreen({super.key});

  @override
  State<CampusEventsScreen> createState() => _CampusEventsScreenState();
}

class _CampusEventsScreenState extends State<CampusEventsScreen> {
  late Future<Map<String, dynamic>> _eventFuture;

  @override
  void initState() {
    super.initState();
    _eventFuture = _loadEvent();
  }

  Future<Map<String, dynamic>> _loadEvent() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));

    return const {
      'title': 'SRC 2026 Election Manifestos',
      'venue': 'Main Hall, Gert Sibande Ermelo Campus',
      'date': 'Friday, 27 March 2026',
      'description':
          'Meet presidential candidates, hear policy plans, and ask direct questions before voting week.',
      'agenda': [
        '12:00 PM - Opening',
        '12:30 PM - Presidential Speeches',
        '14:00 PM - Q&A',
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Events')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateEventSheet(context),
        tooltip: 'Create Event',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _eventFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoading();
          }
          if (!snapshot.hasData || snapshot.hasError) {
            return Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _eventFuture = _loadEvent();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry event load'),
              ),
            );
          }

          final event = snapshot.data!;
          final agenda = (event['agenda'] as List<dynamic>).cast<String>();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(event),
                const SizedBox(height: 14),
                _buildAgendaCard(agenda),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreateEventSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final venueCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: 'Date')),
              TextField(controller: venueCtrl, decoration: const InputDecoration(labelText: 'Venue')),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final newEvent = {
                          'title': titleCtrl.text.isEmpty ? 'Untitled Event' : titleCtrl.text,
                          'venue': venueCtrl.text.isEmpty ? 'TBA' : venueCtrl.text,
                          'date': dateCtrl.text.isEmpty ? 'TBA' : dateCtrl.text,
                          'description': descCtrl.text.isEmpty ? '' : descCtrl.text,
                          'agenda': <String>[],
                        };

                        setState(() {
                          _eventFuture = Future.value(newEvent);
                        });

                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event created')));
                      },
                      child: const Text('Create Event'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> event) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF2962FF), Color(0xFF6A5AE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2962FF).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event['title'] as String,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                event['date'] as String,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event['venue'] as String,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            event['description'] as String,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaCard(List<String> agenda) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Event Agenda',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 10),
          ...agenda.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2962FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('RSVP noted for this event!')),
                );
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('RSVP for Manifesto Session'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
