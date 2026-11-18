import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/content_service.dart';
import '../widgets/vibe_scaffold.dart';

class HelpfulContactsScreen extends StatefulWidget {
  const HelpfulContactsScreen({super.key});

  @override
  State<HelpfulContactsScreen> createState() => _HelpfulContactsScreenState();
}

class _HelpfulContactsScreenState extends State<HelpfulContactsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => ContentService.loadSection(
    'helpful_contacts',
    fallback: const <Map<String, dynamic>>[
      <String, dynamic>{
        'title': 'Student Support Office',
        'subtitle': 'Campus information and general student support.',
        'display_value': 'Example campus support page',
        'value': 'https://example.org/campus-support',
        'action': 'web',
        'category': 'Campus',
      },
      <String, dynamic>{
        'title': 'Academic Support Centre',
        'subtitle': 'Study skills, tutoring, and learning resources.',
        'display_value': 'Example academic support page',
        'value': 'https://example.org/academic-support',
        'action': 'web',
        'category': 'Academics',
      },
      <String, dynamic>{
        'title': 'Student Life Office',
        'subtitle': 'Clubs, events, and campus activities.',
        'display_value': 'Example student life page',
        'value': 'https://example.org/student-life',
        'action': 'web',
        'category': 'Campus',
      },
    ],
  );

  Future<void> _open(Map<String, dynamic> contact) async {
    final action = _contactAction(contact);
    final value = '${contact['value'] ?? ''}'.trim();
    final uri = switch (action) {
      'phone' => Uri(scheme: 'tel', path: value),
      'email' => Uri(scheme: 'mailto', path: value),
      _ => Uri.tryParse(
        value.startsWith(RegExp(r'https?://', caseSensitive: false))
            ? value
            : 'https://$value',
      ),
    };
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This contact could not be opened.')),
      );
    }
  }

  String _contactAction(Map<String, dynamic> contact) {
    final configured = '${contact['action'] ?? ''}'.trim().toLowerCase();
    if (const {'phone', 'email', 'web'}.contains(configured)) return configured;
    final value = '${contact['value'] ?? ''}'.trim();
    if (value.contains('@')) return 'email';
    if (RegExp(r'^\+?[\d\s()-]+$').hasMatch(value)) return 'phone';
    return 'web';
  }

  String _actionLabel(String action) => switch (action) {
    'phone' => 'Call now',
    'email' => 'Send email',
    _ => 'Open website',
  };

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Helpful contacts'),
        actions: <Widget>[
          IconButton(
            onPressed: () => setState(() => _future = _load()),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh directory',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF071C42),
              Color(0xFF1248A0),
              Color(0xFF5B2FC9),
            ],
          ),
        ),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            final contacts = snapshot.data ?? const <Map<String, dynamic>>[];
            if (contacts.isEmpty) {
              return const Center(
                child: Text(
                  'The contact directory is currently unavailable.',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 100),
              itemCount: contacts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final contact = contacts[index];
                final action = _contactAction(contact);
                final urgent =
                    '${contact['category']}'.toLowerCase() == 'emergency';
                final icon = action == 'phone'
                    ? Icons.phone_in_talk_rounded
                    : action == 'email'
                    ? Icons.mail_rounded
                    : Icons.language_rounded;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 25,
                            backgroundColor:
                                (urgent ? Colors.redAccent : Colors.cyanAccent)
                                    .withValues(alpha: .18),
                            child: Icon(
                              icon,
                              color: urgent
                                  ? Colors.redAccent
                                  : Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${contact['title']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${contact['subtitle'] ?? ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${contact['display_value'] ?? contact['value'] ?? ''}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _open(contact),
                          icon: Icon(icon, size: 19),
                          label: Text(_actionLabel(action)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
