import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/auth_background_scaffold.dart';
import 'package:mindnest/core/ui/auth_desktop_shell.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';

class RegisterInstitutionSuccessScreen extends ConsumerStatefulWidget {
  const RegisterInstitutionSuccessScreen({super.key, this.institutionName});

  final String? institutionName;

  @override
  ConsumerState<RegisterInstitutionSuccessScreen> createState() =>
      _RegisterInstitutionSuccessScreenState();
}

class _RegisterInstitutionSuccessScreenState
    extends ConsumerState<RegisterInstitutionSuccessScreen> {
  static const _desktopBreakpoint = 1100.0;
  bool _dismissAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dismissWelcomeIfNeeded();
    });
  }

  Future<void> _dismissWelcomeIfNeeded() async {
    if (_dismissAttempted || !mounted) {
      return;
    }
    _dismissAttempted = true;
    try {
      await ref.read(institutionRepositoryProvider).dismissInstitutionWelcome();
    } catch (_) {
      // Ignore cleanup failure; the screen should still be usable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final content = _SuccessCard(institutionName: widget.institutionName);

    if (isDesktop) {
      return AuthDesktopShell(
        heroHighlightText: 'Institution request',
        heroBaseText: 'ready.',
        heroDescription:
            'Your email is verified and your workspace request is now in '
            'review. Enter the institution workspace to track approval and '
            'next steps.',
        metrics: const [
          AuthDesktopMetric(value: '30m', label: 'REVIEW TARGET'),
          AuthDesktopMetric(value: 'READY', label: 'EMAIL STATUS'),
        ],
        formChild: content,
      );
    }

    return AuthBackgroundScaffold(
      fallingSnow: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFCFFFFFF),
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({this.institutionName});

  final String? institutionName;

  @override
  Widget build(BuildContext context) {
    final displayInstitution = (institutionName ?? '').trim();
    final hasInstitution = displayInstitution.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFE9FBF8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFB6EFE7)),
          ),
          child: const Icon(
            Icons.celebration_rounded,
            color: Color(0xFF0E9B90),
            size: 36,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Institution workspace ready',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF071937),
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasInstitution
              ? '$displayInstitution is connected to your institution-admin '
                    'account. Continue to the workspace to track approval status and begin setup.'
              : 'Your institution-admin account is ready. Continue to the '
                    'workspace to track approval status and begin setup.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF516784),
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FFFD),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFD2F3EE)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SuccessStep(
                icon: Icons.mark_email_read_rounded,
                title: 'Account verification complete',
                description: 'Your institution-admin sign-in is active.',
              ),
              SizedBox(height: 14),
              _SuccessStep(
                icon: Icons.fact_check_outlined,
                title: 'Workspace access unlocked',
                description:
                    'Use the workspace to monitor institution status and next actions.',
              ),
              SizedBox(height: 14),
              _SuccessStep(
                icon: Icons.groups_rounded,
                title: 'Next steps are ready',
                description:
                    'You can prepare join access, team setup, and approval follow-up from one place.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF0E9B90), Color(0xFF18A89D)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3C72ECDC),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () => context.go(AppRoute.institutionAdmin),
            style: ElevatedButton.styleFrom(
              shadowColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text(
              'Enter Institution Workspace  ->',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF0E9B90), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF071937),
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF5D728B),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
