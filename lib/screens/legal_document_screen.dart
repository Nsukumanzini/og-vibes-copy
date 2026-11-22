import 'package:flutter/material.dart';

enum LegalDocumentType { terms, privacy }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final isTerms = type == LegalDocumentType.terms;
    final sections = isTerms ? _termsSections : _privacySections;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FD),
      appBar: AppBar(title: Text(isTerms ? 'Terms of Use' : 'Privacy Policy')),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D47A1), Color(0xFF2457F5)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.gavel_rounded, color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          isTerms
                              ? 'OG Vibes Terms of Use'
                              : 'Your privacy at OG Vibes',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isTerms
                              ? 'The rules that keep our student community useful, respectful and safe.'
                              : 'How we collect, use, protect and give you control over your information.',
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Effective 11 August 2026',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...sections.map(
                    (section) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE8F0FF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.$1,
                            style: const TextStyle(
                              color: Color(0xFF0D47A1),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            section.$2,
                            style: const TextStyle(
                              color: Color(0xFF2457F5),
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Questions or requests can be sent to the OG Vibes support team through the in-app support channel. Material policy changes will be communicated in the app.',
                    style: TextStyle(color: Color(0xFF66758A), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _termsSections = <(String, String)>[
    (
      '1. Agreement and eligibility',
      'By creating an account or using OG Vibes, you agree to these Terms and the Privacy Policy. You must provide accurate account information and be legally able to use the service. Student-only features may require verification by your institution.',
    ),
    (
      '2. Your account',
      'Keep your password and device secure. You are responsible for activity performed through your account. Tell support promptly if you suspect unauthorised access. Do not sell, transfer, impersonate, or create accounts for another person.',
    ),
    (
      '3. Community conduct',
      'Treat students, lecturers, staff and community members with respect. Harassment, threats, hate speech, exploitation, fraud, spam, academic dishonesty, and unlawful or dangerous content are prohibited. Never misuse emergency or safety features.',
    ),
    (
      '4. Content and permissions',
      'You keep ownership of content you submit. You give OG Vibes permission to store, process and display it only as needed to operate and improve the service. Only upload content you have the right to share, and respect copyright, privacy and confidentiality.',
    ),
    (
      '5. Academic and marketplace features',
      'Timetables, marks, learning resources, events, listings and notices may be supplied by users or institutions. Confirm important academic or financial information with the official source. Marketplace transactions are between participating users unless explicitly stated otherwise.',
    ),
    (
      '6. Safety and emergencies',
      'SOS and safety tools assist with communication and evidence collection but do not replace emergency services. If there is immediate danger, contact police, ambulance or firefighters directly. Location, media and audio are processed only when you activate the relevant feature and grant permission.',
    ),
    (
      '7. Moderation and account action',
      'We may remove content, restrict features, suspend accounts or preserve information where reasonably necessary to enforce these Terms, protect users, investigate abuse or comply with law. Available review or appeal channels will be shown where appropriate.',
    ),
    (
      '8. Availability and changes',
      'We work to keep OG Vibes reliable, but features may be interrupted, changed or retired. Offline content can be outdated until the app reconnects. We are not liable for events outside our reasonable control, subject to rights that cannot legally be excluded.',
    ),
    (
      '9. Ending use',
      'You may stop using OG Vibes or request account deletion through Settings. Some records may be retained where required for security, disputes, legal compliance or legitimate operational needs, as described in the Privacy Policy.',
    ),
  ];

  static const _privacySections = <(String, String)>[
    (
      '1. Information we collect',
      'We collect information you provide, such as your name, nickname, email, campus, course, level, profile details, posts, messages and support requests. With permission, selected features may process device tokens, location, images, video, documents or audio.',
    ),
    (
      '2. How we use information',
      'We use information to create and secure accounts, deliver academic and community features, show relevant module content, enable communication, operate safety tools, prevent abuse, provide support, and maintain or improve OG Vibes.',
    ),
    (
      '3. Legal basis and fairness',
      'We process information to provide the service you request, meet legal obligations, protect legitimate safety and security interests, and obtain consent where required. We aim to follow South Africa’s Protection of Personal Information Act and applicable institutional requirements.',
    ),
    (
      '4. Sharing',
      'Information is shared only with users you choose to interact with, authorised institutional staff where a feature requires it, service providers that operate OG Vibes, emergency or legal authorities where law or safety requires it, or another party with your instruction. We do not sell personal information.',
    ),
    (
      '5. Storage and security',
      'OG Vibes uses access controls, encrypted connections and account-based permissions to protect data. No system is completely risk-free, so keep your credentials private and report suspected misuse. Offline app data remains on your device and should be protected with device security.',
    ),
    (
      '6. Retention',
      'We keep information only as long as needed for the service, safety, dispute resolution, legal compliance and legitimate operations. Retention periods vary by data type. Deleted content may remain briefly in protected backups before scheduled removal.',
    ),
    (
      '7. Your choices and rights',
      'You may review or update profile information, control device permissions and notifications, remove content where supported, sign out, or request access, correction, objection or deletion through support and account settings. Some requests may require identity verification.',
    ),
    (
      '8. Children and sensitive information',
      'OG Vibes is designed for tertiary student communities. Do not post unnecessary identity documents, health information or other sensitive data in public areas. If a feature requests sensitive information, review its explanation before continuing.',
    ),
    (
      '9. Updates and contact',
      'We may update this Policy as OG Vibes changes. Significant updates will be highlighted in the app and the effective date will be revised. Contact in-app support for privacy questions or to exercise your rights.',
    ),
  ];
}
