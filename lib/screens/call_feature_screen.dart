import 'dart:ui';

import 'package:flutter/material.dart';

import '../utils/theme_constants.dart';
import '../widgets/vibe_scaffold.dart';
import 'call_history_screen.dart';

class CallFeatureScreen extends StatelessWidget {
  const CallFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('OG Calls')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppStyles.brandGradient,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.video_call_rounded, color: AppColors.electricCyan, size: 58),
                    SizedBox(height: 16),
                    Text(
                      'Private voice and video calls',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Open a private chat and tap the phone or video icon to call that student.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.history_rounded)),
              title: const Text('Call history'),
              subtitle: const Text('Review incoming, outgoing, missed, and declined calls.'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
