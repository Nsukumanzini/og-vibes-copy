import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:og_vibes_student/utils/theme_constants.dart';
import 'package:og_vibes_student/widgets/vibe_scaffold.dart';

class AcademicEscalationScreen extends StatefulWidget {
  const AcademicEscalationScreen({super.key});

  @override
  State<AcademicEscalationScreen> createState() =>
      _AcademicEscalationScreenState();
}

class _AcademicEscalationScreenState extends State<AcademicEscalationScreen> {
  static const List<String> _moduleOptions = <String>[
    'Mathematics N4',
    'Computer Practice N4',
    'Entrepreneurship N4',
    'Engineering Science N4',
  ];

  static const List<String> _helpOptions = <String>[
    '1-on-1 Tutor',
    'Lecturer Consult',
    'Study Group',
  ];

  late Future<void> _initialLoad;
  String? _selectedModule;
  String? _selectedHelpType;
  final TextEditingController _descriptionController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _initialLoad = Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VibeScaffold(
      appBar: AppBar(
        title: const Text('Academic support'),
        actions: [
          Semantics(
            button: true,
            label: 'How academic support works',
            child: IconButton(
              tooltip: 'How it works',
              onPressed: _showSupportInfo,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initialLoad,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingState();
          }

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 116),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHero()
                    .animate()
                    .fadeIn(duration: 420.ms)
                    .slideY(begin: .08, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 18),
                _buildFormCard()
                    .animate(delay: 90.ms)
                    .fadeIn(duration: 420.ms)
                    .slideY(begin: .06, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 14),
                _buildTrustStrip()
                    .animate(delay: 150.ms)
                    .fadeIn(duration: 360.ms),
                const SizedBox(height: 18),
                _buildSubmitButton()
                    .animate(delay: 190.ms)
                    .fadeIn(duration: 360.ms)
                    .slideY(begin: .08, end: 0),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppStyles.brandGradient,
        borderRadius: AppStyles.bentoRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: AppColors.vibeBlue.withValues(alpha: 0.24),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -40,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.electricCyan.withValues(alpha: 0.13),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: AppStyles.pillRadius,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: 15,
                      color: AppColors.electricCyan,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Priority academic care',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'You don’t have to\nfigure it out alone.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  height: 1.14,
                  letterSpacing: -0.7,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tell us where you’re stuck and we’ll connect you with the right support.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.76),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: AppStyles.bentoRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.76),
            borderRadius: AppStyles.bentoRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
            boxShadow: AppStyles.glassShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              const Text(
                'Three quick details help us route your request.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              const _FieldLabel(number: '01', label: 'Choose your module'),
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                value: _selectedModule,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'Select the module',
                  prefixIcon: Icon(Icons.menu_book_rounded),
                ),
                items: _moduleOptions
                    .map(
                      (String module) => DropdownMenuItem<String>(
                        value: module,
                        child: Text(module),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) =>
                    setState(() => _selectedModule = value),
              ),
              const SizedBox(height: 18),
              const _FieldLabel(
                number: '02',
                label: 'Pick the support style',
              ),
              const SizedBox(height: 9),
              DropdownButtonFormField<String>(
                value: _selectedHelpType,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'How would you like help?',
                  prefixIcon: Icon(Icons.groups_2_rounded),
                ),
                items: _helpOptions
                    .map(
                      (String type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) =>
                    setState(() => _selectedHelpType = value),
              ),
              const SizedBox(height: 18),
              const _FieldLabel(
                number: '03',
                label: 'Describe the challenge',
              ),
              const SizedBox(height: 9),
              TextField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  hintText:
                      'For example: I need help understanding financial maths calculations before Friday.',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 70),
                    child: Icon(Icons.edit_note_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrustStrip() {
    return const Row(
      children: [
        Expanded(
          child: _TrustItem(
            icon: Icons.schedule_rounded,
            title: 'Quick response',
            caption: 'Usually within 24h',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _TrustItem(
            icon: Icons.lock_outline_rounded,
            title: 'Private',
            caption: 'Support team only',
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppStyles.controlRadius,
        boxShadow: [
          BoxShadow(
            color: AppColors.vibeBlue.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _sending ? null : _submitSupportRequest,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.arrow_upward_rounded),
        label: Text(
          _sending ? 'Sending request…' : 'Send priority support request',
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 116),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFE5ECF8),
        highlightColor: Colors.white,
        child: Column(
          children: [
            _skeleton(height: 230),
            const SizedBox(height: 18),
            _skeleton(height: 430),
            const SizedBox(height: 14),
            _skeleton(height: 76),
          ],
        ),
      ),
    );
  }

  Widget _skeleton({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppStyles.bentoRadius,
      ),
    );
  }

  void _showSupportInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 6, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How academic support works',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10),
            Text(
              'Your request is routed to the Head of Department and Student Support Center. Only the relevant support team can view the details.',
              style: TextStyle(color: AppColors.textMuted, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitSupportRequest() async {
    if (_selectedModule == null ||
        _selectedHelpType == null ||
        _descriptionController.text.trim().isEmpty) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all three details before sending.'),
        ),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to send this request.')),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.from('academic_support_requests').insert({
        'user_id': user.id,
        'module': _selectedModule,
        'help_type': _selectedHelpType,
        'description': _descriptionController.text.trim(),
      });
      if (!mounted) return;
      _descriptionController.clear();
      setState(() {
        _sending = false;
        _selectedModule = null;
        _selectedHelpType = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            'Support request sent to your HOD and Student Support Center.',
          ),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: ${error.message}')),
      );
    }
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.vibeBlue.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.vibeBlue,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.vibeBlue, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
