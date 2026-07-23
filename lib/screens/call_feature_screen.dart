import 'package:flutter/material.dart';

import 'active_call_screen.dart';
import 'call_history_screen.dart';
import 'incoming_call_screen.dart';
import 'outgoing_call_screen.dart';

class CallFeatureScreen extends StatelessWidget {
  const CallFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call Feature')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _CallActionCard(
            title: 'Start outgoing call',
            subtitle: 'Open the outgoing call screen for a demo or in-progress call UI.',
            icon: Icons.call_outlined,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OutgoingCallScreen(
                    contactName: 'Test contact',
                    callType: 'audio',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _CallActionCard(
            title: 'Simulate incoming call',
            subtitle: 'Open the incoming-call popup UI from the app navigator.',
            icon: Icons.phone_in_talk_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => IncomingCallScreen(
                    contactName: 'Test contact',
                    callType: 'video',
                    onAccept: () => Navigator.of(context).pop(),
                    onDecline: () => Navigator.of(context).pop(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _CallActionCard(
            title: 'Open active call view',
            subtitle: 'Preview the live video/audio call interface.',
            icon: Icons.videocam_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActiveCallScreen(
                    localStream: null,
                    remoteStream: null,
                    onEnd: () => Navigator.of(context).pop(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _CallActionCard(
            title: 'View call history',
            subtitle: 'See past calls and their status from the app.',
            icon: Icons.history_rounded,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CallActionCard extends StatelessWidget {
  const _CallActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: onTap,
      ),
    );
  }
}
