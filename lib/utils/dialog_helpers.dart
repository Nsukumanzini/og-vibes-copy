import 'package:flutter/material.dart';

/// Shows a "Coming Soon" dialog for locked features in MVP.
/// 
/// Matches the "Happy Campus" light theme with:
/// - White background, rounded corners
/// - Electric Blue icon and button
/// - Clean, polished messaging
Future<void> showComingSoonDialog(
  BuildContext context,
  String featureName,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF2962FF).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.rocket_launch,
                  color: Color(0xFF2962FF),
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '$featureName is Coming Soon!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0D47A1),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We are polishing this feature for the official launch. '
                'Stay tuned!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Got it',
                    style: TextStyle(
                      color: Color(0xFF2962FF),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
