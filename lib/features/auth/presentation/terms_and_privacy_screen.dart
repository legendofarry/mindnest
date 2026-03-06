import 'package:flutter/material.dart';

enum LegalDocumentType { termsOfService, privacyPolicy }

class TermsAndPrivacyScreen extends StatelessWidget {
  const TermsAndPrivacyScreen({super.key, required this.documentType});

  final LegalDocumentType documentType;

  bool get _isTerms => documentType == LegalDocumentType.termsOfService;
  String get _title => _isTerms ? 'Terms of Service' : 'Privacy Policy';
  String get _subtitle => _isTerms
      ? 'Clear, friendly rules for using MindNest confidently.'
      : 'A simple explanation of what we collect and why.';
  IconData get _heroIcon =>
      _isTerms ? Icons.gavel_rounded : Icons.privacy_tip_rounded;

  List<String> get _highlights => _isTerms
      ? const ['Simple language', 'Respectful use', 'Safety first']
      : const ['You stay in control', 'No data selling', 'Clear visibility'];

  List<_LegalSection> get _sections => _isTerms
      ? const [
          _LegalSection(
            icon: Icons.waving_hand_rounded,
            title: 'Using MindNest',
            points: [
              'Use MindNest for check-ins, wellness support, and guided tools.',
              'Provide accurate account details so your experience is reliable.',
              'Keep your login secure and do not share your password.',
            ],
          ),
          _LegalSection(
            icon: Icons.health_and_safety_rounded,
            title: 'Health And Safety',
            points: [
              'MindNest supports wellbeing but is not emergency medical care.',
              'For urgent danger or crisis, contact local emergency services immediately.',
            ],
          ),
          _LegalSection(
            icon: Icons.groups_rounded,
            title: 'Respectful Community',
            points: [
              'Do not harass, threaten, or abuse others.',
              'Do not post harmful, illegal, or misleading content.',
              'Harmful misuse may lead to restrictions on your account.',
            ],
          ),
          _LegalSection(
            icon: Icons.school_rounded,
            title: 'Institution Features',
            points: [
              'If you join an institution, visibility follows your role and privacy settings.',
              'Invites, membership, and access rights follow institution workflows.',
            ],
          ),
          _LegalSection(
            icon: Icons.update_rounded,
            title: 'Service Updates',
            points: [
              'MindNest features may evolve over time as we improve the product.',
              'Any important legal or policy updates will be reflected here.',
            ],
          ),
        ]
      : const [
          _LegalSection(
            icon: Icons.dataset_rounded,
            title: 'What We Collect',
            points: [
              'Profile info like name, email, and phone numbers.',
              'Wellness activity such as onboarding responses and mood check-ins.',
              'Institution records when you join a school or organization.',
            ],
          ),
          _LegalSection(
            icon: Icons.lightbulb_circle_rounded,
            title: 'Why We Collect It',
            points: [
              'To run your account and deliver essential app functions.',
              'To personalize support and improve your wellness experience.',
              'To power institution workflows like invites and appointments.',
            ],
          ),
          _LegalSection(
            icon: Icons.visibility_rounded,
            title: 'Who Can See Data',
            points: [
              'You can always access your own personal data.',
              'Institution visibility depends on role, permissions, and settings.',
              'MindNest does not sell your personal data.',
            ],
          ),
          _LegalSection(
            icon: Icons.tune_rounded,
            title: 'Your Choices',
            points: [
              'Update profile and privacy preferences from app settings.',
              'Export your available data from within the app.',
              'New policy versions are shown in this screen.',
            ],
          ),
          _LegalSection(
            icon: Icons.lock_rounded,
            title: 'Security',
            points: [
              'MindNest uses platform security controls and access rules.',
              'No system is perfect, but protections are continuously improved.',
            ],
          ),
        ];

  String get _footerText => _isTerms
      ? 'By using MindNest, you agree to these terms. If you do not agree, you can stop using the app at any time.'
      : 'Using MindNest means you understand this policy and how data supports your experience.';

  @override
  Widget build(BuildContext context) {
    final otherDoc = _isTerms
        ? LegalDocumentType.privacyPolicy
        : LegalDocumentType.termsOfService;
    final otherLabel = _isTerms
        ? 'Open Privacy Policy'
        : 'Open Terms of Service';

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF8FDFF), Color(0xFFF1F9F8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth >= 920
                  ? 24.0
                  : 16.0;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      14,
                      horizontalPadding,
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroCard(
                          title: _title,
                          subtitle: _subtitle,
                          icon: _heroIcon,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _highlights
                              .map((item) => _HighlightChip(label: item))
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TermsAndPrivacyScreen(
                                      documentType: otherDoc,
                                    ),
                                  ),
                                ),
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: Text(otherLabel),
                          ),
                        ),
                        const SizedBox(height: 2),
                        ...List<Widget>.generate(_sections.length, (index) {
                          final section = _sections[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _LegalSectionCard(
                              section: section,
                              index: index + 1,
                            ),
                          );
                        }),
                        _EndCard(text: _footerText),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection({
    required this.icon,
    required this.title,
    required this.points,
  });

  final IconData icon;
  final String title;
  final List<String> points;
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C7F79), Color(0xFF14A399)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2D089981),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFE6FFFB),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
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

class _HighlightChip extends StatelessWidget {
  const _HighlightChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD4F1EC)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0D6F69),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _LegalSectionCard extends StatelessWidget {
  const _LegalSectionCard({required this.section, required this.index});

  final _LegalSection section;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFFFC),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  section.icon,
                  size: 17,
                  color: const Color(0xFF0E9B90),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '$index. ${section.title}',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...section.points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: Color(0xFF0E9B90),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                        height: 1.38,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFF1F7FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}
