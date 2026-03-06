import 'package:flutter/material.dart';

enum LegalDocumentType { termsOfService, privacyPolicy }

class TermsAndPrivacyScreen extends StatelessWidget {
  const TermsAndPrivacyScreen({super.key, required this.documentType});

  final LegalDocumentType documentType;

  bool get _isTerms => documentType == LegalDocumentType.termsOfService;

  @override
  Widget build(BuildContext context) {
    final title = _isTerms ? 'Terms of Service' : 'Privacy Policy';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _isTerms ? _buildTerms(context) : _buildPrivacy(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTerms(BuildContext context) {
    return const [
      _DocIntro(
        text:
            'Welcome to MindNest. These terms are written in simple language so you know what to expect when using the app.',
      ),
      _DocSection(
        title: 'Using MindNest',
        points: [
          'You can use MindNest to track wellness, complete check-ins, and access support features.',
          'Please use accurate information when creating your account.',
          'Keep your login details private and secure.',
        ],
      ),
      _DocSection(
        title: 'Health And Safety',
        points: [
          'MindNest supports wellness but is not a replacement for emergency or clinical medical care.',
          'If you are in immediate danger or crisis, contact local emergency services or a crisis line right away.',
        ],
      ),
      _DocSection(
        title: 'Respectful Use',
        points: [
          'Do not harass, threaten, or abuse other users.',
          'Do not upload harmful, illegal, or misleading content.',
          'Accounts may be limited or removed if used in harmful ways.',
        ],
      ),
      _DocSection(
        title: 'Institution Features',
        points: [
          'If you join an institution, some activity can be visible based on your privacy settings and institution rules.',
          'Invites, membership status, and access rights depend on institutional workflows.',
        ],
      ),
      _DocSection(
        title: 'Service Changes',
        points: [
          'We may improve, update, or retire features over time.',
          'Important policy updates will be reflected in this screen.',
        ],
      ),
      _DocFooter(
        text:
            'By continuing to use MindNest, you agree to these terms. If you disagree, you can stop using the app at any time.',
      ),
    ];
  }

  List<Widget> _buildPrivacy(BuildContext context) {
    return const [
      _DocIntro(
        text:
            'Your privacy matters. This policy explains what data MindNest stores and how it is used.',
      ),
      _DocSection(
        title: 'What We Collect',
        points: [
          'Account details such as name, email, and phone number.',
          'Wellness activity like onboarding responses, mood check-ins, and feature usage.',
          'Institution-related records if you join a school or organization.',
        ],
      ),
      _DocSection(
        title: 'Why We Collect It',
        points: [
          'To run your account and deliver core app features.',
          'To personalize wellness support and improve your experience.',
          'To support institution workflows such as invites, appointments, and notifications.',
        ],
      ),
      _DocSection(
        title: 'Who Can See Your Data',
        points: [
          'You can always see your own account data.',
          'Institution visibility depends on your role, privacy settings, and institutional permissions.',
          'We do not sell your personal data.',
        ],
      ),
      _DocSection(
        title: 'Your Choices',
        points: [
          'You can update your profile and privacy preferences from settings.',
          'You can export your available data from the app.',
          'If policies change, the latest version appears here.',
        ],
      ),
      _DocSection(
        title: 'Data Security',
        points: [
          'We use platform security controls and access rules to protect data.',
          'No system is perfect, but we continuously improve safety measures.',
        ],
      ),
      _DocFooter(
        text:
            'Using MindNest means you understand this policy and how your data is used to provide the service.',
      ),
    ];
  }
}

class _DocIntro extends StatelessWidget {
  const _DocIntro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFFFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB3ECDD)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0D6F69),
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _DocSection extends StatelessWidget {
  const _DocSection({required this.title, required this.points});

  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 7),
          ...points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
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
                        height: 1.35,
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

class _DocFooter extends StatelessWidget {
  const _DocFooter({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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
