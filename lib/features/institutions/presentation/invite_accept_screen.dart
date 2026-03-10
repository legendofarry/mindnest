import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({super.key, this.inviteId});

  final String? inviteId;

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _accept(UserInvite invite) async {
    final institutionCode = _codeController.text.trim().toUpperCase();
    if (institutionCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the institution code to accept.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(institutionRepositoryProvider)
          .acceptInvite(invite: invite, institutionCode: institutionCode);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted.')));
      if (invite.intendedRole == UserRole.counselor) {
        context.go(AppRoute.counselorSetup);
      } else {
        context.go(AppRoute.home);
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
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final inviteId = widget.inviteId?.trim() ?? '';

    if (inviteId.isEmpty) {
      // Fallback: send the user to Home with join-code prompt so they can proceed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoute.homeWithJoinCodeIntent());
        }
      });
      return const SizedBox.shrink();
    }

    if (authUser == null) {
      return MindNestShell(
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sign in to continue',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Invitations are handled in-app. Sign in to view and accept your invite.',
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.go(AppRoute.login),
                  child: const Text('Go to login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final inviteAsync = ref.watch(pendingUserInviteByIdProvider(inviteId));
    return MindNestShell(
      child: inviteAsync.when(
        data: (invite) {
          if (invite == null) {
            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Invite unavailable',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This invite is no longer pending. It may be expired, revoked, or already handled.',
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => context.go(AppRoute.notifications),
                      child: const Text('Back to notifications'),
                    ),
                  ],
                ),
              ),
            );
          }

          final roleLabel = invite.intendedRole.label;
          return GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Institution Invitation',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Institution: ${invite.institutionName}'),
                  const SizedBox(height: 4),
                  Text('Role: $roleLabel'),
                  const SizedBox(height: 4),
                  Text('Expires: ${invite.expiresAt?.toLocal() ?? '--'}'),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Institution code',
                      hintText: 'Enter code from admin',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Code is required to join, even with an invite.',
                    style: TextStyle(fontSize: 12),
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
