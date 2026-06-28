import 'package:flutter/material.dart';

import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class MyCampusFriendsScreen extends StatelessWidget {
  const MyCampusFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('My Campus Friends'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'My campus friends will appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
