import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/interaction_feedback_service.dart';
import '../utils/theme_constants.dart';
import '../widgets/adaptive_scroll_body.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.contactName,
    required this.callType,
    required this.onAccept,
    required this.onDecline,
    this.contactPhotoUrl,
  });
  final String contactName;
  final String callType;
  final String? contactPhotoUrl;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? _ringTimer;

  @override
  void initState() {
    super.initState();
    unawaited(InteractionFeedbackService.notificationReceived());
    SystemSound.play(SystemSoundType.alert);
    _ringTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    });
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.callType == 'video';
    final photo = widget.contactPhotoUrl?.trim() ?? '';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.midnightInk,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF07172F), Color(0xFF0D47A1), Color(0xFF2457F5)],
            ),
          ),
          child: SafeArea(
            child: AdaptiveScrollBody(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              child: Column(
                children: [
                  const Text(
                    'OG CALLS',
                    style: TextStyle(
                      color: AppColors.electricCyan,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    video ? 'Incoming video call' : 'Incoming voice call',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const Spacer(),
                  Container(
                    width: 160,
                    height: 160,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppStyles.brandGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.electricCyan.withValues(alpha: .35),
                          blurRadius: 48,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: Colors.white12,
                      backgroundImage: photo.isEmpty
                          ? null
                          : CachedNetworkImageProvider(photo),
                      child: photo.isEmpty
                          ? Text(
                              widget.contactName.isEmpty
                                  ? '?'
                                  : widget.contactName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 58,
                                fontWeight: FontWeight.w900,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    widget.contactName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 30,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        video ? Icons.videocam_rounded : Icons.lock_rounded,
                        size: 17,
                        color: Colors.white60,
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'Secure OG Vibes call',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(34),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceAround,
                          spacing: 24,
                          runSpacing: 20,
                          children: [
                            _CallAnswerButton(
                              label: 'Decline',
                              icon: Icons.call_end_rounded,
                              color: AppColors.danger,
                              onTap: () {
                                HapticFeedback.heavyImpact();
                                widget.onDecline();
                              },
                            ),
                            _CallAnswerButton(
                              label: video ? 'Join video' : 'Answer',
                              icon: video
                                  ? Icons.videocam_rounded
                                  : Icons.call_rounded,
                              color: AppColors.success,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.onAccept();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallAnswerButton extends StatelessWidget {
  const _CallAnswerButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: .35), blurRadius: 22),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}
