import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/core/ui/mindnest_shell.dart';
import 'package:mindnest/core/ui/modern_banner.dart';
import 'package:mindnest/features/auth/data/auth_providers.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/data/institution_providers.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';
import 'package:mindnest/features/auth/presentation/logout/logout_flow.dart';

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
      await _syncConnectedState(invite);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite accepted.')));

      if (invite.intendedRole == UserRole.counselor) {
        context.go(AppRoute.counselorSetup);
      } else {
        context.go(AppRoute.home);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _syncConnectedState(UserInvite invite) async {
    final startedAt = DateTime.now();
    final inviteId = invite.id.trim();

    while (mounted &&
        DateTime.now().difference(startedAt) < const Duration(seconds: 3)) {
      ref.invalidate(pendingUserInviteProvider);
      ref.invalidate(pendingUserInvitesProvider);
      if (inviteId.isNotEmpty) {
        ref.invalidate(pendingUserInviteByIdProvider(inviteId));
        ref.invalidate(inviteByIdProvider(inviteId));
      }
      await ref.read(currentUserProfileProvider.notifier).refreshProfile();
      final profile = ref.read(currentUserProfileProvider).valueOrNull;
      final institutionReady =
          (profile?.institutionId ?? '').trim() == invite.institutionId;
      final roleReady = profile?.role == invite.intendedRole;
      if (institutionReady && roleReady) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _decline(UserInvite invite) async {
    setState(() => _isSubmitting = true);
    try {
      await ref.read(institutionRepositoryProvider).declineInvite(invite);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite declined.')));
      context.go(AppRoute.home);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authStateChangesProvider).valueOrNull;
    final inviteId = widget.inviteId?.trim() ?? '';
    final fallbackInviteAsync = ref.watch(pendingUserInviteProvider);
    final rawInviteAsync = inviteId.isEmpty
        ? const AsyncValue<UserInvite?>.data(null)
        : ref.watch(inviteByIdProvider(inviteId));

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

    final inviteAsync = inviteId.isEmpty
        ? fallbackInviteAsync
        : ref.watch(pendingUserInviteByIdProvider(inviteId));

    return MindNestShell(
      child: inviteAsync.when(
        data: (invite) {
          final resolvedInvite = invite ?? fallbackInviteAsync.valueOrNull;
          final rawInvite = rawInviteAsync.valueOrNull;
          final profile = ref.watch(currentUserProfileProvider).valueOrNull;
          final userInstitutionId = (profile?.institutionId ?? '').trim();

          if (userInstitutionId.isNotEmpty &&
              resolvedInvite != null &&
              userInstitutionId == resolvedInvite.institutionId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showModernBanner(
                context,
                message: 'You already joined this institution.',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF0E9B90),
              );
              context.go(AppRoute.home);
            });
            return const SizedBox.shrink();
          }

          if (resolvedInvite == null) {
            if (rawInvite != null && rawInvite.inviteeUid != authUser.uid) {
              return GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Invite belongs to another account',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This invite is linked to a different user. Please sign out and open the link after signing in as the invited account.',
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () =>
                            confirmAndLogout(context: context, ref: ref),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Stack(
                  children: [
                    const _InviteUnavailableBackground(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Lottie.asset(
                            'assets/loading/loading.json',
                            height: 160,
                            repeat: true,
                            frameRate: FrameRate.max,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Invite unavailable',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0B1A2F),
                              ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'This invite is no longer active. It may be expired, revoked, or already handled.',
                          style: TextStyle(
                            color: Color(0xFF4B5563),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          final roleLabel = resolvedInvite.intendedRole.label;
          final shouldPrefillCode =
              resolvedInvite.intendedRole == UserRole.counselor;
          final institutionDoc = ref.watch(
            institutionDocumentProvider(resolvedInvite.institutionId),
          );
          final joinCode =
              (institutionDoc.valueOrNull?['joinCode'] as String? ?? '').trim();

          if (shouldPrefillCode && joinCode.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final normalized = joinCode.toUpperCase();
              if (_codeController.text.trim() != normalized) {
                _codeController.text = normalized;
              }
            });
          }

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
                  Text('Institution: ${resolvedInvite.institutionName}'),
                  const SizedBox(height: 4),
                  Text('Role: $roleLabel'),
                  const SizedBox(height: 4),
                  Text(
                    'Expires: ${resolvedInvite.expiresAt?.toLocal() ?? '--'}',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    obscureText: shouldPrefillCode,
                    enableSuggestions: !shouldPrefillCode,
                    autocorrect: false,
                    readOnly: shouldPrefillCode,
                    obscuringCharacter: '•',
                    decoration: InputDecoration(
                      labelText: 'Institution code',
                      hintText: shouldPrefillCode
                          ? 'Code auto-filled from invite'
                          : 'Enter code from admin',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: shouldPrefillCode
                          ? const Icon(Icons.visibility_off_rounded)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Code is required to join, even with an invite.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _accept(resolvedInvite),
                    child: Text(
                      _isSubmitting ? 'Accepting...' : 'Accept invite',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _decline(resolvedInvite),
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

class _InviteUnavailableBackground extends StatefulWidget {
  const _InviteUnavailableBackground();

  @override
  State<_InviteUnavailableBackground> createState() =>
      _InviteUnavailableBackgroundState();
}

class _InviteUnavailableBackgroundState
    extends State<_InviteUnavailableBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _InviteBlurPainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

class _InviteBlurPainter extends CustomPainter {
  const _InviteBlurPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);

    paint.color =
        Color.lerp(
          const Color(0xFF9BDCF3),
          const Color(0xFF8EEAD5),
          progress,
        ) ??
        const Color(0xFF9BDCF3);
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.15),
      120,
      paint,
    );

    paint.color =
        Color.lerp(
          const Color(0xFF9AB5FF),
          const Color(0xFFB3C7FF),
          1 - progress,
        ) ??
        const Color(0xFF9AB5FF);
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.28),
      110,
      paint,
    );

    paint.color =
        Color.lerp(
          const Color(0xFFA5F3FC),
          const Color(0xFF92FCE1),
          progress,
        ) ??
        const Color(0xFFA5F3FC);
    canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.8), 140, paint);
  }

  @override
  bool shouldRepaint(covariant _InviteBlurPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
