import 'package:flutter/material.dart';

import '../screens/og_assistant_screen.dart';

/// Header shortcut to OG Assistant, shared by all five home tabs.
class OgAssistantButton extends StatelessWidget {
  const OgAssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Open OG Assistant',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const OgAssistantScreen(),
          ),
        );
      },
      icon: const Icon(Icons.auto_awesome_rounded),
    );
  }
}
