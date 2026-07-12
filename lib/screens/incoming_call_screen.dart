import 'package:flutter/material.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key, required this.contactName, required this.callType, required this.onAccept, required this.onDecline});

  final String contactName;
  final String callType;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incoming call')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 48, child: Icon(Icons.call, size: 40)),
            const SizedBox(height: 18),
            Text(contactName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(callType == 'video' ? 'Incoming video call' : 'Incoming audio call'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.call),
                  label: const Text('Accept'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onDecline,
                  icon: const Icon(Icons.call_end),
                  label: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
