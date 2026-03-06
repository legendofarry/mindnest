import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';

class CounselorInviteWaitingScreen extends ConsumerStatefulWidget {
  const CounselorInviteWaitingScreen({super.key});

  @override
  ConsumerState<CounselorInviteWaitingScreen> createState() =>
      _CounselorInviteWaitingScreenState();
}

class _CounselorInviteWaitingScreenState
    extends ConsumerState<CounselorInviteWaitingScreen> {
  bool _isSwitchingToIndividual = false;

  Future<void> _continueAsIndividual() async {
    setState(() => _isSwitchingToIndividual = true);
    try {
      await ref.read(authRepositoryProvider).setCurrentUserAsIndividual();
      if (!mounted) {
        return;
      }
      context.go(AppRoute.home);
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
        setState(() => _isSwitchingToIndividual = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MindNestShell(
      maxWidth: 560,
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Counselor Account Created',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your account is ready. Next step is to accept an institution invite from your admin.',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFFFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFB3ECDD)),
                ),
                child: const Text(
                  'Basic onboarding questions are skipped for this counselor-intent flow.',
                  style: TextStyle(
                    color: Color(0xFF0D6F69),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => context.go(AppRoute.notifications),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Open Notifications'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isSwitchingToIndividual
                    ? null
                    : _continueAsIndividual,
                child: Text(
                  _isSwitchingToIndividual
                      ? 'Switching...'
                      : 'Continue as Individual Instead',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
