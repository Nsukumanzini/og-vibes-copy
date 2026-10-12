import 'package:flutter/material.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

export 'events_screen.dart';
export 'lost_and_found_screen.dart';

class AccommodationScreen extends StatelessWidget {
  const AccommodationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(title: const Text('Accommodation')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.construction, size: 80, color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Hang tight!\nWe are polishing this experience.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
