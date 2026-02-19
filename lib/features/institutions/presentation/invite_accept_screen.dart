import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';
import 'package:mindnest/features/onboarding/data/onboarding_providers.dart';

class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({super.key});

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  bool _isSubmitting = false;

  Future<void> _accept(UserInvite invite) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(institutionRepositoryProvider).acceptInvite(invite);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted.')));
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
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _decline(UserInvite invite) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(institutionRepositoryProvider).declineInvite(invite);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite declined.')));
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
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final inviteAsync = ref.watch(pendingUserInviteProvider);

    return MindNestShell(
      child: inviteAsync.when(
        data: (invite) {
          if (invite == null) {
            final onboardingNeeded = ref
                .watch(onboardingRepositoryProvider)
                .requiresQuestionnaire(profile);
            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'No pending invite found.',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => context.go(
                        onboardingNeeded ? AppRoute.onboarding : AppRoute.home,
                      ),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            );
          }

          final currentInstitutionId = profile?.institutionId ?? '';
          final roleWillChange =
              profile == null || profile.role != invite.intendedRole;
          final institutionWillChange =
              currentInstitutionId.isNotEmpty &&
              currentInstitutionId != invite.institutionId;

          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Invitation Found',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You were invited to join ${invite.institutionName} as ${invite.intendedRole.label}.',
                  ),
                  const SizedBox(height: 16),
                  if (roleWillChange || institutionWillChange)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        'Accepting this invite will update your role/institution and may trigger onboarding for the new role.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _accept(invite),
                    child: Text(
                      _isSubmitting ? 'Accepting...' : 'Accept invite',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => _decline(invite),
                    child: const Text('Decline invite'),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(error.toString()),
          ),
        ),
      ),
    );
  }
}
