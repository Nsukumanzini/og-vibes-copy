import 'package:flutter/material.dart';

class OutgoingCallScreen extends StatelessWidget {
  const OutgoingCallScreen({super.key, required this.contactName, required this.callType});

  final String contactName;
  final String callType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calling')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 42, child: Icon(Icons.call_outlined, size: 36)),
            const SizedBox(height: 18),
            Text(contactName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(callType == 'video' ? 'Video call in progress' : 'Audio call in progress'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.call_end),
              label: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
