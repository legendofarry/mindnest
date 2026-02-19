import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

class PostSignupDecisionScreen extends ConsumerStatefulWidget {
  const PostSignupDecisionScreen({super.key});

  @override
  ConsumerState<PostSignupDecisionScreen> createState() =>
      _PostSignupDecisionScreenState();
}

class _PostSignupDecisionScreenState
    extends ConsumerState<PostSignupDecisionScreen> {
  bool _isSubmitting = false;

  Future<void> _chooseIndividual() async {
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .setCurrentUserRole(UserRole.individual);
      if (mounted) {
        context.go(AppRoute.verifyEmail);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _chooseInstitutionJoin() {
    context.go(AppRoute.joinInstitution);
  }

  @override
  Widget build(BuildContext context) {
    return MindNestShell(
      maxWidth: 560,
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you joining an institution?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose one path now. You can still change later in your dashboard.',
              ),
              const SizedBox(height: 20),
              _ActionTile(
                title: 'Yes, I have a join code',
                subtitle:
                    'Join your school/university and pick Student or Staff.',
                icon: Icons.apartment_rounded,
                onTap: _isSubmitting ? null : _chooseInstitutionJoin,
              ),
              const SizedBox(height: 12),
              _ActionTile(
                title: 'No, continue as individual',
                subtitle: 'Use MindNest independently with personal tools.',
                icon: Icons.person_outline_rounded,
                onTap: _isSubmitting ? null : _chooseIndividual,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1A0F172A)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0x140E7490),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0E7490)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
